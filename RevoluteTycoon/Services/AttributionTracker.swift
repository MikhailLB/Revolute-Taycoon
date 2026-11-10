import AdSupport
import AppTrackingTransparency
import AppsFlyerLib
import Foundation
import UIKit

/// AppsFlyer attribution. Mirrors this layer:
/// requests ATT, starts the SDK, captures the install / reopen / deep-link
/// payloads, repairs a first-run Organic false-positive via the GCD API, and
/// composes the flat config-request body (every AppsFlyer key passed through
/// verbatim).
final class AttributionTracker: NSObject, AppsFlyerLibDelegate, DeepLinkDelegate {
    private let agent: NetworkClient

    private var install: [String: Any]?
    private var reopen: [String: Any]?
    private var deepLink: [String: Any]?

    private let installReady = OnceLatch()
    private let deepLinkReady = OnceLatch()
    private var started = false
    private var gcdSnapshot: [String: Any]?

    /// Fires when the AppsFlyer delegate hands over install data. The
    /// coordinator uses it to re-POST the config body if the initial pipeline
    /// POST went out without AF data (slow cold handshake).
    var onLateInstall: (() -> Void)?

    /// True once we hold any attribution payload worth sending with a POST.
    var hasInstall: Bool { !(install?.isEmpty ?? true) }

    init(agent: NetworkClient) {
        self.agent = agent
        super.init()
    }

    // MARK: Start

    func start() {
        guard RemoteStore.ready, !started else {
            if !RemoteStore.ready { completeEmpty() }
            return
        }
        started = true
        let af = AppsFlyerLib.shared()
        af.appsFlyerDevKey = RemoteStore.appsFlyerKey
        af.appleAppID = RemoteStore.storeId
        af.delegate = self
        af.deepLinkDelegate = self
        // Give the ATT prompt time to resolve before attribution fires.
        af.waitForATTUserAuthorization(timeoutInterval: 4)
        af.start()
        // Safety: never let the deep-link latch hang the pipeline.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Tunables.deepLinkTimeout * 1_000_000_000))
            self?.deepLinkReady.signal()
        }
    }

    func requestTrackingIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined
        else { return }
        // iOS silently drops the request if the app is not active — wait a beat
        // after the first frame.
        try? await Task.sleep(nanoseconds: Tunables.attDelayMs * 1_000_000)
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    // MARK: Signals

    func awaitSignals(installTimeout: TimeInterval) async {
        start()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await awaitLatch(self.installReady, timeout: installTimeout) }
            group.addTask { await awaitLatch(self.deepLinkReady, timeout: Tunables.deepLinkTimeout) }
            await group.waitForAll()
        }
        // The SDK can time out with nothing (e.g. slow first launch). If so, ask
        // the GCD endpoint directly before we compose the body — but under a
        // hard deadline so a stalled connection can't hold the launch here.
        // The lookup is memoised, so if it does land late the next caller
        // (the background conversion callback) still reuses it.
        if install == nil || (install?.isEmpty ?? true) {
            let late: [String: Any]? = await withDeadline(seconds: Tunables.installFallbackTimeout) {
                [weak self] in await self?.fetchGcd() ?? nil
            } ?? nil
            if let late { install = late }
        }
    }

    var appsFlyerId: String? { AppsFlyerLib.shared().getAppsFlyerUID() }

    // MARK: Compose body

    func compose(locale: String, pushToken: String?) async -> [String: Any] {
        // All body field names come from the Rust vault — the strings
        // "af_id" / "store_id" / "push_token" / "firebase_project_id" /
        // "sub_id_10" / "bundle_id" / "os" / "locale" never appear as
        // plaintext in the Swift binary (static-analysis graph marker).
        let keys = RemoteStore.bodyKeys
        var body: [String: Any] = [:]
        if let install { body.merge(install) { current, _ in current } }
        if let reopen { reopen.forEach { body[$0.key] = body[$0.key] ?? $0.value } }
        if let deepLink { deepLink.forEach { body[$0.key] = body[$0.key] ?? $0.value } }

        if !keys.afId.isEmpty {
            body[keys.afId] = appsFlyerId ?? body[keys.afId] ?? ""
        }
        if !keys.bundleId.isEmpty {
            body[keys.bundleId] = Bundle.main.bundleIdentifier ?? ""
        }
        if !keys.os.isEmpty { body[keys.os] = RemoteStore.osValue }
        if !keys.storeId.isEmpty { body[keys.storeId] = RemoteStore.storeToken }
        if !keys.locale.isEmpty { body[keys.locale] = locale }

        if let pushToken, !pushToken.isEmpty, !RemoteStore.firebaseSenderId.isEmpty {
            if !keys.pushToken.isEmpty { body[keys.pushToken] = pushToken }
            if !keys.firebaseProjectId.isEmpty {
                body[keys.firebaseProjectId] = RemoteStore.firebaseSenderId
            }
        }

        if ATTrackingManager.trackingAuthorizationStatus == .authorized,
           !keys.subId10.isEmpty
        {
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            if !idfa.isEmpty, !idfa.hasPrefix("00000000-") {
                body[keys.subId10] = idfa
            }
        }
        debugTrace("payload \(body)")
        return body
    }

    // MARK: AppsFlyerLibDelegate

    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        let received = flat(data)
        let status = (received["af_status"] as? String)
        debugTrace("conversion af_status=\(status ?? "nil") keys=\(received.keys)")
        // Signal immediately with whatever the SDK handed us. Previously an
        // "Organic" verdict slept `organicRecheckSeconds` (8 s) before
        // signalling, which meant every organic launch burned the full
        // `awaitSignals` timeout even on a fast network. The old GCD recheck
        // only mattered for a late re-POST that no longer exists, so dropping
        // it makes organic launches resolve the moment the callback lands.
        install = received
        installReady.signal()
        onLateInstall?()
    }

    func onConversionDataFail(_ error: Error) {
        debugTrace("conversion fail \(error.localizedDescription)")
        // Don't give up: the GCD lookup often succeeds where the callback failed.
        Task { [weak self] in
            guard let self else { return }
            self.install = await self.fetchGcd() ?? [:]
            self.installReady.signal()
            if self.hasInstall { self.onLateInstall?() }
        }
    }

    func onAppOpenAttribution(_ attributionData: [AnyHashable: Any]) {
        reopen = flat(attributionData)
    }

    func onAppOpenAttributionFailure(_ error: Error) {
        debugTrace("reopen fail \(error.localizedDescription)")
    }

    // MARK: DeepLinkDelegate

    func didResolveDeepLink(_ result: DeepLinkResult) {
        if let event = result.deepLink?.clickEvent {
            deepLink = flat(event)
        }
        deepLinkReady.signal()
    }

    // MARK: Helpers

    private func flat(_ raw: [AnyHashable: Any]) -> [String: Any] {
        var map: [String: Any] = [:]
        for (k, v) in raw { map["\(k)"] = v }
        if let payload = map["payload"] as? [String: Any] { return payload }
        return map
    }

    /// Direct install-data lookup (GCD v5). Tried twice with a short gap — the
    /// first call right after `start()` frequently races the server — and the
    /// result is memoised so repeated callers don't hammer the endpoint.
    /// `app_id` must be the bare numeric id (no `id` prefix), otherwise GCD 404s.
    private func fetchGcd() async -> [String: Any]? {
        if let gcdSnapshot { return gcdSnapshot }
        guard let uid = appsFlyerId, !uid.isEmpty else { return nil }
        let base = RemoteStore.gcdBase
        guard !base.isEmpty else { return nil }
        let sep = base.contains("?") ? "&" : "?"
        guard let url = URL(string: "\(base)\(sep)app_id=\(RemoteStore.storeId)&device_id=\(uid)")
        else { return nil }
        let auth = ["Authorization": "\(RemoteStore.authPrefix)\(RemoteStore.appsFlyerKey)"]

        for attempt in 0 ..< 2 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
            }
            do {
                let (data, response) = try await agent.get(url, headers: auth)
                guard response.statusCode == 200,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      !obj.isEmpty
                else { continue }
                gcdSnapshot = obj
                return obj
            } catch {
                continue
            }
        }
        return nil
    }

    private func completeEmpty() {
        installReady.signal()
        deepLinkReady.signal()
    }
}

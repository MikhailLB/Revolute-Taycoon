import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

/// Push subsystem: Firebase (sender) + APNs + notification taps. Mirrors the
/// this layer. Owns the FCM token, surfaces cold-start /
/// foreground push destinations, and drives the opt-in permission flow.
final class PushCenter: NSObject, MessagingDelegate, UNUserNotificationCenterDelegate {
    private let session: SessionCache
    let enabled: Bool

    private var booted = false
    private(set) var token: String?

    /// Called when a push is tapped while the WebView is already on screen.
    var onForegroundDestination: ((String) -> Void)?
    /// Called when a push tap should route a non-portal session into the WebView.
    var onColdLaunchUrl: ((String) -> Void)?
    /// Called when the FCM token changes (triggers a config re-POST).
    var onTokenChanged: ((String) -> Void)?

    init(session: SessionCache, enabled: Bool) {
        self.session = session
        self.enabled = enabled
        super.init()
    }

    func boot() async {
        guard enabled, !booted else { return }
        booted = true
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        await waitForApns(attempts: Tunables.apnsPollCount,
                          stepMs: Tunables.apnsPollStepMs)
        token = try? await Messaging.messaging().token()
        if let token, !token.isEmpty { debugTrace("fcm token ready") }
    }

    private func waitForApns(attempts: Int, stepMs: UInt64) async {
        for _ in 0 ..< attempts {
            if Messaging.messaging().apnsToken != nil { return }
            try? await Task.sleep(nanoseconds: stepMs * 1_000_000)
        }
    }

    // MARK: Permission

    func canOfferPermission() async -> Bool {
        guard enabled, !session.pushDeniedByOs else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            session.markPushDeniedByOs()
            return false
        case .notDetermined, .provisional:
            return true
        default:
            return false
        }
    }

    func askPermission() async -> Bool {
        guard enabled else { return false }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        // Note: we do NOT overwrite `pushAllowed` here — that flag now
        // reflects the user's choice on OUR promo screen, not the OS verdict.
        // The OS denial is tracked separately via `markPushDeniedByOs`.
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            await waitForApns(attempts: Tunables.apnsPollCountAfterConsent,
                              stepMs: Tunables.apnsPollStepAfterConsentMs)
            token = try? await Messaging.messaging().token()
            if let token, !token.isEmpty { onTokenChanged?(token) }
        } else {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied { session.markPushDeniedByOs() }
        }
        return granted
    }

    // MARK: MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        token = fcmToken
        onTokenChanged?(fcmToken)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let url = Self.extractUrl(userInfo) else { return }
        if let handler = onForegroundDestination {
            handler(url)
        } else if let cold = onColdLaunchUrl {
            // Also persist so an even earlier consume in the coordinator wins.
            UserDefaults.standard.set(url, forKey: RemoteStore.launchRouteKey)
            cold(url)
        } else {
            UserDefaults.standard.set(url, forKey: RemoteStore.launchRouteKey)
            session.stashPushUrl(url)
        }
    }

    // MARK: URL extraction (top-level, nested containers, last-resort scan)

    static func extractUrl(_ payload: [AnyHashable: Any]) -> String? {
        // 1. Named destination fields, in order of preference. The field
        //    names come from the Rust vault (comma-joined), so the list never
        //    appears in the Swift binary as a plaintext array literal.
        for key in RemoteStore.pushUrlKeys {
            if let raw = payload[key] as? String, let usable = normalize(raw) {
                return usable
            }
        }
        // 2. Recurse into the usual nesting containers.
        for container in ["payload", "data", "aps"] {
            if let nested = payload[container] as? [AnyHashable: Any],
               let found = extractUrl(nested) {
                return found
            }
        }
        // 3. Fall back to any value that plainly looks like an http(s) link,
        //    skipping the standard APNs/FCM bookkeeping keys.
        let skip = RemoteStore.pushSkipKeys
        for (rawKey, value) in payload {
            guard let key = rawKey as? String, !skip.contains(key) else { continue }
            if let str = value as? String, looksLikeLink(str), let usable = normalize(str) {
                return usable
            }
        }
        return nil
    }

    /// Accepts a well-formed http(s) URL, and promotes a bare `host/path` to
    /// https. Returns nil for anything without a real host.
    private static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if let u = URL(string: trimmed),
           let scheme = u.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           !(u.host ?? "").isEmpty {
            return trimmed
        }
        if trimmed.contains("."),
           let u = URL(string: "https://\(trimmed)"),
           !(u.host ?? "").isEmpty {
            return "https://\(trimmed)"
        }
        return nil
    }

    private static func looksLikeLink(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }
}

import FirebaseCore
import FirebaseMessaging
import Foundation
import Observation
import UIKit
import UserNotifications

/// Top-level launch controller. Assembles the services, drives the boot
/// pipeline, publishes the current `Phase` for `RootFlowView` to render and
/// keeps the device orientation lock in sync (portrait for the native game,
/// free for every gray-flow screen). Singleton so the app delegate (push
/// callbacks) and the SwiftUI view hierarchy share one instance.
@MainActor
@Observable
final class LaunchModel {
    static let shared = LaunchModel()

    enum Phase: Equatable {
        case idle
        case booting
        case native
        case promo(url: String)
        case hosted(url: String, cold: Bool)
        case offline
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0

    private var session: SessionCache!
    private var probe: Reachability!
    private var agent: NetworkClient!
    private var attribution: AttributionTracker!
    private var exchange: ConfigService!
    private var signal: PushCenter!
    private var coordinator: LaunchCoordinator!
    private var configured = false
    private var started = false
    private var heartbeat: Task<Void, Never>?
    /// Set once a cold-start push tap has pinned the web shell to its own URL.
    /// While true the config pipeline is not allowed to repaint the screen, so
    /// a tap-launched session always lands on the push URL, never the config
    /// destination that the parallel POST resolves a moment later.
    private var pushRouteCommitted = false

    /// Services that may run (Firebase requires a real GoogleService-Info.plist).
    private(set) var firebaseReady = false

    private init() {}

    // MARK: Launch-time configuration (called from the app delegate)

    func configure() {
        guard !configured else { return }
        configured = true

        session = SessionCache()
        agent = NetworkClient()
        probe = Reachability()
        probe.start()

        if RemoteStore.ready, hasFirebaseConfig() {
            FirebaseApp.configure()
            firebaseReady = true
        }

        signal = PushCenter(session: session, enabled: firebaseReady)
        attribution = AttributionTracker(agent: agent)
        exchange = ConfigService(agent: agent, session: session)
        coordinator = LaunchCoordinator(
            session: session,
            probe: probe,
            attribution: attribution,
            exchange: exchange,
            signal: signal,
            agent: agent,
            runtimeEnabled: RemoteStore.ready
        )

        probe.onLost = { /* WebHostView subscribes directly when mounted */ }
        signal.onColdLaunchUrl = { [weak self] url in
            Task { @MainActor in self?.routeToHosted(url: url, cold: true) }
        }

        if firebaseReady {
            // Set the notification + messaging delegates early so a cold-start
            // push tap is captured before the SwiftUI gate runs its pipeline.
            Messaging.messaging().delegate = signal
            UNUserNotificationCenter.current().delegate = signal
            UIApplication.shared.registerForRemoteNotifications()
        }

        // Fire up AppsFlyer the moment services exist, in parallel with
        // Firebase init, reachability settling and the first loading-screen
        // frame — the SDK's cold-start handshake is on the critical path to
        // the config POST, so every ms it saves trims total launch latency.
        // Idempotent: the pipeline's own `start()` later becomes a no-op.
        // Safe on an offline launch: if the SDK's one-shot delegate fails,
        // `AttributionTracker.awaitSignals` falls back to the GCD REST call
        // on the retry that follows a successful reachability probe.
        if RemoteStore.ready {
            Task { [attribution] in attribution?.start() }
        }
    }

    private func hasFirebaseConfig() -> Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    // MARK: APNs plumbing (forwarded from the app delegate)

    func setApnsToken(_ token: Data) {
        guard firebaseReady else { return }
        Messaging.messaging().apnsToken = token
    }

    /// Cold-start push payload handed over by the app delegate. If it carries a
    /// destination we stash it so the coordinator routes straight into the web
    /// shell on this very launch.
    func captureColdPush(_ payload: [AnyHashable: Any]) {
        guard let url = PushCenter.extractUrl(payload) else { return }
        UserDefaults.standard.set(url, forKey: RemoteStore.launchRouteKey)
        session?.stashPushUrl(url)
    }

    // MARK: SwiftUI entry

    /// Returns true if the launch flow is inert — the app should render the white
    /// part immediately with zero overhead (identical to the base game).
    var isWhiteOnly: Bool { !(coordinator?.enabled ?? false) }

    func begin() {
        guard !started else { return }
        started = true
        if isWhiteOnly {
            // Native-only build: decode the game catalog off the main thread so
            // the first game frame doesn't hang ~1 s.
            GameStore.warmCatalog()
            transition(to: .native)
            return
        }
        Task { await routeByConnectivity() }
    }

    func retry() {
        if isWhiteOnly { transition(to: .native); return }
        pushRouteCommitted = false
        progress = 0
        enterBooting()
    }

    /// Launch gate: settle connectivity before anything fills the loading bar.
    /// A fresh or returning-web launch needs the network up front — no link
    /// means the offline screen shows immediately, with the bar still at zero.
    /// The one exception is a returning-native user: the game runs offline, so
    /// we drop straight into it (and only re-ask the server when we are online).
    private func routeByConnectivity() async {
        let online = await isReachableAtLaunch()
        // A cold-start push tap can commit the web shell to its URL while we
        // were settling connectivity (the notification delegate fires on its
        // own clock). If it did, the route is already decided — the launch
        // router must not paint native/offline/booting over it, which is what
        // previously stranded the loading screen on a second cold-start push.
        if pushRouteCommitted { return }
        if session.route == .native, !online {
            GameStore.warmCatalog()
            transition(to: .native)
            return
        }
        guard online else {
            transition(to: .offline)
            return
        }
        enterBooting()
    }

    private func enterBooting() {
        // A committed cold-start push route owns the screen for this launch.
        // Re-entering the boot phase here would strand the loading screen,
        // because `applyDestination` then refuses to repaint the pinned route
        // (`guard !pushRouteCommitted`). Bail out and keep the web shell.
        guard !pushRouteCommitted else { return }
        transition(to: .booting)
        startHeartbeat()
        Task { await runPipeline() }
    }

    /// Cheap NWPath snapshot. If the monitor hasn't delivered its first path
    /// yet (it was started at `willFinishLaunching`, so this is rare), give it
    /// one short beat before trusting a negative. No HTTP probe here — the
    /// offline screen's Retry does the authoritative `canReachNetwork` check.
    private func isReachableAtLaunch() async -> Bool {
        if probe.hasInterface { return true }
        try? await Task.sleep(nanoseconds: 260_000_000)
        return probe.hasInterface
    }

    private func runPipeline() async {
        let destination = await coordinator.decide { [weak self] value in
            Task { @MainActor in self?.bumpProgress(to: value) }
        }
        // Freeze the bar at full and give the user ~0.4 s to see it before
        // the screen flips — matches the contract "fills completely only
        // right before we actually switch screens".
        await MainActor.run { bumpProgress(to: 1) }
        try? await Task.sleep(nanoseconds: 420_000_000)
        await applyDestination(destination)
    }

    /// Soft upward-only progress update so the bar never visibly rewinds when
    /// milestones arrive out of order or on a retry.
    private func bumpProgress(to value: Double) {
        let clamped = min(max(value, 0), 1)
        if clamped > progress { progress = clamped }
    }

    /// Slow crawl while the pipeline waits on network/attribution — tops out
    /// at 0.9 so a real milestone always has somewhere to climb to. Cancelled
    /// when the pipeline finishes or the phase moves off `.booting`.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                await MainActor.run { [weak self] in
                    guard let self, self.phase == .booting else { return }
                    let step = max(0.004, (0.9 - self.progress) * 0.025)
                    self.bumpProgress(to: self.progress + step)
                }
            }
        }
    }

    private func applyDestination(_ destination: LaunchTarget) async {
        // A cold-start push tap already pinned the web shell to its URL — don't
        // let the config pipeline's late verdict repaint over it.
        guard !pushRouteCommitted else { return }
        switch destination {
        case .native:
            // Only now, on the native route, warm the game catalog — a web
            // destination never touches native-game components.
            GameStore.warmCatalog()
            transition(to: .native)
        case .offline:
            transition(to: .offline)
        case let .hosted(url, cold):
            if !cold,
               session.shouldShowPushInvite,
               await signal.canOfferPermission() {
                transition(to: .promo(url: url))
            } else {
                transition(to: .hosted(url: url, cold: cold))
            }
        }
    }

    // MARK: Transitions used by the screens

    func routeToHosted(url: String, cold: Bool) {
        // A push tap wins over the config decision for the rest of this launch.
        if cold { pushRouteCommitted = true }
        transition(to: .hosted(url: url, cold: cold))
    }

    func markOffline() {
        transition(to: .offline)
    }

    func promoFinished(url: String) {
        transition(to: .hosted(url: url, cold: false))
    }

    // MARK: Phase + orientation lock

    private func transition(to newPhase: Phase) {
        phase = newPhase
        BootstrapDelegate.applyOrientation(orientationMask(for: newPhase))
        if newPhase != .booting { heartbeat?.cancel(); heartbeat = nil }
    }

    /// Native game is portrait-only; every gray-flow screen (loading, offline,
    /// push promo, web lane) is free to rotate.
    private func orientationMask(for phase: Phase) -> UIInterfaceOrientationMask {
        switch phase {
        case .native: return .portrait
        default:      return .allButUpsideDown
        }
    }

    // MARK: Accessors for the screens

    var sessionRef: SessionCache { session }
    var probeRef: Reachability { probe }
    var signalRef: PushCenter { signal }
    var agentRef: NetworkClient { agent }
}

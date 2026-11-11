import Foundation

/// The routing brain. Decides — once per install, then re-evaluated on each
/// launch — whether to show the web view or the white game, following the
/// this layer state machine exactly.
final class LaunchCoordinator {
    let session: SessionCache
    let probe: Reachability
    let attribution: AttributionTracker
    let exchange: ConfigService
    let signal: PushCenter
    let agent: NetworkClient
    private let runtimeEnabled: Bool

    private var deciding: Task<LaunchTarget, Never>?
    /// Set once the launch decision has produced a route. Guards the push-token
    /// refresh so it can never fire a second POST *during* the decision.
    private var decisionComplete = false
    private var postedToken: String?

    init(
        session: SessionCache,
        probe: Reachability,
        attribution: AttributionTracker,
        exchange: ConfigService,
        signal: PushCenter,
        agent: NetworkClient,
        runtimeEnabled: Bool
    ) {
        self.session = session
        self.probe = probe
        self.attribution = attribution
        self.exchange = exchange
        self.signal = signal
        self.agent = agent
        self.runtimeEnabled = runtimeEnabled
    }

    var enabled: Bool { runtimeEnabled && RemoteStore.ready }

    /// Resolve the ATT consent prompt (first launch only) *before* the budgeted
    /// decision runs, so a slow user tapping through the dialog can't eat into
    /// `decisionBudget` and strand a paid first-launch user on native. No-op on
    /// every later launch, since the status is no longer `.notDetermined`.
    func prepareTracking() async {
        guard enabled else { return }
        await attribution.requestTrackingIfNeeded()
    }

    /// De-dupes only concurrent calls; the cache is cleared on completion so an
    /// offline Retry re-runs the full pipeline.
    func decide(onProgress: @escaping (Double) -> Void) async -> LaunchTarget {
        if let deciding { return await deciding.value }
        let task = Task { () -> LaunchTarget in
            let result = await run(onProgress: onProgress)
            return result
        }
        deciding = task
        // Absolute ceiling on the decision. If a flaky network or a slow SDK
        // handshake drags past the budget, we stop waiting and default to the
        // native game. The task keeps running in the background and still
        // persists whatever route it eventually resolves, so a paid user who
        // was too slow this launch is routed correctly on the next one.
        let value = await withDeadline(seconds: Tunables.decisionBudget) {
            await task.value
        } ?? .native
        deciding = nil
        decisionComplete = true
        return value
    }

    private func run(onProgress: @escaping (Double) -> Void) async -> LaunchTarget {
        guard enabled else {
            onProgress(1)
            return .native
        }
        // A push token that lands *after* the decision (typically when a web
        // user accepts the push promo) delivers itself to the backend with one
        // extra, de-duped POST. During the decision this is inert, so the
        // launch itself still sends exactly one request.
        signal.onTokenChanged = { [weak self] token in self?.refreshForToken(token) }
        // Highest priority: a cold-start push tap.
        if let cold = session.consumeLaunchRoute() {
            session.saveRoute(.hosted)
            _ = session.consumePushUrl()
            Task { await self.backgroundDispatch() }
            onProgress(1)
            return .hosted(url: cold, coldLaunch: true)
        }

        onProgress(0.12)
        switch session.route {
        case .undecided: return await firstDecision(onProgress)
        case .hosted: return await returningHosted(onProgress)
        case .native: return await returningNative(onProgress)
        }
    }

    // MARK: First launch

    private func firstDecision(_ progress: @escaping (Double) -> Void) async -> LaunchTarget {
        guard probe.hasInterface else { return .offline }
        progress(0.24)
        // Push boot (APNs + FCM token) runs in parallel: the token only
        // enriches the config body, so the decision must never block on it —
        // a stalled FCM fetch previously added seconds to every launch.
        let boot = Task { await self.signal.boot() }
        // ATT consent is resolved earlier, outside the decision budget (see
        // `prepareTracking`), so a slow dialog doesn't push the config answer
        // past the budget and strand the user on native.
        progress(0.46)
        await attribution.awaitSignals(installTimeout: Tunables.installSignalsTimeout)
        progress(0.72)
        // Give the parallel push boot a short, bounded chance to finish so the
        // token can ride along on the single POST — but no longer.
        _ = await withDeadline(seconds: Tunables.pushBootGrace) { await boot.value }
        let reply = await requestConfig()
        progress(1)
        if reply.hasDestination, let url = reply.url {
            session.saveRoute(.hosted)
            return .hosted(url: url, coldLaunch: false)
        }
        // POST failed or server rejected → confirm the link is really down
        // before painting the offline screen on a first launch, otherwise
        // a transient 5xx on the first ever request would strand the user
        // on the native game with no attribution ever to follow.
        if !(await probe.canReachNetwork()) { return .offline }
        session.saveRoute(.native)
        return .native
    }

    // MARK: Returning — was WebView

    private func returningHosted(_ progress: @escaping (Double) -> Void) async -> LaunchTarget {
        // Last good URL, used only as a fallback when the server is unreachable.
        let fallback = session.savedUrl

        // A tapped push always wins outright.
        if let pending = session.consumePushUrl(), !pending.isEmpty {
            progress(1)
            return .hosted(url: pending, coldLaunch: false)
        }

        guard probe.hasInterface else {
            return fallback.map { .hosted(url: $0, coldLaunch: false) } ?? .offline
        }

        let boot = Task { await self.signal.boot() }
        await attribution.awaitSignals(installTimeout: Tunables.returningSignalsTimeout)
        _ = await withDeadline(seconds: Tunables.pushBootGrace) { await boot.value }

        // Online → always re-ask the backend; the destination may have moved to
        // a different partner host since the last run, and honouring a stale
        // cached URL here is exactly the behaviour review flags.
        progress(0.6)
        let reply = await requestConfig()
        progress(1)
        if reply.hasDestination, let url = reply.url {
            return .hosted(url: url, coldLaunch: false)
        }
        // Server didn't hand us a URL — fall back to the saved destination so
        // a returning user stays in the web shell. Only drop to offline if we
        // never had one and we can confirm the link is actually down.
        if let fallback { return .hosted(url: fallback, coldLaunch: false) }
        if !(await probe.canReachNetwork()) { return .offline }
        return .offline
    }

    // MARK: Returning — was game

    private func returningNative(_ progress: @escaping (Double) -> Void) async -> LaunchTarget {
        guard probe.hasInterface else { progress(1); return .native }
        let boot = Task { await self.signal.boot() }
        progress(0.55)
        // Wait for the config answer on the same budget as the very first
        // launch (`installSignalsTimeout`) rather than the shorter returning
        // window, so a returning-native user gets the full first-launch-grade
        // chance to be routed into the web shell before we fall back to native.
        await attribution.awaitSignals(installTimeout: Tunables.installSignalsTimeout)
        _ = await withDeadline(seconds: Tunables.pushBootGrace) { await boot.value }
        let reply = await requestConfig()
        progress(1)
        guard reply.hasDestination, let url = reply.url else { return .native }
        session.saveRoute(.hosted)
        return .hosted(url: url, coldLaunch: false)
    }

    // MARK: Config

    /// The single config POST for this launch. The late-install / token-change
    /// re-POST paths were removed deliberately: they fired a second, near-
    /// simultaneous request for every organic launch. The launch now sends
    /// exactly one request with whatever attribution + token arrived inside the
    /// bounded gather window.
    private func requestConfig() async -> ConfigResult {
        let body = await attribution.compose(
            locale: Locale.current.identifier.replacingOccurrences(of: "-", with: "_"),
            pushToken: signal.token
        )
        return await exchange.request(body)
    }

    private func backgroundDispatch() async {
        await signal.boot()
        await attribution.awaitSignals(installTimeout: Tunables.returningSignalsTimeout)
        _ = await requestConfig()
    }

    /// Fires only after the route is decided and only when the token actually
    /// changed — FirebaseMessaging calls the delegate repeatedly per launch
    /// with the same value. This is the web-flow push-opt-in path, never the
    /// organic launch decision.
    private func refreshForToken(_ token: String) {
        // Only the web route ever needs the backend to learn the push token
        // (to target promos). An organic/native launch stays at exactly one
        // request — no token re-POST at all.
        guard decisionComplete, enabled, session.route == .hosted,
              token != postedToken else { return }
        postedToken = token
        Task { [weak self] in
            guard let self else { return }
            _ = await self.requestConfig()
        }
    }
}

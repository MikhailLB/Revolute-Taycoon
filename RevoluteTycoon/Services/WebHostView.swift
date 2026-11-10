import SwiftUI
import UIKit
import WebKit

/// Full-screen WKWebView shell for attributed users. Loads the remote URL,
/// injects one merged "feels native" script into every frame, gates navigation
/// by scheme (no host allowlist — the partner host may change after release),
/// survives redirect loops and transport switches, and lifts focused inputs
/// above the keyboard using the real keyboard frame rather than visualViewport.
struct WebHostView: UIViewControllerRepresentable {
    let url: String
    let coldLaunch: Bool
    let session: SessionCache
    let probe: Reachability
    let signal: PushCenter
    let agent: NetworkClient
    let onOffline: () -> Void

    func makeUIViewController(context: Context) -> WebHostController {
        WebHostController(
            url: url,
            coldLaunch: coldLaunch,
            session: session,
            probe: probe,
            signal: signal,
            agent: agent,
            onOffline: onOffline
        )
    }

    func updateUIViewController(_ controller: WebHostController, context: Context) {
        controller.navigateIfChanged(to: url)
    }
}

final class WebHostController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let initialUrl: String
    private let coldLaunch: Bool
    private let session: SessionCache
    private let probe: Reachability
    private let signal: PushCenter
    private let agent: NetworkClient
    private let onOffline: () -> Void

    private var webView: WKWebView!
    private var bottomPin: NSLayoutConstraint!

    private var redirectHits = 0
    private var networkHits = 0
    private var currentMainUrl: String?
    private var offlineShown = false
    private var coldRefreshDone = false

    init(
        url: String,
        coldLaunch: Bool,
        session: SessionCache,
        probe: Reachability,
        signal: PushCenter,
        agent: NetworkClient,
        onOffline: @escaping () -> Void
    ) {
        initialUrl = url
        self.coldLaunch = coldLaunch
        self.session = session
        self.probe = probe
        self.signal = signal
        self.agent = agent
        self.onOffline = onOffline
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildWebView()
        wireCallbacks()
        observeKeyboard()
        kickOff()
    }

    deinit {
        signal.onForegroundDestination = nil
        probe.onInterfaceChange = nil
        probe.onLost = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func buildWebView() {
        let content = WKUserContentController()
        // The bootstrap script lives encrypted in the Rust vault and is
        // decoded here — nothing of it exists as a Swift string literal.
        let bootstrap = RemoteStore.webInjection
        if !bootstrap.isEmpty {
            content.addUserScript(WKUserScript(
                source: bootstrap,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        }

        let config = WKWebViewConfiguration()
        config.userContentController = content
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.alpha = 0 // revealed on first didFinish to avoid a white flash
        if !agent.userAgent.isEmpty { webView.customUserAgent = agent.userAgent }

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        // Pin on all four sides to the safe-area guide so the page never sits
        // under the notch or the home indicator — the black backdrop behind
        // this view (set by `RootFlowView`) fills the inset gaps.
        let safe = view.safeAreaLayoutGuide
        bottomPin = webView.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safe.topAnchor),
            webView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            bottomPin,
        ])
    }

    private func wireCallbacks() {
        // Push tapped while this screen is live → navigate in place.
        signal.onForegroundDestination = { [weak self] dest in
            guard let self, let u = URL(string: dest) else { return }
            self.webView.load(URLRequest(url: u))
        }
        // Transport switched (Wi-Fi ⇄ cellular / VPN) → the socket is stale.
        probe.onInterfaceChange = { [weak self] in
            guard let self, self.isViewLoaded, self.view.window != nil else { return }
            self.reloadCurrent()
        }
        // Link definitively gone.
        probe.onLost = { [weak self] in self?.confirmThenOffline() }
    }

    private func kickOff() {
        if let pending = session.consumePushUrl(), let u = URL(string: pending) {
            webView.load(URLRequest(url: u))
            return
        }
        guard let u = URL(string: initialUrl) else { return }
        if coldLaunch {
            // Give the compositor a moment so a tap-launched session lays out at
            // the correct size instead of the pre-rotation frame.
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(RemoteStore.webColdSettleMs)
            ) { [weak self] in
                self?.webView.load(URLRequest(url: u))
            }
        } else {
            webView.load(URLRequest(url: u))
        }
    }

    func navigateIfChanged(to target: String) {
        guard isViewLoaded, target != currentMainUrl,
              let u = URL(string: target) else { return }
        webView.load(URLRequest(url: u))
    }

    // MARK: Rotation reflow

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.nudgeReflow()
        }
    }

    private func nudgeReflow() {
        let js = RemoteStore.jsReflow
        guard !js.isEmpty else { return }
        for ms in RemoteStore.webReflowDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
                self?.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    // MARK: Keyboard (native frame, not visualViewport)

    private func observeKeyboard() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(keyboardMoved(_:)),
                       name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardHidden),
                       name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardMoved(_ note: Notification) {
        guard let value = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        else { return }
        let frame = view.convert(value.cgRectValue, from: nil)
        let overlap = max(0, view.bounds.maxY - frame.minY)
        applyKeyboardInset(overlap)
    }

    @objc private func keyboardHidden() {
        applyKeyboardInset(0)
    }

    private func applyKeyboardInset(_ inset: CGFloat) {
        webView.scrollView.contentInset.bottom = inset
        webView.scrollView.verticalScrollIndicatorInsets.bottom = inset
        if inset > 0 {
            let js = RemoteStore.jsFocus
            if !js.isEmpty { webView.evaluateJavaScript(js, completionHandler: nil) }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        // `javascript:` never drives a top-level navigation.
        if scheme == "javascript" { decisionHandler(.cancel); return }
        // Allowed schemes (the list lives encrypted in the Rust vault) stay in
        // the web view.
        if RemoteStore.webSchemes.contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame ?? false {
                currentMainUrl = url.absoluteString
            }
            decisionHandler(.allow)
            return
        }
        // Everything else is a deep link into another app (tel, mailto, sms,
        // itms-apps, tg, and partner app schemes). Hand it to the system
        // unconditionally — gating on canOpenURL silently drops schemes we
        // didn't pre-declare in LSApplicationQueriesSchemes.
        handoffDeepLink(url)
        decisionHandler(.cancel)
    }

    /// Opens an external deep link through the OS and keeps the web view put.
    private func handoffDeepLink(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        redirectHits = 0
        networkHits = 0
        revealWebView()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(RemoteStore.webPostFinishMs)
        ) { [weak self] in
            guard let self else { return }
            let js = RemoteStore.jsReflow
            if !js.isEmpty { self.webView.evaluateJavaScript(js, completionHandler: nil) }
            if self.coldLaunch, !self.coldRefreshDone {
                self.coldRefreshDone = true
                self.webView.reload()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handle(error)
    }

    // MARK: WKUIDelegate — target="_blank" opens in the same view

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let u = navigationAction.request.url else { return nil }
        let scheme = u.scheme?.lowercased() ?? ""
        if RemoteStore.webSchemes.contains(scheme) {
            webView.load(URLRequest(url: u))
        } else if scheme != "javascript" {
            handoffDeepLink(u)
        }
        return nil
    }

    // MARK: Error handling

    private func handle(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return } // superseded navigation

        let desc = error.localizedDescription.lowercased()
        let redirectLoop = ns.code == NSURLErrorHTTPTooManyRedirects
            || desc.contains("too many redirects")
        if redirectLoop, let last = currentMainUrl, redirectHits < RemoteStore.webRedirectRetry {
            redirectHits += 1
            load(last)
            return
        }

        // Transient failure while a link is still present → back off and retry
        // instead of dropping straight to the offline screen.
        if probe.hasInterface, networkHits < RemoteStore.webNetRetry, let last = currentMainUrl {
            networkHits += 1
            let delay = Double(networkHits) * 0.9
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.load(last)
            }
            return
        }

        confirmThenOffline()
    }

    private func load(_ string: String) {
        guard let u = URL(string: string) else { return }
        webView.load(URLRequest(url: u))
    }

    private func reloadCurrent() {
        if let last = currentMainUrl { load(last) } else { load(initialUrl) }
    }

    private func revealWebView() {
        guard webView.alpha < 1 else { return }
        UIView.animate(withDuration: 0.18) { self.webView.alpha = 1 }
    }

    private func confirmThenOffline() {
        guard !offlineShown else { return }
        Task { @MainActor in
            if await probe.canReachNetwork() {
                // False alarm (e.g. transport flip) — reload instead.
                reloadCurrent()
            } else {
                goOffline()
            }
        }
    }

    private func goOffline() {
        guard !offlineShown, isViewLoaded, view.window != nil else { return }
        offlineShown = true
        probe.onLost = nil
        onOffline()
    }
}

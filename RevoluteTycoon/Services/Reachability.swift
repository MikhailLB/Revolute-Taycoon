import Foundation
import Network

/// Connectivity watcher. `hasInterface` is the cheap NWPath snapshot;
/// `canReachNetwork` performs a time-boxed HEAD request to neutral hosts (never
/// our own backend) so a VPN or a not-yet-propagated domain never looks offline.
///
/// Two callbacks are published, both delivered on the main queue:
///   • `onLost`            — the link went down for real;
///   • `onInterfaceChange` — still up, but the active transport flipped
///                           (Wi-Fi ⇄ cellular, or a VPN came up / went down).
/// The web shell uses the latter to force a reload, because WKWebView keeps a
/// dead socket open across a transport switch.
final class Reachability {
    private let monitor = NWPathMonitor()
    private let watchQueue = DispatchQueue(label: "rt.net.watch")
    private let prober: URLSession
    private let probeTimeoutSeconds: TimeInterval

    private var running = false
    private var upPreviously = true
    private var transportTag = ""

    var onLost: (() -> Void)?
    var onInterfaceChange: (() -> Void)?

    init() {
        // Per-probe timeout is vault-sourced (default 1.4s). The resource
        // ceiling is just a hair above so URLSession's own cancellation
        // never races the Swift-level deadline we race against below.
        let ms = RemoteStore.probeTimeoutMs
        probeTimeoutSeconds = Double(ms) / 1000.0
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = probeTimeoutSeconds
        cfg.timeoutIntervalForResource = probeTimeoutSeconds + 0.6
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        prober = URLSession(configuration: cfg)
    }

    func start() {
        guard !running else { return }
        running = true
        transportTag = Self.tag(for: monitor.currentPath)
        monitor.pathUpdateHandler = { [weak self] path in self?.absorb(path) }
        monitor.start(queue: watchQueue)
    }

    var hasInterface: Bool { monitor.currentPath.status == .satisfied }

    // MARK: Path updates

    private func absorb(_ path: NWPath) {
        let up = path.status == .satisfied
        let tag = Self.tag(for: path)

        let wentDown = upPreviously && !up
        let flipped = up && upPreviously && tag != transportTag

        upPreviously = up
        transportTag = tag

        if wentDown {
            DispatchQueue.main.async { [weak self] in self?.onLost?() }
        } else if flipped {
            DispatchQueue.main.async { [weak self] in self?.onInterfaceChange?() }
        }
    }

    /// Stable signature of the currently available transports; a change here
    /// while the link stays up means the OS swapped the route out under us.
    private static func tag(for path: NWPath) -> String {
        path.availableInterfaces
            .map { "\($0.type)" }
            .sorted()
            .joined(separator: "+")
    }

    // MARK: Active reachability

    /// Fires HEAD requests at every neutral probe host IN PARALLEL and resolves
    /// as soon as any one answers (even with a 4xx). Previously the probes ran
    /// sequentially with a 3 s timeout each — a cold simulator that stalled on
    /// both neutral hosts for 7 s would return `false` and flash the offline
    /// screen even with full connectivity. The config endpoint host is added
    /// to the set as the authoritative "can we reach the real backend" check.
    func canReachNetwork() async -> Bool {
        guard hasInterface else { return false }
        var hosts = RemoteStore.probeHosts
        if let endpointHost = URL(string: RemoteStore.endpoint)?.host,
           !endpointHost.isEmpty, !hosts.contains(endpointHost)
        {
            hosts.append(endpointHost)
        }
        guard !hosts.isEmpty else { return true }

        return await withTaskGroup(of: Bool.self) { group in
            for host in hosts {
                group.addTask { [weak self] in
                    guard let self else { return false }
                    return await self.headSucceeds(host)
                }
            }
            for await ok in group where ok {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private func headSucceeds(_ host: String) async -> Bool {
        guard let url = URL(string: "https://\(host)/") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = probeTimeoutSeconds
        do {
            let (_, response) = try await prober.data(for: req)
            guard let http = response as? HTTPURLResponse else { return true }
            return http.statusCode < 500
        } catch {
            return false
        }
    }
}

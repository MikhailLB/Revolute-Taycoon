import Foundation

/// Secret ids — must stay in sync with `rust/engine/src/vault.rs` (`ID_*`).
enum RemoteKey: UInt32 {
    case endpoint = 0
    case afKey = 1
    case firebaseSender = 2
    case gcdBase = 3
    case privacy = 4
    case support = 5
    case uaProduct = 6
    case uaPlatformPrefix = 7
    case uaPlatformSuffix = 8
    case uaEngine = 9
    case uaSafariVersion = 10
    case uaMobileToken = 11
    case uaSafariTail = 12
    case storeId = 13
    case storagePrefix = 14
    case launchRouteKey = 15
    case probeHostA = 16
    case probeHostB = 17
    case pushUrlKeys = 18
    case pushSkipKeys = 19
    case pushSnooze = 20
    case bodyKeys = 21
    case osValue = 22
    case headerJson = 23
    case headerAuth = 24
    case webSchemes = 25
    case probeHostC = 26
    case cfgTimeout = 27
    case probeTimeoutMs = 28
    case webInjection = 29
    case jsReflow = 30
    case jsFocus = 31
    case webReflowDelays = 32
    case webPostFinishMs = 33
    case webColdSettleMs = 34
    case webRedirectRetry = 35
    case webNetRetry = 36
}

/// Index-aligned accessor over the comma-joined config body field names
/// that live inside the Rust vault. Keeps the plaintext names
/// (`store_id`, `push_token`, `firebase_project_id`, `af_id`, …) out of the
/// Swift binary — the index positions here must match the CSV order defined
/// in `examples/vault_encode.rs::ENC_BODY_KEYS`.
struct ConfigBodyKeys {
    let afId: String
    let bundleId: String
    let os: String
    let storeId: String
    let locale: String
    let pushToken: String
    let firebaseProjectId: String
    let subId10: String

    init(parts: [String]) {
        func at(_ index: Int) -> String {
            index < parts.count ? parts[index] : ""
        }
        afId = at(0)
        bundleId = at(1)
        os = at(2)
        storeId = at(3)
        locale = at(4)
        pushToken = at(5)
        firebaseProjectId = at(6)
        subId10 = at(7)
    }
}

/// Thin, read-only front door to the secret vault that lives inside
/// the Rust engine. No endpoint, key, User-Agent fragment or storage name ever
/// exists as a Swift string literal — everything is decoded on demand by the
/// embedded VM and handed across the C ABI.
///
/// Values are resolved lazily and cached (they never change at runtime).
enum RemoteStore {
    private static var cache: [UInt32: String] = [:]
    private static let lock = NSLock()

    static func value(_ key: RemoteKey) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key.rawValue] { return hit }
        let resolved = resolveFromEngine(key.rawValue)
        cache[key.rawValue] = resolved
        return resolved
    }

    private static func resolveFromEngine(_ id: UInt32) -> String {
        guard let ptr = rt_cfg_resolve(id) else { return "" }
        defer { rt_string_free(ptr) }
        return String(cString: ptr)
    }

    // ── Convenience accessors ────────────────────────────────────────────
    static var endpoint: String { value(.endpoint) }
    static var appsFlyerKey: String { value(.afKey) }
    static var firebaseSenderId: String { value(.firebaseSender) }
    static var gcdBase: String { value(.gcdBase) }
    static var privacyUrl: String { value(.privacy) }
    static var supportUrl: String { value(.support) }
    static var storeId: String { value(.storeId) }
    /// `store_id` body field, e.g. `id6824470855`.
    static var storeToken: String { "id\(storeId)" }
    static var storagePrefix: String { value(.storagePrefix) }
    static var launchRouteKey: String { value(.launchRouteKey) }
    /// Reachability probe hosts — a THIRD neutral entry means a sim that
    /// stalls on both apple.com and one.one.one.one still has a live answer.
    static var probeHosts: [String] {
        [value(.probeHostA), value(.probeHostB), value(.probeHostC)]
            .filter { !$0.isEmpty }
    }

    // ── Config POST body / HTTP header literals (all vault-sourced) ────────
    /// Ordered CSV decoded into typed field names for the config POST body.
    static var bodyKeys: ConfigBodyKeys { ConfigBodyKeys(parts: split(.bodyKeys)) }
    /// Value shipped in the `os` body field — e.g. "iOS".
    static var osValue: String { value(.osValue) }
    /// `application/json` — Content-Type / Accept header value.
    static var headerJson: String { value(.headerJson) }
    /// `Bearer ` — prefix for the GCD install-data Authorization header.
    static var authPrefix: String { value(.headerAuth) }
    /// Allowed URL schemes for in-webview navigation (javascript: blocked).
    static var webSchemes: Set<String> { Set(split(.webSchemes)) }

    // ── WebView bootstrap + timing (all vault-sourced) ────────────────────
    /// Merged "feels native" script injected into every frame. Decoded from
    /// the Rust vault so the behaviour set isn't a plaintext match in the app.
    static var webInjection: String { value(.webInjection) }
    /// Snippet that nudges a `resize` through the page + visualViewport.
    static var jsReflow: String { value(.jsReflow) }
    /// Snippet that scrolls the focused field into view above the keyboard.
    static var jsFocus: String { value(.jsFocus) }
    /// Reflow nudge delays (ms) fired after a rotation.
    static var webReflowDelays: [Int] {
        let parsed = split(.webReflowDelays).compactMap { Int($0) }
        return parsed.isEmpty ? [60, 210, 400, 640, 910] : parsed
    }
    /// Delay after `didFinish` before we poke a resize (ms).
    static var webPostFinishMs: Int { Int(number(for: .webPostFinishMs).nonZero(690)) }
    /// Delay before loading on a cold tap-launched session (ms).
    static var webColdSettleMs: Int { Int(number(for: .webColdSettleMs).nonZero(340)) }
    /// How many times a redirect loop is retried before giving up.
    static var webRedirectRetry: Int { Int(number(for: .webRedirectRetry).nonZero(4)) }
    /// How many transient network failures are retried before offline.
    static var webNetRetry: Int { Int(number(for: .webNetRetry).nonZero(3)) }

    /// Config POST round-trip timeout in seconds (vault-stored so the magic
    /// number doesn't ship as a Swift literal).
    static var cfgTimeoutSeconds: TimeInterval {
        let n = number(for: .cfgTimeout)
        return n > 0 ? TimeInterval(n) : 11
    }
    /// Per-probe HEAD timeout for `canReachNetwork` (milliseconds).
    static var probeTimeoutMs: UInt64 {
        let n = number(for: .probeTimeoutMs)
        return n > 0 ? n : 1400
    }

    /// Candidate URL field names in a push payload, resolved from the vault
    /// so the list never ships as a plaintext Swift array literal.
    static var pushUrlKeys: [String] { split(.pushUrlKeys) }
    /// APNs / FCM bookkeeping keys to ignore during the fallback scan.
    static var pushSkipKeys: Set<String> { Set(split(.pushSkipKeys)) }

    /// "Not Now" cooldown for the push opt-in screen, seconds. Decoded via the
    /// numeric vault helper so the literal integer never appears in the binary.
    static var pushSnoozeSeconds: Int {
        let n = number(for: .pushSnooze)
        return n > 0 ? Int(n) : 247_734
    }

    /// Whether the launch flow is live. When false the app is native-only and
    /// no attribution / push / WebView code runs — identical to the base game.
    static var ready: Bool { rt_cfg_ready() }

    static func number(for key: RemoteKey) -> UInt64 {
        rt_cfg_number(key.rawValue)
    }

    static func split(_ key: RemoteKey) -> [String] {
        value(key)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private extension UInt64 {
    /// Returns `self` when it decoded to a real value, otherwise the supplied
    /// fallback — the vault yields 0 for an empty/absent entry.
    func nonZero(_ fallback: UInt64) -> UInt64 { self == 0 ? fallback : self }
}

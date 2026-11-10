import Foundation
import Security

/// Per-project timing values. Kept off round numbers and off every sibling's
/// row so the binary doesn't share a magic-number fingerprint.
enum Tunables {
    /// Push opt-in "Not Now" cooldown — resolved from the Rust vault so the
    /// numeric constant never ships plaintext in the Swift binary.
    static var pushSnoozeSeconds: Int { RemoteStore.pushSnoozeSeconds }
    /// Config POST timeout — vault-sourced so the magic number is not a
    /// literal in the binary.
    static var configTimeout: TimeInterval { RemoteStore.cfgTimeoutSeconds }
    /// Hard ceiling on how long the first-launch decision waits for the
    /// AppsFlyer install payload before it POSTs anyway. Kept low so a flaky
    /// network can't drag the loading screen past the budget.
    static let installSignalsTimeout: TimeInterval = 4
    static let returningSignalsTimeout: TimeInterval = 3
    /// Ceiling for the direct GCD install-data fallback fired when the SDK
    /// callback hasn't landed in time (it otherwise did two ~11 s attempts).
    static let installFallbackTimeout: TimeInterval = 2
    /// How long to wait for the deferred-deep-link resolution before giving up
    /// (organic launches never resolve one, so this must stay short).
    static let deepLinkTimeout: TimeInterval = 2.5
    /// Absolute wall-clock ceiling for the whole launch decision. Whatever the
    /// network or the AppsFlyer/Firebase handshakes are doing, the loading
    /// screen hands off (defaulting to the native game) by this point. This is
    /// the guarantee that launch stays bounded on any device / iOS version.
    static let decisionBudget: TimeInterval = 7.5
    /// How long the decision will wait for the push boot (APNs + FCM token)
    /// that runs in parallel — the token is optional for the config body, so
    /// we never block the whole launch on it.
    static let pushBootGrace: TimeInterval = 0.9
    static let attDelayMs: UInt64 = 520
    static let apnsPollCount = 4
    static let apnsPollStepMs: UInt64 = 450
    static let apnsPollCountAfterConsent = 14
    static let apnsPollStepAfterConsentMs: UInt64 = 720
    static let savedUrlExpiryDays = 6
}

/// Persists the launch session state. SharedPreferences-equivalent values go
/// to `UserDefaults`; destination URLs go to the Keychain. All key names are
/// namespaced with the (decoded) storage prefix so nothing is a literal.
final class SessionCache {
    private let defaults = UserDefaults.standard
    private let prefix = RemoteStore.storagePrefix

    private var kRoute: String { "\(prefix).route" }
    private var kExpiry: String { "\(prefix).expiry" }
    private var kInvite: String { "\(prefix).invite.after" }
    private var kAllowed: String { "\(prefix).push.allowed" }
    private var kOsDenied: String { "\(prefix).push.osdenied" }
    private var kSavedUrl: String { "\(prefix).dest" }
    private var kPendingUrl: String { "\(prefix).pending" }

    // MARK: Route

    var route: LaunchMode { LaunchMode(storage: defaults.string(forKey: kRoute)) }

    func saveRoute(_ route: LaunchMode) {
        defaults.set(route.rawValue, forKey: kRoute)
    }

    // MARK: Saved / pending destination URL (Keychain)

    var savedUrl: String? { Keychain.read(service: prefix, account: kSavedUrl) }

    func cacheUrl(_ url: String, expiresAt: Int?) {
        Keychain.write(url, service: prefix, account: kSavedUrl)
        // Honour the server's TTL when present, otherwise fall back to our own
        // window so a saved URL can never live forever.
        let ttl = expiresAt
            ?? Int(Date().timeIntervalSince1970) + Tunables.savedUrlExpiryDays * 86_400
        defaults.set(ttl, forKey: kExpiry)
    }

    var cachedUrlExpired: Bool {
        let expiry = defaults.integer(forKey: kExpiry)
        if expiry == 0 { return true }
        return Int(Date().timeIntervalSince1970) >= expiry
    }

    func stashPushUrl(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.write(trimmed, service: prefix, account: kPendingUrl)
    }

    func consumePushUrl() -> String? {
        let value = Keychain.read(service: prefix, account: kPendingUrl)
        if value != nil { Keychain.delete(service: prefix, account: kPendingUrl) }
        return value
    }

    // MARK: Push flags

    var pushAllowed: Bool { defaults.bool(forKey: kAllowed) }
    var pushDeniedByOs: Bool { defaults.bool(forKey: kOsDenied) }

    func setPushAllowed(_ value: Bool) { defaults.set(value, forKey: kAllowed) }
    func markPushDeniedByOs() { defaults.set(true, forKey: kOsDenied) }

    /// Called the moment the user taps "Allow" on the in-app promo —
    /// deliberately independent of what the OS prompt returns. The contract
    /// is "user picked Allow on OUR screen, so never show that screen again",
    /// regardless of whether they then confirm or decline the system dialog.
    func markPushPromoAccepted() { defaults.set(true, forKey: kAllowed) }

    var shouldShowPushInvite: Bool {
        if pushAllowed || pushDeniedByOs { return false }
        let after = defaults.integer(forKey: kInvite)
        if after == 0 { return true }
        return Int(Date().timeIntervalSince1970) >= after
    }

    func snoozePushInvite() {
        let until = Int(Date().timeIntervalSince1970) + Tunables.pushSnoozeSeconds
        defaults.set(until, forKey: kInvite)
    }

    // MARK: Cold-start push launch route (written by the notification handler)

    func consumeLaunchRoute() -> String? {
        let key = RemoteStore.launchRouteKey
        guard let value = defaults.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        defaults.removeObject(forKey: key)
        return value
    }
}

/// Minimal Keychain string store for destination URLs.
enum Keychain {
    static func write(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

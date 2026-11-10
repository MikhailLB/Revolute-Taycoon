import Foundation

/// Which experience a returning install has committed to. Opaque raw values so
/// nothing descriptive is written to on-device storage.
enum LaunchMode: String {
    case undecided = "u"
    case hosted = "h"
    case native = "n"

    init(storage: String?) {
        switch storage {
        case "h": self = .hosted
        case "n": self = .native
        default: self = .undecided
        }
    }
}

/// Parsed config-endpoint response.
struct ConfigResult {
    let accepted: Bool
    let url: String?
    let expiresAt: Int?
    let reason: String?

    var hasDestination: Bool { accepted && !(url?.isEmpty ?? true) }

    static func rejected(_ reason: String) -> ConfigResult {
        ConfigResult(accepted: false, url: nil, expiresAt: nil, reason: reason)
    }

    static func parse(_ data: Data) -> ConfigResult {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data),
            let map = obj as? [String: Any]
        else { return .rejected("invalid_response") }
        let url = map["url"] as? String
        var expires: Int?
        if let n = map["expires"] as? NSNumber {
            expires = n.intValue
        } else if let s = map["expires"] as? String {
            expires = Int(s)
        }
        return ConfigResult(
            accepted: (map["ok"] as? Bool) == true,
            url: url,
            expiresAt: expires,
            reason: map["message"] as? String
        )
    }
}

/// Where the boot pipeline decided to send the user.
enum LaunchTarget: Equatable {
    case native
    case hosted(url: String, coldLaunch: Bool)
    case offline
}

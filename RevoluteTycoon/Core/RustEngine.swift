import Foundation

/// Thin owner of the Rust engine handle. All game logic lives on the Rust side.
final class RustEngine {
    struct Flags: OptionSet {
        let rawValue: UInt32
        static let decision = Flags(rawValue: 1)
        static let gameOver = Flags(rawValue: 2)
        static let tampered = Flags(rawValue: 4)
        static let monthClosed = Flags(rawValue: 8)
    }

    private let handle: OpaquePointer

    init(seed: UInt64) {
        handle = rt_engine_new(seed)
    }

    /// Fails when the save is corrupt or was edited outside the game.
    init?(save: Data) {
        let ptr: OpaquePointer? = save.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return rt_engine_load(base, raw.count)
        }
        guard let ptr else { return nil }
        handle = ptr
    }

    deinit {
        rt_engine_free(handle)
    }

    func step(hours: UInt32) -> Flags {
        Flags(rawValue: rt_engine_step(handle, hours))
    }

    func snapshotData() -> Data? {
        Self.take(rt_engine_snapshot(handle))
    }

    func perform(_ action: [String: Any]) -> ActionResult {
        guard let body = try? JSONSerialization.data(withJSONObject: action),
              let json = String(data: body, encoding: .utf8) else {
            return ActionResult(ok: false, message: "Invalid action")
        }
        let reply = json.withCString { rt_engine_action(handle, $0) }
        guard let data = Self.take(reply),
              let result = try? JSONDecoder().decode(ActionResult.self, from: data) else {
            return ActionResult(ok: false, message: "Engine error")
        }
        return result
    }

    func save() -> Data? {
        var len = 0
        guard let ptr = rt_engine_save(handle, &len) else { return nil }
        let data = Data(bytes: ptr, count: len)
        rt_bytes_free(ptr, len)
        return data
    }

    static func catalogData() -> Data? {
        take(rt_catalog())
    }

    private static func take(_ ptr: UnsafeMutablePointer<CChar>?) -> Data? {
        guard let ptr else { return nil }
        let data = Data(bytes: ptr, count: strlen(ptr))
        rt_string_free(ptr)
        return data
    }
}

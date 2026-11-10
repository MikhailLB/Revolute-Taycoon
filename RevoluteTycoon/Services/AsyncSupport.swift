import Foundation

/// Debug-only trace. The closure (and its string literals) are compiled out of
/// Release builds, so no launch log strings ship in the binary.
@inline(__always)
func debugTrace(_ message: @autoclosure () -> String) {
    #if DEBUG
    print("[RT] \(message())")
    #endif
}

/// A one-shot latch that supports awaiting with multiple waiters. Used to wait
/// for the AppsFlyer install / deep-link callbacks.
final class OnceLatch: @unchecked Sendable {
    private var done = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    func signal() {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if done {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// Awaits `latch` but gives up after `timeout` seconds (either way returns).
func awaitLatch(_ latch: OnceLatch, timeout: TimeInterval) async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await latch.wait() }
        group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
        _ = await group.next()
        group.cancelAll()
    }
}

/// Runs `operation` but returns `nil` if it hasn't finished within `seconds`.
/// The launch pipeline uses this to put a hard wall-clock ceiling on any
/// network step (attribution lookup, push boot) so a flaky connection can
/// never stall the loading screen — whatever hasn't arrived in time is simply
/// omitted, and the pipeline moves on.
func withDeadline<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

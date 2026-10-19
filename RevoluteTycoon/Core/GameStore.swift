import Foundation
import Observation
import SwiftUI

enum GameSpeed: Int, CaseIterable, Identifiable {
    case pause = 0, normal, fast, faster, fastest

    var id: Int { rawValue }

    /// In-game hours simulated per real second.
    var hoursPerSecond: Double {
        switch self {
        case .pause: 0
        case .normal: 2
        case .fast: 5
        case .faster: 12
        case .fastest: 30
        }
    }

    var symbol: String {
        switch self {
        case .pause: "pause.fill"
        case .normal: "play.fill"
        case .fast: "forward.fill"
        case .faster: "forward.end.fill"
        case .fastest: "bolt.fill"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let ok: Bool
}

@MainActor
@Observable
final class GameStore {
    private(set) var snapshot: Snapshot?
    let catalog: Catalog
    var speed: GameSpeed = .pause
    var selectedVenueId: Int = 0
    var toast: Toast?
    var integrityAlert = false
    var loadFailed = false
    var hasSave: Bool { FileManager.default.fileExists(atPath: Self.saveURL.path) }

    private var engine: RustEngine?
    private var loop: Task<Void, Never>?
    private var accumulator: Double = 0
    private var lastSavedDay = -1
    private var speedBeforeDecision: GameSpeed = .normal
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static var saveURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("career.rvty")
    }

    init() {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        if let data = RustEngine.catalogData(), let c = try? d.decode(Catalog.self, from: data) {
            catalog = c
        } else {
            catalog = Catalog(items: [], formats: [], licenses: [], cities: [], roles: [], research: [], loans: [])
        }
    }

    var isRunning: Bool { engine != nil }

    var venue: VenueView? {
        guard let s = snapshot else { return nil }
        return s.venue(selectedVenueId) ?? s.venues.first
    }

    // MARK: - Lifecycle

    func newGame() {
        engine = RustEngine(seed: UInt64.random(in: 1...UInt64.max))
        selectedVenueId = 0
        lastSavedDay = -1
        refresh()
        save()
        speed = .normal
        startLoop()
    }

    #if DEBUG
    /// Screenshot harness: `-shot <tab> [-days N]` starts a fresh career, fast-forwards and opens a tab.
    static var debugTab: String? { debugArg("-shot") }

    static func debugArg(_ name: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    func debugBoot() {
        let a = ProcessInfo.processInfo.arguments
        guard Self.debugTab != nil else { return }
        newGame()
        speed = .pause
        if let i = a.firstIndex(of: "-days"), i + 1 < a.count, let days = Int(a[i + 1]), let engine {
            for _ in 0..<days {
                _ = engine.step(hours: 24)
                refresh()
                if snapshot?.decision != nil {
                    if a.contains("-keep") { break }
                    send(["type": "decide", "option": 0], quiet: true)
                }
            }
        }
        speed = .pause
    }
    #endif

    @discardableResult
    func continueGame() -> Bool {
        guard let data = try? Data(contentsOf: Self.saveURL) else { return false }
        guard let e = RustEngine(save: data) else {
            loadFailed = true
            return false
        }
        engine = e
        refresh()
        selectedVenueId = snapshot?.venues.first?.id ?? 0
        lastSavedDay = snapshot?.clock.day ?? -1
        speed = .pause
        startLoop()
        return true
    }

    func quitToMenu() {
        save()
        loop?.cancel()
        loop = nil
        engine = nil
        snapshot = nil
        speed = .pause
    }

    func deleteSave() {
        try? FileManager.default.removeItem(at: Self.saveURL)
    }

    func save() {
        guard let engine, let data = engine.save() else { return }
        try? data.write(to: Self.saveURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        lastSavedDay = snapshot?.clock.day ?? lastSavedDay
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.tick(dt: 0.2)
            }
        }
    }

    private func tick(dt: Double) {
        guard let engine, speed != .pause else { return }
        accumulator += speed.hoursPerSecond * dt
        let hours = UInt32(accumulator)
        guard hours > 0 else { return }
        accumulator -= Double(hours)
        let flags = engine.step(hours: hours)
        refresh()
        if flags.contains(.tampered) {
            speed = .pause
            integrityAlert = true
            return
        }
        if flags.contains(.decision) || flags.contains(.gameOver) {
            if speed != .pause { speedBeforeDecision = speed }
            speed = .pause
        }
        if let day = snapshot?.clock.day, day != lastSavedDay {
            save()
        }
    }

    func refresh() {
        guard let engine, let data = engine.snapshotData() else { return }
        do {
            snapshot = try decoder.decode(Snapshot.self, from: data)
        } catch {
            #if DEBUG
            print("Snapshot decode failed: \(error)")
            #endif
        }
    }

    /// Reload the last good save after an integrity failure.
    func recoverFromTamper() {
        integrityAlert = false
        loop?.cancel()
        engine = nil
        if !continueGame() {
            newGame()
        }
    }

    // MARK: - Actions

    @discardableResult
    func send(_ action: [String: Any], quiet: Bool = false) -> Bool {
        guard let engine else { return false }
        let r = engine.perform(action)
        refresh()
        if !quiet || !r.ok {
            showToast(r.message, ok: r.ok)
        }
        return r.ok
    }

    func decide(_ option: Int) {
        send(["type": "decide", "option": option])
        if snapshot?.decision == nil, speed == .pause {
            speed = speedBeforeDecision
        }
    }

    func showToast(_ text: String, ok: Bool) {
        let t = Toast(text: text, ok: ok)
        withAnimation(.spring(duration: 0.3)) { toast = t }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            if self?.toast == t {
                withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
            }
        }
    }

    func place(_ item: String, x: Int, y: Int) -> Bool {
        send(["type": "place", "venue": selectedVenueId, "item": item, "x": x, "y": y], quiet: true)
    }

    func move(_ id: Int, x: Int, y: Int) -> Bool {
        send(["type": "move", "venue": selectedVenueId, "id": id, "x": x, "y": y], quiet: true)
    }

    func sell(_ id: Int) {
        send(["type": "sell", "venue": selectedVenueId, "id": id])
    }

    func hire(_ role: String, _ count: Int) {
        send(["type": "hire", "venue": selectedVenueId, "role": role, "count": count], quiet: true)
    }
}

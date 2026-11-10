import SwiftUI

@main
struct RevoluteTycoonApp: App {
    @UIApplicationDelegateAdaptor(BootstrapDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            // The game store is NOT created here on purpose: constructing it
            // pulls the full catalog across the Rust FFI and decodes it on the
            // main thread (visible as a ~1 s hang). The webview launch path
            // never renders the game at all, so paying that cost on every
            // launch defeats the loading screen. `NativeShell` defers the
            // construction until SwiftUI actually asks for the white branch.
            RootFlowView { NativeShell() }
        }
    }
}

/// Wraps the native game so `GameStore` is only ever instantiated when the
/// white branch of the root flow becomes visible. For gray-flow (webview)
/// users the catalog is never decoded and no save file is touched.
private struct NativeShell: View {
    @State private var store: GameStore?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if let store {
                RootView()
                    .environment(store)
                    .preferredColorScheme(.dark)
                    .tint(Theme.gold)
            } else {
                // Launch-screen colour matches the native launch asset, so the
                // brief gap between this view appearing and the store's first
                // frame is visually continuous — no white flash.
                Color("LaunchBackground").ignoresSafeArea()
            }
        }
        .onAppear {
            if store == nil { store = GameStore() }
        }
        .onChange(of: phase) { _, p in
            guard let store, p != .active else { return }
            store.save()
            if store.speed != .pause { store.speed = .pause }
        }
    }
}

struct RootView: View {
    @Environment(GameStore.self) private var store
    @AppStorage("accepted_notice_v1") private var acceptedNotice = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if !acceptedNotice {
                OnboardingView { acceptedNotice = true }
                    .transition(.opacity)
            } else if store.isRunning, store.snapshot != nil {
                GameView()
                    .transition(.opacity)
            } else {
                MenuView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.isRunning)
        .animation(.easeInOut(duration: 0.35), value: acceptedNotice)
        #if DEBUG
        .task {
            if GameStore.debugTab != nil {
                acceptedNotice = true
                store.debugBoot()
            }
        }
        #endif
    }
}

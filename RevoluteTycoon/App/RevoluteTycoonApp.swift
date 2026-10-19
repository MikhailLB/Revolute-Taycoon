import SwiftUI

@main
struct RevoluteTycoonApp: App {
    @State private var store = GameStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .onChange(of: phase) { _, p in
            if p != .active {
                store.save()
                if store.speed != .pause { store.speed = .pause }
            }
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

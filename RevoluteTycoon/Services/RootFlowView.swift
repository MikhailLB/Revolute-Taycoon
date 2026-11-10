import SwiftUI

/// Root gate for the whole app. Renders the native game unchanged for organic
/// users, the staged loading screen while the pipeline runs, and the web +
/// support screens for attributed users. When the launch flow is disabled
/// (no credentials) it renders the white content immediately with no boot
/// overhead, so the base game stays byte-for-byte unaffected.
struct RootFlowView<White: View>: View {
    @State private var flow = LaunchModel.shared
    @ViewBuilder var white: () -> White

    var body: some View {
        content
            .task { flow.begin() }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .idle, .booting:
            LoadingView(progress: flow.progress)
                .transition(.opacity)
        case .native:
            white()
                .transition(.opacity)
        case let .promo(url):
            PushOptInView(
                url: url,
                session: flow.sessionRef,
                signal: flow.signalRef,
                onFinish: { flow.promoFinished(url: url) }
            )
            .transition(.opacity)
        case let .hosted(url, cold):
            ZStack {
                Color.black.ignoresSafeArea()
                WebHostView(
                    url: url,
                    coldLaunch: cold,
                    session: flow.sessionRef,
                    probe: flow.probeRef,
                    signal: flow.signalRef,
                    agent: flow.agentRef,
                    onOffline: { flow.markOffline() }
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .statusBarHidden(true)
            .transition(.opacity)
        case .offline:
            OfflineView(
                probe: flow.probeRef,
                onRecovered: { flow.retry() }
            )
            .transition(.opacity)
        }
    }
}

// MARK: - Loading screen

/// Shown while the pipeline runs (both the native-bound and the webview-bound
/// path). Fills the full window in both orientations; the headline block sits
/// in the top third while the "Loading…" row + progress bar hug the bottom
/// safe area, so a short landscape viewport never clips them.
struct LoadingView: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                LinearGradient(
                    colors: [Theme.bgDeep, Color(hex: 0x241047)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer(minLength: wide ? 18 : 48)
                    Crest(mark: wide ? 84 : 118)
                    Spacer(minLength: 24)
                    bottomBlock(width: geo.size.width, wide: wide)
                        .padding(.bottom, wide ? 22 : 40)
                        .padding(.horizontal, wide ? 48 : 32)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private func bottomBlock(width: CGFloat, wide: Bool) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Loading")
                    .font(.system(size: wide ? 20 : 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                LoadingDots()
            }
            ProgressTrack(value: progress)
                .frame(height: 10)
                .frame(maxWidth: min(width - 64, 420))
            Text("\(Int((min(max(progress, 0), 1)) * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.dim)
        }
    }
}

/// Casino-chip crest used on the menu — repeated here so the launch and the
/// menu screen share a single mark instead of flashing two different logos.
private struct Crest: View {
    var mark: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            LogoMark(size: mark)
            Text("REVOLUTE")
                .font(.system(size: mark * 0.31, weight: .black, design: .rounded))
                .tracking(mark * 0.045)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.gold, Color(hex: 0xFFE9A8), Theme.goldDeep],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            Text("TYCOON")
                .font(.system(size: mark * 0.16, weight: .heavy, design: .rounded))
                .tracking(mark * 0.11)
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}

/// Three dots that advance in sequence — CPU-cheap, no `Timer.publish` churn,
/// animation driven by `TimelineView` so iOS can throttle it when occluded.
private struct LoadingDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.33)) { tl in
            let phase = Int(tl.date.timeIntervalSinceReferenceDate / 0.33) % 3
            HStack(spacing: 5) {
                ForEach(0 ..< 3, id: \.self) { i in
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == i ? 1.35 : 0.72)
                        .opacity(phase == i ? 1 : 0.45)
                        .animation(.easeInOut(duration: 0.28), value: phase)
                }
            }
        }
    }
}

/// Capsule-shaped bar with an animated fill. `.animation(value:)` smooths the
/// discrete pipeline milestones into a visible glide instead of hard jumps.
private struct ProgressTrack: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            let w = max(10, geo.size.width * CGFloat(min(max(value, 0), 1)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.gold, Color(hex: 0xFFC658), Theme.goldDeep],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: w)
                    .shadow(color: Theme.gold.opacity(0.55), radius: 6, y: 0)
                    .animation(.easeOut(duration: 0.38), value: value)
            }
        }
    }
}

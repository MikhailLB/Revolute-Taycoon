import SwiftUI

/// No-internet screen. Retry is never trusted on faith — the button only fires
/// `onRecovered` after a real reachability probe succeeds; otherwise it resets
/// and shows a "still offline" hint so the button never gets stuck disabled.
struct OfflineView: View {
    let probe: Reachability
    let onRecovered: () -> Void

    @State private var checking = false
    @State private var stillOffline = false

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

                if wide {
                    landscapeBody(geo: geo)
                } else {
                    portraitBody(geo: geo)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Layouts

    private func portraitBody(geo: GeometryProxy) -> some View {
        VStack(spacing: 24) {
            Spacer()
            badge(size: 148, icon: 60)
            copy(titleSize: 24, alignment: .center)
                .padding(.horizontal, 28)

            if stillOffline {
                Text("No connection yet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.orange)
                    .transition(.opacity)
            }

            Spacer()
            retryButton
                .frame(maxWidth: min(geo.size.width - 64, 420))
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
    }

    private func landscapeBody(geo: GeometryProxy) -> some View {
        HStack(spacing: 28) {
            badge(size: 116, icon: 46)
            VStack(alignment: .leading, spacing: 14) {
                copy(titleSize: 19, alignment: .leading)
                if stillOffline {
                    Text("No connection yet")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.orange)
                }
                retryButton
                    .frame(maxWidth: min(geo.size.width * 0.45, 320))
            }
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pieces

    private func badge(size: CGFloat, icon: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Theme.red.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: "wifi.slash")
                .font(.system(size: icon, weight: .bold))
                .foregroundStyle(Theme.red)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func copy(titleSize: CGFloat, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 12) {
            Text("NO INTERNET CONNECTION")
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .foregroundStyle(.white)
            Text("Check your connection and try again")
                .font(.system(size: 16, weight: .medium))
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .foregroundStyle(Theme.dim)
        }
    }

    private var retryButton: some View {
        Button(action: retry) {
            HStack(spacing: 10) {
                if checking {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(checking)
    }

    // MARK: Action

    private func retry() {
        guard !checking else { return }
        checking = true
        stillOffline = false
        Task {
            let online = await probe.canReachNetwork()
            await MainActor.run {
                if online {
                    onRecovered()
                } else {
                    checking = false
                    withAnimation { stillOffline = true }
                }
            }
        }
    }
}

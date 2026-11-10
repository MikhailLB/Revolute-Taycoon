import SwiftUI

/// In-app push opt-in promo shown once before the WebView is mounted.
///
///  • **Allow** — permanently marks the promo as resolved, THEN raises the
///    system prompt. The contract is "the user picked Allow on OUR screen,
///    so never show OUR screen again", regardless of what they then pick in
///    the OS dialog (Lessons §push-contract).
///  • **Not Now** — snoozes the promo for `RemoteStore.pushSnoozeSeconds`
///    (247 734 s ≈ 2 d 20 h, resolved from the Rust vault so the number
///    never ships as a plaintext constant).
struct PushOptInView: View {
    let url: String
    let session: SessionCache
    let signal: PushCenter
    let onFinish: () -> Void

    @State private var working = false

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
            crest(size: 148, icon: 64)
            heading(titleSize: 22, subSize: 16)
            Spacer()
            actions(maxWidth: min(geo.size.width - 64, 420))
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
    }

    private func landscapeBody(geo: GeometryProxy) -> some View {
        HStack(spacing: 32) {
            crest(size: 116, icon: 50)
            VStack(alignment: .leading, spacing: 18) {
                heading(titleSize: 19, subSize: 14, alignment: .leading)
                actions(maxWidth: min(geo.size.width * 0.5, 380))
            }
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Pieces

    private func crest(size: CGFloat, icon: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Theme.gold.opacity(0.14))
                .frame(width: size, height: size)
            Image(systemName: "bell.badge.fill")
                .font(.system(size: icon, weight: .bold))
                .foregroundStyle(Theme.gold)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private func heading(
        titleSize: CGFloat, subSize: CGFloat,
        alignment: HorizontalAlignment = .center
    ) -> some View {
        VStack(alignment: alignment, spacing: 10) {
            Text("ALLOW NOTIFICATIONS ABOUT BONUSES AND PROMOS")
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .foregroundStyle(.white)
            Text("Stay tuned for special offers and rewards")
                .font(.system(size: subSize, weight: .medium))
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .foregroundStyle(Theme.dim)
        }
    }

    private func actions(maxWidth: CGFloat) -> some View {
        VStack(spacing: 14) {
            Button(action: accept) {
                Group {
                    if working { ProgressView().tint(.black) }
                    else { Text("Allow") }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(working)

            // `PrimaryButtonStyle` paints its label black, so the "Not now"
            // variant is inlined here with an explicit white foreground to
            // keep it legible against the dark panel background.
            Button(action: skip) {
                Text("Not now")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Theme.panelHi)
                    )
            }
            .disabled(working)
            .opacity(working ? 0.6 : 1)
        }
        .frame(maxWidth: maxWidth)
    }

    // MARK: Actions

    private func accept() {
        guard !working else { return }
        working = true
        // Lock the promo FIRST, then surface the system prompt. Whatever the
        // OS prompt returns, our own screen is done.
        session.markPushPromoAccepted()
        Task {
            _ = await signal.askPermission()
            await MainActor.run { onFinish() }
        }
    }

    private func skip() {
        guard !working else { return }
        working = true
        session.snoozePushInvite()
        onFinish()
    }
}

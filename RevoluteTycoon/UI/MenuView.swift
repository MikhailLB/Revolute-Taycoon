import SwiftUI

struct LogoMark: View {
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = min(sz.width, sz.height) / 2 - 2
                // Casino chip.
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Theme.goldDeep))
                for i in 0..<8 {
                    var p = Path()
                    let a0 = Angle.radians(t * 0.4 + Double(i) * .pi / 4)
                    let a1 = Angle.radians(t * 0.4 + Double(i) * .pi / 4 + .pi / 8)
                    p.addArc(center: c, radius: r * 0.9, startAngle: a0, endAngle: a1, clockwise: false)
                    ctx.stroke(p, with: .color(.white), lineWidth: r * 0.16)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.72, y: c.y - r * 0.72, width: r * 1.44, height: r * 1.44)), with: .color(Color(hex: 0x1A1033)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 0.66, y: c.y - r * 0.66, width: r * 1.32, height: r * 1.32)), with: .color(Theme.gold), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                ctx.draw(Text("R").font(.system(size: r * 0.95, weight: .black, design: .serif)).foregroundColor(Theme.gold), at: c)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.gold.opacity(0.4), radius: 20)
    }
}

struct MenuView: View {
    @Environment(GameStore.self) private var store
    @State private var confirmNew = false
    @State private var showAbout = false

    var body: some View {
        @Bindable var store = store
        ZStack {
            LinearGradient(colors: [Theme.bgDeep, Color(hex: 0x241047)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                LogoMark(size: 130)
                VStack(spacing: 6) {
                    Text("REVOLUTE")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(LinearGradient(colors: [Theme.gold, Color(hex: 0xFFE9A8), Theme.goldDeep], startPoint: .top, endPoint: .bottom))
                    Text("TYCOON")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .tracking(14)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Casino business simulator")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
                Label("Early Access", systemImage: "hammer.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.violet.opacity(0.25)))
                    .foregroundStyle(Theme.violet)
                Spacer()
                VStack(spacing: 12) {
                    if store.hasSave {
                        Button("Continue") { store.continueGame() }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("New Company") { confirmNew = true }
                            .buttonStyle(PrimaryButtonStyle(color: Theme.panelHi))
                            .foregroundStyle(.white)
                    } else {
                        Button("Start Your Company") { store.newGame() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    Button("About & Early Access") { showAbout = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 32)
                Text("A management game. No real-money gambling, no betting, no prizes.")
                    .font(.caption2).foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
            }
        }
        .alert("Start a new company?", isPresented: $confirmNew) {
            Button("Start over", role: .destructive) {
                store.deleteSave()
                store.newGame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current career will be erased.")
        }
        .alert("Save could not be verified", isPresented: $store.loadFailed) {
            Button("Start a new company", role: .destructive) {
                store.deleteSave()
                store.newGame()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The save file is damaged or was modified outside the game, so it was rejected.")
        }
        .sheet(isPresented: $showAbout) { AboutView() }
    }
}

struct OnboardingView: View {
    var onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    LogoMark(size: 90)
                    Spacer()
                }
                .padding(.top, 30)
                Text("Welcome, future tycoon")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text("Revolute Taycoon is a business simulation. You manage a hospitality and gaming company: equipment, staff, taxes, licenses, loans and branches.")
                    .foregroundStyle(Theme.dim)

                notice(icon: "building.columns.fill", color: Theme.gold, title: "You run the business, not the games",
                       text: "You never place bets or play casino games. Guest activity is simulated as revenue in your company's books.")
                notice(icon: "dollarsign.circle.fill", color: Theme.green, title: "No real money",
                       text: "All currency is fictional and has no cash value. Nothing can be bought, won, withdrawn or exchanged. There are no in-app purchases or ads.")
                notice(icon: "hammer.fill", color: Theme.violet, title: "Early Access",
                       text: "The game is in active development. Some sections such as integrated resorts, international expansion, the holding company and the digital division are marked \"Coming soon\" and will arrive in future updates.")
                notice(icon: "heart.text.square.fill", color: Theme.pink, title: "Responsible gaming",
                       text: "Real gambling can cause harm. In the game, responsible gaming programs are part of running a compliant business. If gambling affects you or someone you know, seek local support services.")

                Button("I understand, let's build") { onAccept() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)
                Text("Intended for adults (17+). Fictional companies, cities and regulators.")
                    .font(.caption2).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func notice(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Early Access roadmap") {
                    roadmap("Integrated Resort format & Resort Concession", "Hotel towers, arenas and convention halls.")
                    roadmap("International expansion", "Lagoon Isle and offshore jurisdictions with their own tax regimes.")
                    roadmap("Holding company & IPO", "Investors, shares and acquisitions of rival chains.")
                    roadmap("Digital division", "Brand entertainment services and media campaigns.")
                    roadmap("Cashless floor", "Digital wallets replacing the cage.")
                }
                Section("About") {
                    Text("Revolute Taycoon is a management simulation about running a casino company. It contains no real-money gambling, no betting by the player and no purchasable currency. All companies, cities and regulators are fictional.")
                        .font(.footnote)
                    Text("Simulation, finance and tax calculations run in a native engine on your device. The game works fully offline and collects no personal data.")
                        .font(.footnote)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("About")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func roadmap(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                EarlyAccessBadge()
            }
            Text(text).font(.caption).foregroundStyle(Theme.dim)
        }
    }
}

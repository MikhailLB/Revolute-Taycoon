import SwiftUI

enum GameTab: String, CaseIterable, Identifiable {
    case floor, staff, finance, develop, empire

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floor: "Floor"
        case .staff: "Staff"
        case .finance: "Finance"
        case .develop: "Develop"
        case .empire: "Empire"
        }
    }

    var icon: String {
        switch self {
        case .floor: "square.grid.3x3.fill"
        case .staff: "person.3.fill"
        case .finance: "chart.bar.xaxis"
        case .develop: "point.3.connected.trianglepath.dotted"
        case .empire: "map.fill"
        }
    }
}

struct GameView: View {
    @Environment(GameStore.self) private var store
    #if DEBUG
    @State private var tab: GameTab = GameTab(rawValue: GameStore.debugTab ?? "") ?? .floor
    @State private var showOffice = GameStore.debugTab == "office"
    #else
    @State private var tab: GameTab = .floor
    @State private var showOffice = false
    #endif

    var body: some View {
        @Bindable var store = store
        if let s = store.snapshot {
            VStack(spacing: 0) {
                HUD(snapshot: s, showOffice: $showOffice)
                ZStack {
                    switch tab {
                    case .floor: FloorTab()
                    case .staff: StaffTab()
                    case .finance: FinanceTab()
                    case .develop: DevelopTab()
                    case .empire: EmpireTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                TabBar(tab: $tab, badges: badges(s))
            }
            .background(Theme.bg.ignoresSafeArea())
            .overlay(alignment: .top) {
                if let t = store.toast {
                    ToastView(toast: t)
                        .padding(.top, 70)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: Binding(get: { s.decision != nil && !s.company.gameOver }, set: { _ in })) {
                if let d = s.decision {
                    DecisionSheet(decision: d)
                        .presentationDetents([.medium])
                        .interactiveDismissDisabled()
                }
            }
            .sheet(isPresented: $showOffice) { OfficeSheet() }
            .alert("Integrity check failed", isPresented: $store.integrityAlert) {
                Button("Restore last save") { store.recoverFromTamper() }
            } message: {
                Text("The game state was modified from outside the game. Your last verified save will be restored.")
            }
            .overlay {
                if s.company.gameOver { GameOverView(snapshot: s) }
            }
        }
    }

    private func badges(_ s: Snapshot) -> [GameTab: Int] {
        var b: [GameTab: Int] = [:]
        let short = s.venues.reduce(0) { acc, v in acc + v.staff.filter { $0.have < $0.need }.count }
        if short > 0 { b[.staff] = short }
        if s.researchActive == nil, s.research.contains(where: { $0.state == "available" }) { b[.develop] = 1 }
        if s.licenses.contains(where: { $0.state == "next" && $0.blocked == nil }) { b[.empire] = 1 }
        return b
    }
}

struct HUD: View {
    @Environment(GameStore.self) private var store
    let snapshot: Snapshot
    @Binding var showOffice: Bool

    var body: some View {
        @Bindable var store = store
        let c = snapshot.company
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Fmt.money(c.cash))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(c.cash < 0 ? Theme.red : Theme.gold)
                        .contentTransition(.numericText())
                    Text(c.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(snapshot.clock.weekday) \(snapshot.clock.dayOfMonth) \(snapshot.clock.monthLabel)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    HStack(spacing: 4) {
                        Image(systemName: (6...19).contains(snapshot.clock.hour) ? "sun.max.fill" : "moon.stars.fill")
                            .foregroundStyle((6...19).contains(snapshot.clock.hour) ? Theme.gold : Theme.violet)
                        Text(Fmt.hour(snapshot.clock.hour)).monospacedDigit()
                        Text("· close in \(snapshot.clock.daysToClose)d").foregroundStyle(Theme.faint)
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                Button { showOffice = true } label: {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 16))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.panelHi))
                }
                .foregroundStyle(Theme.gold)
            }
            HStack(spacing: 8) {
                ForEach(GameSpeed.allCases) { sp in
                    Button {
                        if snapshot.decision == nil { store.speed = sp }
                    } label: {
                        Image(systemName: sp.symbol)
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(store.speed == sp ? Theme.gold : Theme.panelHi))
                            .foregroundStyle(store.speed == sp ? .black : .white)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.gold)
                    Text("\(Int(c.reputation))")
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.teal).padding(.leading, 4)
                    Text(c.rating)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelHi))
            }
            if c.insolventDays > 0 {
                Label("Insolvency: \(max(0, 45 - c.insolventDays)) days to recover", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(Theme.bgDeep)
    }
}

struct TabBar: View {
    @Binding var tab: GameTab
    var badges: [GameTab: Int]

    var body: some View {
        HStack {
            ForEach(GameTab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 18, weight: .semibold))
                        Text(t.title).font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(tab == t ? Theme.gold : Theme.faint)
                    .overlay(alignment: .topTrailing) {
                        if let n = badges[t] {
                            Text("\(n)")
                                .font(.system(size: 9, weight: .black))
                                .padding(4)
                                .background(Circle().fill(Theme.pink))
                                .foregroundStyle(.white)
                                .offset(x: -14, y: 2)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.bgDeep.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(toast.ok ? Theme.green : Theme.red)
            Text(toast.text).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.panelHi).shadow(color: .black.opacity(0.4), radius: 10))
        .padding(.horizontal, 20)
    }
}

struct DecisionSheet: View {
    @Environment(GameStore.self) private var store
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon).font(.title).foregroundStyle(Theme.gold)
                Text(decision.title).font(.title3.bold())
            }
            Text(decision.text).foregroundStyle(Theme.dim)
            Spacer(minLength: 0)
            ForEach(Array(decision.options.enumerated()), id: \.offset) { i, o in
                Button {
                    store.decide(i)
                } label: {
                    VStack(spacing: 2) {
                        Text(o.label)
                        Text(o.detail).font(.caption).opacity(0.75)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(color: i == 0 ? Theme.gold : Theme.panelHi))
                .foregroundStyle(i == 0 ? .black : .white)
            }
        }
        .padding(22)
        .presentationBackground(Theme.panel)
    }

    private var icon: String {
        switch decision.kind {
        case "strike": "person.3.sequence.fill"
        case "high_roller": "crown.fill"
        case "celebrity": "star.circle.fill"
        case "council": "building.2.fill"
        case "poaching": "person.badge.minus"
        default: "questionmark.circle.fill"
        }
    }
}

struct GameOverView: View {
    @Environment(GameStore.self) private var store
    let snapshot: Snapshot

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "building.columns").font(.system(size: 54)).foregroundStyle(Theme.red)
                Text("Bankruptcy").font(.largeTitle.bold())
                Text("Creditors took control of \(snapshot.company.name). Peak results of your career:")
                    .multilineTextAlignment(.center).foregroundStyle(Theme.dim)
                HStack {
                    StatTile(title: "Lifetime GGR", value: Fmt.money(snapshot.company.lifetimeGgr))
                    StatTile(title: "Guests served", value: Fmt.count(snapshot.company.lifetimeVisitors))
                }
                HStack {
                    StatTile(title: "Taxes paid", value: Fmt.money(snapshot.company.taxesPaid))
                    StatTile(title: "Venues", value: "\(snapshot.venues.count)")
                }
                Button("Start a new company") {
                    store.deleteSave()
                    store.newGame()
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Main menu") { store.quitToMenu() }
                    .foregroundStyle(Theme.dim)
            }
            .padding(28)
        }
    }
}

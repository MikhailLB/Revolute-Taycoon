import SwiftUI

struct StaffTab: View {
    @Environment(GameStore.self) private var store
    @State private var wage: Double = 1
    @State private var marketing: Double = 2000
    @State private var comps: Double = 0.03
    @State private var loadedFor: Int = -1

    var body: some View {
        if let v = store.venue {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        VenuePicker()
                        Spacer()
                        Button {
                            store.send(["type": "auto_staff", "venue": v.id])
                        } label: { Label("Auto-staff", systemImage: "wand.and.stars") }
                            .buttonStyle(ChipButtonStyle(color: Theme.gold))
                            .foregroundStyle(.black)
                    }

                    Card {
                        VStack(spacing: 10) {
                            HStack {
                                StatTile(title: "Head count", value: "\(v.staffTotal)", sub: "needed \(v.staffNeed)")
                                StatTile(title: "Payroll / month", value: Fmt.money(v.monthlyPayroll), sub: "+ payroll tax")
                            }
                            Meter(title: "Staff morale", value: v.morale)
                            Text("Opening hours \(Fmt.hour(v.openFrom))–\(v.openTo == 24 ? "24:00" : Fmt.hour(v.openTo)). Each post needs several people to cover shifts, days off and leave.")
                                .font(.caption).foregroundStyle(Theme.faint)
                        }
                    }

                    VStack(spacing: 8) {
                        SectionTitle(text: "Roster")
                        ForEach(v.staff) { line in
                            RoleRow(line: line, def: store.catalog.role(line.role))
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(text: "Venue policies")
                            policy(title: "Pay level", value: "\(Int(wage * 100))% of market", hint: "Higher pay lifts morale and service; below market risks strikes.") {
                                Slider(value: $wage, in: 0.8...1.5, step: 0.05) { editing in
                                    if !editing { store.send(["type": "set_wage", "venue": v.id, "level": wage], quiet: true) }
                                }
                            }
                            policy(title: "Marketing budget", value: "\(Fmt.money(marketing))/mo", hint: "Billboards, radio and promotions. Diminishing returns.") {
                                Slider(value: $marketing, in: 0...200_000, step: 500) { editing in
                                    if !editing { store.send(["type": "set_marketing", "venue": v.id, "amount": marketing], quiet: true) }
                                }
                            }
                            policy(title: "Comps", value: "\(Fmt.pct(comps, digits: 1)) of GGR", hint: "Free drinks, meals and rewards returned to guests. Raises satisfaction.") {
                                Slider(value: $comps, in: 0...0.2, step: 0.005) { editing in
                                    if !editing { store.send(["type": "set_comps", "venue": v.id, "rate": comps], quiet: true) }
                                }
                            }
                        }
                    }

                    Card {
                        VStack(spacing: 10) {
                            SectionTitle(text: "Venue health")
                            Meter(title: "Guest satisfaction", value: v.satisfaction)
                            Meter(title: "Compliance (AML)", value: v.compliance)
                            Meter(title: "Security", value: v.security)
                        }
                    }
                }
                .padding(14)
            }
            .onAppear { sync(v) }
            .onChange(of: v.id) { _, _ in sync(v) }
        }
    }

    private func sync(_ v: VenueView) {
        wage = v.wageLevel
        marketing = v.marketingMonth
        comps = v.compRate
        loadedFor = v.id
    }

    private func policy<C: View>(title: String, value: String, hint: String, @ViewBuilder control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value).font(.subheadline.weight(.bold)).foregroundStyle(Theme.gold).monospacedDigit()
            }
            control()
            Text(hint).font(.caption2).foregroundStyle(Theme.faint)
        }
    }
}

struct RoleRow: View {
    @Environment(GameStore.self) private var store
    let line: StaffLine
    let def: RoleDef?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(def?.name ?? line.role).font(.subheadline.weight(.bold))
                    Spacer()
                    Text("\(line.have)").font(.headline.monospacedDigit())
                    Text("/ \(line.need)").font(.caption).foregroundStyle(Theme.dim)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(color).frame(width: g.size.width * CGFloat(min(1, line.coverage)))
                    }
                }
                .frame(height: 5)
                Text(def.map { "\(Fmt.money($0.salaryMonth))/mo base · hire \(Fmt.money($0.hireCost))" } ?? "")
                    .font(.caption2).foregroundStyle(Theme.faint)
            }
            VStack(spacing: 4) {
                stepper("plus", 1)
                stepper("minus", -1)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .contextMenu {
            Button("Hire 5") { store.hire(line.role, 5) }
            Button("Let go 5", role: .destructive) { store.hire(line.role, -5) }
            if let d = def { Text(d.description) }
        }
    }

    private func stepper(_ s: String, _ n: Int) -> some View {
        Button { store.hire(line.role, n) } label: {
            Image(systemName: s)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panelHi))
        }
        .foregroundStyle(.white)
    }

    private var color: Color {
        line.need == 0 ? Theme.dim : line.coverage >= 1 ? Theme.green : line.coverage >= 0.6 ? Theme.gold : Theme.red
    }

    private var icon: String {
        switch line.role {
        case "dealer": "suit.spade.fill"
        case "attendant": "gamecontroller.fill"
        case "cashier": "banknote.fill"
        case "security": "shield.lefthalf.filled"
        case "hospitality": "wineglass.fill"
        case "technician": "wrench.adjustable.fill"
        case "manager": "person.crop.circle.badge.checkmark"
        case "compliance": "doc.text.magnifyingglass"
        default: "person.fill"
        }
    }
}

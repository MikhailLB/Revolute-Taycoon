import SwiftUI

struct EmpireTab: View {
    @Environment(GameStore.self) private var store
    @State private var cityId = "port_river"
    @State private var askName = false
    @State private var branchName = ""
    @State private var renameCompany = false
    @State private var companyName = ""

    var body: some View {
        if let s = store.snapshot {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.company.name).font(.title3.bold())
                            Text("\(s.venues.count) of \(s.company.maxVenues) venues · \(s.company.licenseName)")
                                .font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Button {
                            companyName = s.company.name
                            renameCompany = true
                        } label: { Image(systemName: "pencil.circle.fill").font(.title2) }
                    }

                    MapCard(snapshot: s, selected: $cityId)
                    cityCard(s)
                    formatCard(s)
                    licenses(s)

                    SectionTitle(text: "Coming in future updates")
                    ComingSoonCard(title: "International expansion", text: "Lagoon Isle and other offshore jurisdictions with their own tax regimes and regulators.", icon: "airplane")
                    ComingSoonCard(title: "Integrated Resort", text: "Hotel towers, arenas and convention halls under a state concession.", icon: "building.2.crop.circle")
                    ComingSoonCard(title: "Acquisitions", text: "Buy out rival venues in your cities to absorb their market share.", icon: "arrow.triangle.merge")
                }
                .padding(14)
            }
            .alert("Name the new branch", isPresented: $askName) {
                TextField("Branch name", text: $branchName)
                Button("Start construction") {
                    store.send(["type": "open_branch", "city": cityId, "name": branchName])
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename company", isPresented: $renameCompany) {
                TextField("Company name", text: $companyName)
                Button("Save") { store.send(["type": "rename_company", "name": companyName]) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func cityCard(_ s: Snapshot) -> some View {
        if let c = store.catalog.city(cityId), let cv = s.cities.first(where: { $0.id == cityId }) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(c.name).font(.title3.bold())
                        Spacer()
                        if c.earlyAccessLocked { EarlyAccessBadge() }
                        else if cv.venues > 0 { Text("\(cv.venues) venue(s)").font(.caption.bold()).foregroundStyle(Theme.green) }
                    }
                    Text(c.description).font(.footnote).foregroundStyle(Theme.dim)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        StatTile(title: "Population", value: Fmt.count(c.population))
                        StatTile(title: "Guest wealth", value: String(format: "×%.2f", c.wealth))
                        StatTile(title: "Tourism", value: Fmt.pct(c.tourism))
                        StatTile(title: "Competition", value: String(format: "%.0f", c.competition * cv.pressure), color: c.competition * cv.pressure > 40 ? Theme.orange : .white)
                        StatTile(title: "Rent", value: "\(Fmt.money(c.rentM2Month))/m²")
                        StatTile(title: "Wages", value: String(format: "×%.2f", c.wageIndex))
                        StatTile(title: "Gaming tax", value: ["Low", "Medium", "High"][min(2, c.taxSchedule)], sub: "progressive on GGR")
                        StatTile(title: "VAT", value: Fmt.pct(c.vat))
                        StatTile(title: "Payroll tax", value: Fmt.pct(c.payrollTax))
                    }
                    if !c.earlyAccessLocked {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("New branch: \(Fmt.money(cv.branchCost))").font(.subheadline.bold())
                                Text("Fit-out \(cv.branchDays) days · starts as a Gaming Club").font(.caption).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                        }
                        if let b = cv.blocked {
                            Label(b, systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.orange)
                        }
                        Button("Open a branch here") {
                            branchName = "Revolute \(c.name)"
                            askName = true
                        }
                        .buttonStyle(PrimaryButtonStyle(enabled: cv.blocked == nil))
                        .disabled(cv.blocked != nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formatCard(_ s: Snapshot) -> some View {
        if let v = store.venue {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: "Venue format")
                        VenuePicker()
                    }
                    HStack(spacing: 6) {
                        ForEach(store.catalog.formats) { f in
                            VStack(spacing: 4) {
                                Image(systemName: ["storefront.fill", "building.fill", "building.2.fill", "building.columns.fill"][min(3, f.level)])
                                    .font(.title3)
                                Text(f.name).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(f.level <= v.format ? Theme.gold : f.earlyAccessLocked ? Theme.violet : Theme.faint)
                            .background(RoundedRectangle(cornerRadius: 10).fill(f.level == v.format ? Theme.gold.opacity(0.15) : Theme.panelHi))
                        }
                    }
                    if let next = v.nextFormat {
                        Text("Next: \(next.name)").font(.headline)
                        Text(next.description).font(.footnote).foregroundStyle(Theme.dim)
                        if next.earlyAccessLocked {
                            EarlyAccessBadge()
                        } else {
                            HStack {
                                StatTile(title: "Cost", value: Fmt.money(next.upgradeCost), color: Theme.gold)
                                StatTile(title: "Floor", value: "\(next.gridW)×\(next.gridH)", sub: "\(Int(next.areaM2)) m²")
                                StatTile(title: "G&A", value: "\(Fmt.money(next.overheadMonth))/mo")
                            }
                            Text("Requires \(store.catalog.licenses[min(next.minLicense, store.catalog.licenses.count - 1)].name) and reputation \(Int(next.minReputation)). Works take \(max(3, next.buildDays / 2)) days at half capacity.")
                                .font(.caption).foregroundStyle(Theme.faint)
                            if let b = v.upgradeBlocked {
                                Label(b, systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.orange)
                            }
                            Button("Upgrade \(v.name)") {
                                store.send(["type": "upgrade_format", "venue": v.id])
                            }
                            .buttonStyle(PrimaryButtonStyle(enabled: v.upgradeBlocked == nil))
                            .disabled(v.upgradeBlocked != nil)
                        }
                    }
                }
            }
        }
    }

    private func licenses(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Gaming licenses")
            ForEach(store.catalog.licenses) { l in
                let lv = s.licenses.first { $0.tier == l.tier }
                let state = lv?.state ?? "locked"
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: state == "owned" ? "checkmark.seal.fill" : "seal")
                                .foregroundStyle(state == "owned" ? Theme.green : state == "early_access" ? Theme.violet : Theme.gold)
                            Text(l.name).font(.subheadline.bold())
                            Spacer()
                            if state == "early_access" { EarlyAccessBadge() }
                            else if state == "owned" { Text("Held").font(.caption.bold()).foregroundStyle(Theme.green) }
                            else { Text(Fmt.money(l.price)).font(.caption.bold()).foregroundStyle(Theme.gold) }
                        }
                        Text(l.description).font(.caption).foregroundStyle(Theme.dim)
                        Text("Fee \(Fmt.money(l.monthlyFee))/mo per venue · reputation \(Int(l.minReputation)) · compliance \(Int(l.minCompliance))")
                            .font(.caption2).foregroundStyle(Theme.faint)
                        if state == "next" {
                            if let b = lv?.blocked {
                                Label(b, systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.orange)
                            }
                            Button("Apply for license") { store.send(["type": "buy_license"]) }
                                .buttonStyle(PrimaryButtonStyle(enabled: lv?.blocked == nil))
                                .disabled(lv?.blocked != nil)
                        }
                    }
                }
            }
        }
    }
}

struct MapCard: View {
    @Environment(GameStore.self) private var store
    let snapshot: Snapshot
    @Binding var selected: String

    var body: some View {
        Card(padding: 0) {
            GeometryReader { g in
                let size = g.size
                ZStack {
                    Canvas { ctx, sz in drawMap(ctx, sz) }
                    ForEach(store.catalog.cities) { c in
                        let cv = snapshot.cities.first { $0.id == c.id }
                        let owned = (cv?.venues ?? 0) > 0
                        Button {
                            selected = c.id
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    Circle()
                                        .fill(c.earlyAccessLocked ? Theme.violet : owned ? Theme.gold : Theme.teal)
                                        .frame(width: selected == c.id ? 22 : 16, height: selected == c.id ? 22 : 16)
                                        .shadow(color: (owned ? Theme.gold : Theme.teal).opacity(0.8), radius: 6)
                                    if c.earlyAccessLocked {
                                        Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.white)
                                    } else if owned {
                                        Text("\(cv?.venues ?? 0)").font(.system(size: 9, weight: .black)).foregroundStyle(.black)
                                    }
                                }
                                Text(c.name).font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Capsule().fill(.black.opacity(0.55)))
                            }
                        }
                        .foregroundStyle(.white)
                        .position(x: size.width * c.mapX, y: size.height * c.mapY)
                    }
                }
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func drawMap(_ ctx: GraphicsContext, _ sz: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .linearGradient(Gradient(colors: [Color(hex: 0x0B2A4A), Color(hex: 0x071A33)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height)))
        // Sea grid.
        var grid = Path()
        stride(from: 0.0, through: sz.width, by: 24).forEach { x in grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: sz.height)) }
        stride(from: 0.0, through: sz.height, by: 24).forEach { y in grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: sz.width, y: y)) }
        ctx.stroke(grid, with: .color(.white.opacity(0.04)), lineWidth: 1)
        // Mainland.
        let pts: [(Double, Double)] = [(0.04, 0.3), (0.2, 0.12), (0.42, 0.18), (0.6, 0.08), (0.78, 0.14), (0.8, 0.36), (0.74, 0.58), (0.78, 0.86), (0.56, 0.92), (0.36, 0.84), (0.14, 0.9), (0.06, 0.66)]
        var land = Path()
        land.move(to: CGPoint(x: pts[0].0 * sz.width, y: pts[0].1 * sz.height))
        for i in 1...pts.count {
            let p = pts[i % pts.count], prev = pts[i - 1]
            let mid = CGPoint(x: (p.0 + prev.0) / 2 * sz.width, y: (p.1 + prev.1) / 2 * sz.height)
            land.addQuadCurve(to: mid, control: CGPoint(x: prev.0 * sz.width, y: prev.1 * sz.height))
        }
        land.closeSubpath()
        ctx.fill(land, with: .linearGradient(Gradient(colors: [Color(hex: 0x1F4D3A), Color(hex: 0x163A2C)]), startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)))
        ctx.stroke(land, with: .color(Theme.gold.opacity(0.35)), lineWidth: 1.5)
        // Island.
        let island = CGRect(x: sz.width * 0.84, y: sz.height * 0.44, width: sz.width * 0.1, height: sz.height * 0.16)
        ctx.fill(Path(ellipseIn: island), with: .color(Color(hex: 0x2A5A3F)))
        ctx.stroke(Path(ellipseIn: island), with: .color(Theme.violet.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        // Roads between cities.
        let cities = store.catalog.cities.filter { !$0.earlyAccessLocked }
        var roads = Path()
        for i in 0..<cities.count {
            for j in (i + 1)..<cities.count {
                roads.move(to: CGPoint(x: cities[i].mapX * sz.width, y: cities[i].mapY * sz.height))
                roads.addLine(to: CGPoint(x: cities[j].mapX * sz.width, y: cities[j].mapY * sz.height))
            }
        }
        ctx.stroke(roads, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }
}

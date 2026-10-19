import SwiftUI

enum FloorMode: Equatable {
    case inspect
    case place(String)
    case move(Int)
}

struct VenuePicker: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        if let s = store.snapshot, let v = store.venue {
            Menu {
                ForEach(s.venues) { venue in
                    Button {
                        store.selectedVenueId = venue.id
                    } label: {
                        Label("\(venue.name) · \(venue.cityName)", systemImage: venue.id == v.id ? "checkmark" : "building.2")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(v.name).font(.system(size: 16, weight: .bold)).lineLimit(1)
                        Text("\(v.formatName) · \(v.cityName) · \(Int(v.areaM2)) m²")
                            .font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    if s.venues.count > 1 {
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(Theme.gold)
                    }
                }
                .foregroundStyle(.white)
            }
            .disabled(s.venues.count < 2)
        }
    }
}

struct FloorTab: View {
    @Environment(GameStore.self) private var store
    #if DEBUG
    @State private var mode: FloorMode = GameStore.debugArg("-place").map { .place($0) } ?? .inspect
    @State private var ghost: (x: Int, y: Int)? = GameStore.debugArg("-place") != nil ? (4, 4) : nil
    @State private var selected: Int? = Int(GameStore.debugArg("-select") ?? "")
    #else
    @State private var mode: FloorMode = .inspect
    @State private var ghost: (x: Int, y: Int)?
    @State private var selected: Int?
    #endif
    @State private var category = "slot"
    @State private var infoItem: ItemDef?

    var body: some View {
        if let v = store.venue, let s = store.snapshot {
            VStack(spacing: 0) {
                header(v)
                statusBanner(v)
                FloorCanvas(
                    venue: v,
                    catalog: store.catalog,
                    hour: s.clock.hour,
                    ghostItem: ghostItem,
                    ghost: ghost,
                    ghostValid: ghostValid(v),
                    selectedId: selected,
                    showGrid: mode != .inspect,
                    onTap: { x, y in tap(x, y, v) }
                )
                .padding(.horizontal, 4)
                bottomPanel(v)
            }
            .onChange(of: store.selectedVenueId) { _, _ in
                mode = .inspect; ghost = nil; selected = nil
            }
            .sheet(item: $infoItem) { ItemInfoSheet(item: $0).presentationDetents([.medium]) }
        }
    }

    // MARK: Header

    private func header(_ v: VenueView) -> some View {
        VStack(spacing: 8) {
            HStack {
                VenuePicker()
                Spacer()
                if v.broken > 0 {
                    Button {
                        store.send(["type": "repair_all", "venue": v.id])
                    } label: {
                        Label("\(v.broken)", systemImage: "wrench.and.screwdriver.fill")
                    }
                    .buttonStyle(ChipButtonStyle(color: Theme.red.opacity(0.3)))
                    .foregroundStyle(Theme.red)
                }
            }
            HStack(spacing: 6) {
                mini("Guests", Fmt.count(v.guestsNow), Theme.teal)
                mini("Occupancy", Fmt.pct(v.occupancyNow), Theme.gold)
                mini("GGR today", Fmt.money(v.today.ggr), v.today.ggr >= 0 ? Theme.green : Theme.red)
                mini("Forecast", "\(Fmt.count(v.forecastVisitors))/d", .white)
                mini("Mood", "\(Int(v.satisfaction))", Theme.meter(v.satisfaction))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func mini(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
            Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
    }

    @ViewBuilder
    private func statusBanner(_ v: VenueView) -> some View {
        let (text, color): (String?, Color) = {
            if let r = v.closedReason { return (r, Theme.red) }
            if v.renovationDays > 0 { return ("Renovation: \(v.renovationDays) days at half capacity", Theme.orange) }
            if v.tablesClosedDays > 0 { return ("Dealers on strike: tables closed \(v.tablesClosedDays) days", Theme.orange) }
            if !v.openNow { return ("Closed for the night. Opens at \(Fmt.hour(v.openFrom))", Theme.violet) }
            if v.buzz > 0 { return ("Buzz: +\(Int(v.buzz * 100))% traffic", Theme.green) }
            if v.buzz < 0 { return ("Bad press: \(Int(v.buzz * 100))% traffic", Theme.red) }
            return (nil, .clear)
        }()
        if let text {
            Text(text)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(color.opacity(0.2))
                .foregroundStyle(color)
        }
    }

    // MARK: Interaction

    private var ghostItem: ItemDef? {
        switch mode {
        case .place(let id): return store.catalog.item(id)
        case .move(let pid):
            guard let p = store.venue?.items.first(where: { $0.id == pid }) else { return nil }
            return store.catalog.item(p.item)
        case .inspect: return nil
        }
    }

    private func ghostValid(_ v: VenueView) -> Bool {
        guard let gi = ghostItem, let g = ghost else { return true }
        if g.x + gi.w > v.gridW || g.y + gi.h > v.gridH { return false }
        var ignore: Int?
        if case .move(let pid) = mode { ignore = pid }
        return !overlaps(v, x: g.x, y: g.y, w: gi.w, h: gi.h, ignore: ignore)
    }

    private func overlaps(_ v: VenueView, x: Int, y: Int, w: Int, h: Int, ignore: Int?) -> Bool {
        v.items.contains { p in
            guard p.id != ignore, let d = store.catalog.item(p.item) else { return false }
            return x < p.x + d.w && p.x < x + w && y < p.y + d.h && p.y < y + h
        }
    }

    private func itemAt(_ v: VenueView, _ x: Int, _ y: Int) -> Placed? {
        v.items.first { p in
            guard let d = store.catalog.item(p.item) else { return false }
            return x >= p.x && x < p.x + d.w && y >= p.y && y < p.y + d.h
        }
    }

    private func tap(_ x: Int, _ y: Int, _ v: VenueView) {
        switch mode {
        case .inspect:
            selected = itemAt(v, x, y)?.id
        case .place(let id):
            ghost = (x, y)
            if ghostValid(v) {
                if store.place(id, x: x, y: y) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        case .move(let pid):
            ghost = (x, y)
            if ghostValid(v), store.move(pid, x: x, y: y) {
                mode = .inspect
                ghost = nil
                selected = pid
            }
        }
    }

    // MARK: Bottom panel

    @ViewBuilder
    private func bottomPanel(_ v: VenueView) -> some View {
        VStack(spacing: 8) {
            switch mode {
            case .inspect:
                if let sid = selected, let p = v.items.first(where: { $0.id == sid }), let d = store.catalog.item(p.item) {
                    inspector(p, d)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            mode = .place(firstAvailable(v) ?? "slot_classic")
                            selected = nil
                        } label: { Label("Build", systemImage: "hammer.fill") }
                            .buttonStyle(PrimaryButtonStyle())
                        Button {
                            store.send(["type": "auto_staff", "venue": v.id])
                        } label: { Label("Auto-staff", systemImage: "person.badge.plus") }
                            .buttonStyle(PrimaryButtonStyle(color: Theme.panelHi))
                            .foregroundStyle(.white)
                    }
                    Text("Tap an object to inspect it. \(v.machines) machines, \(v.tables) tables, \(v.gamingSeats) seats.")
                        .font(.caption2).foregroundStyle(Theme.faint)
                }
            case .place(let id):
                palette(v, selectedId: id)
            case .move:
                HStack {
                    Text("Tap a free spot to move the object").font(.subheadline).foregroundStyle(Theme.dim)
                    Spacer()
                    Button("Cancel") { mode = .inspect; ghost = nil }
                        .buttonStyle(ChipButtonStyle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bgDeep)
    }

    private func firstAvailable(_ v: VenueView) -> String? {
        store.catalog.items.first { $0.category == category && v.blocked($0.id) == nil }?.id
    }

    private func inspector(_ p: Placed, _ d: ItemDef) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ItemIcon(id: d.id, w: d.w, h: d.h, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.headline)
                    Text(p.brokenDays > 0 ? "Out of order: \(p.brokenDays) day(s)" : "Book value \(Fmt.money(p.bookValue))")
                        .font(.caption).foregroundStyle(p.brokenDays > 0 ? Theme.red : Theme.dim)
                }
                Spacer()
                Button { infoItem = d } label: { Image(systemName: "info.circle") }
                    .font(.title3)
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .font(.title3).foregroundStyle(Theme.faint)
            }
            HStack(spacing: 10) {
                Button {
                    mode = .move(p.id); ghost = (p.x, p.y)
                } label: { Label("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right") }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.panelHi))
                    .foregroundStyle(.white)
                Button {
                    store.sell(p.id); selected = nil
                } label: { Label("Sell \(Fmt.money(p.bookValue * 0.5))", systemImage: "dollarsign.arrow.circlepath") }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.red.opacity(0.85)))
            }
        }
    }

    private let categories: [(String, String)] = [
        ("slot", "Machines"), ("table", "Tables"), ("hospitality", "Hospitality"),
        ("service", "Service"), ("security", "Security"), ("decor", "Decor"),
    ]

    private func palette(_ v: VenueView, selectedId: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories, id: \.0) { c in
                            Button(c.1) {
                                category = c.0
                                if let f = store.catalog.items.first(where: { $0.category == c.0 }) {
                                    mode = .place(f.id)
                                }
                            }
                            .buttonStyle(ChipButtonStyle(color: category == c.0 ? Theme.gold : Theme.panelHi))
                            .foregroundStyle(category == c.0 ? .black : .white)
                        }
                    }
                }
                Button("Done") { mode = .inspect; ghost = nil }
                    .buttonStyle(ChipButtonStyle(color: Theme.green))
                    .foregroundStyle(.black)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.catalog.items.filter { $0.category == category }) { item in
                        let blocked = v.blocked(item.id)
                        Button {
                            if blocked == nil { mode = .place(item.id) } else { store.showToast(blocked ?? "", ok: false) }
                        } label: {
                            VStack(spacing: 4) {
                                ItemIcon(id: item.id, w: item.w, h: item.h, size: 42)
                                    .opacity(blocked == nil ? 1 : 0.35)
                                Text(item.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                Text(blocked == nil ? Fmt.money(item.price) : "Locked")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(blocked == nil ? Theme.gold : Theme.faint)
                            }
                            .frame(width: 84, height: 86)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedId == item.id ? Theme.gold.opacity(0.18) : Theme.panel)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedId == item.id ? Theme.gold : Theme.stroke, lineWidth: 1.5))
                            )
                            .overlay(alignment: .topTrailing) {
                                if blocked != nil {
                                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.faint).padding(6)
                                }
                            }
                        }
                        .foregroundStyle(.white)
                        .simultaneousGesture(LongPressGesture().onEnded { _ in infoItem = item })
                    }
                }
            }
            Text("Tap the floor to place. Long-press a card for details.")
                .font(.caption2).foregroundStyle(Theme.faint)
        }
    }
}

struct ItemInfoSheet: View {
    @Environment(GameStore.self) private var store
    let item: ItemDef

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ItemIcon(id: item.id, w: item.w, h: item.h, size: 64)
                VStack(alignment: .leading) {
                    Text(item.name).font(.title3.bold())
                    Text("\(item.w)×\(item.h) tiles · \(Fmt.money(item.price))").font(.subheadline).foregroundStyle(Theme.gold)
                }
            }
            Text(item.description).foregroundStyle(Theme.dim)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                switch item.revenue {
                case "machine":
                    StatTile(title: "Coin-in / seat-hour", value: Fmt.money(item.perSeatHour))
                    StatTile(title: "Hold", value: Fmt.pct(item.hold, digits: 1))
                case "live_table", "high_limit":
                    StatTile(title: "Drop / seat-hour", value: Fmt.money(item.perSeatHour))
                    StatTile(title: "Hold on drop", value: Fmt.pct(item.hold, digits: 0))
                case "rake":
                    StatTile(title: "Rake / seat-hour", value: Fmt.money(item.perSeatHour, cents: true))
                    StatTile(title: "Model", value: "Rake")
                case "food_beverage", "show":
                    StatTile(title: "Spend / guest", value: Fmt.money(item.perSeatHour))
                    StatTile(title: "Gross margin", value: Fmt.pct(item.hold))
                default:
                    StatTile(title: "Appeal", value: String(format: "+%.1f", item.appeal))
                    StatTile(title: "Capacity", value: item.seats > 0 ? "\(item.seats)/h" : "—")
                }
                StatTile(title: "Seats / capacity", value: "\(item.seats)")
                StatTile(title: "Upkeep & fees", value: "\(Fmt.money(item.upkeepDay, cents: true))/day")
                StatTile(title: "Power", value: String(format: "%.1f kW", item.powerKw))
                StatTile(title: "Volatility", value: item.volatility > 0 ? Fmt.pct(item.volatility) : "—")
            }
            if let r = item.requiresResearch, let d = store.catalog.research(r) {
                Label("Requires: \(d.name)", systemImage: "lock.open.fill").font(.footnote).foregroundStyle(Theme.violet)
            }
            Spacer()
        }
        .padding(22)
        .presentationBackground(Theme.panel)
    }
}

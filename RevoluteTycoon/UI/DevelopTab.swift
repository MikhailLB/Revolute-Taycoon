import SwiftUI

struct DevelopTab: View {
    @Environment(GameStore.self) private var store
    @State private var branch = "gaming"
    @State private var detail: ResearchDef?

    private let branches: [(String, String, String)] = [
        ("gaming", "Gaming", "suit.club.fill"),
        ("hospitality", "Hospitality", "fork.knife"),
        ("operations", "Operations", "gearshape.2.fill"),
        ("marketing", "Marketing", "megaphone.fill"),
        ("compliance", "Compliance", "checkmark.shield.fill"),
        ("corporate", "Corporate", "building.columns.fill"),
    ]

    var body: some View {
        if let s = store.snapshot {
            VStack(spacing: 0) {
                activeBanner(s)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(branches, id: \.0) { b in
                            Button {
                                branch = b.0
                            } label: {
                                Label(b.1, systemImage: b.2)
                            }
                            .buttonStyle(ChipButtonStyle(color: branch == b.0 ? Theme.gold : Theme.panelHi))
                            .foregroundStyle(branch == b.0 ? .black : .white)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                ScrollView {
                    let nodes = store.catalog.research.filter { $0.branch == branch }
                    let tiers = Array(Set(nodes.map(\.tier))).sorted()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(tiers, id: \.self) { tier in
                            Text("TIER \(tier + 1)")
                                .font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.faint)
                                .padding(.top, tier == tiers.first ? 0 : 8)
                            ForEach(nodes.filter { $0.tier == tier }) { r in
                                ResearchNode(def: r, view: s.research.first { $0.id == r.id }) { detail = r }
                            }
                            if tier != tiers.last {
                                HStack {
                                    Spacer()
                                    Image(systemName: "arrow.down").foregroundStyle(Theme.faint)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
            }
            .sheet(item: $detail) { r in
                ResearchDetail(def: r).presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder
    private func activeBanner(_ s: Snapshot) -> some View {
        if let id = s.researchActive, let def = store.catalog.research(id), let v = s.research.first(where: { $0.id == id }) {
            let progress = 1 - Double(v.daysLeft) / Double(max(1, def.days))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "flask.fill").foregroundStyle(Theme.teal)
                    Text(def.name).font(.subheadline.bold())
                    Spacer()
                    Text("\(v.daysLeft) days left").font(.caption.bold()).foregroundStyle(Theme.teal)
                }
                ProgressView(value: progress).tint(Theme.teal)
            }
            .padding(14)
            .background(Theme.panel)
        } else {
            HStack {
                Image(systemName: "lightbulb.fill").foregroundStyle(Theme.gold)
                Text("No project running. Pick one to grow your company.").font(.footnote)
                Spacer()
            }
            .padding(14)
            .background(Theme.gold.opacity(0.12))
        }
    }
}

struct ResearchNode: View {
    @Environment(GameStore.self) private var store
    let def: ResearchDef
    let view: ResearchView?
    var onTap: () -> Void

    var body: some View {
        let state = view?.state ?? "locked"
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color(state).opacity(0.18))
                    Image(systemName: icon(state)).foregroundStyle(color(state))
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(def.name).font(.subheadline.weight(.bold)).foregroundStyle(state == "locked" ? Theme.dim : .white)
                        Spacer()
                        if state == "early_access" {
                            EarlyAccessBadge()
                        } else if state == "done" {
                            Text("Done").font(.caption.bold()).foregroundStyle(Theme.green)
                        } else if state == "active" {
                            Text("\(view?.daysLeft ?? 0)d").font(.caption.bold()).foregroundStyle(Theme.teal)
                        } else {
                            Text(Fmt.money(def.cost)).font(.caption.bold()).foregroundStyle(Theme.gold)
                        }
                    }
                    Text(def.description).font(.caption).foregroundStyle(Theme.dim).lineLimit(2).multilineTextAlignment(.leading)
                    if state == "locked", !def.requires.isEmpty {
                        Text("Needs: " + def.requires.compactMap { store.catalog.research($0)?.name }.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(Theme.orange)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(state == "available" ? Theme.gold.opacity(0.6) : Theme.stroke, lineWidth: state == "available" ? 1.5 : 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func color(_ s: String) -> Color {
        switch s {
        case "done": Theme.green
        case "active": Theme.teal
        case "available": Theme.gold
        case "early_access": Theme.violet
        default: Theme.faint
        }
    }

    private func icon(_ s: String) -> String {
        switch s {
        case "done": "checkmark"
        case "active": "hourglass"
        case "available": "sparkle"
        case "early_access": "lock.fill"
        default: "lock"
        }
    }
}

struct ResearchDetail: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let def: ResearchDef

    var body: some View {
        let state = store.snapshot?.research.first { $0.id == def.id }?.state ?? "locked"
        VStack(alignment: .leading, spacing: 14) {
            Text(def.name).font(.title2.bold())
            Text(def.description).foregroundStyle(Theme.dim)
            HStack {
                StatTile(title: "Cost", value: Fmt.money(def.cost), color: Theme.gold)
                StatTile(title: "Duration", value: "\(def.days) days")
                StatTile(title: "Branch", value: def.branch.capitalized)
            }
            if !def.requires.isEmpty {
                Text("Prerequisites: " + def.requires.compactMap { store.catalog.research($0)?.name }.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
            Spacer()
            switch state {
            case "available":
                Button("Start project") {
                    if store.send(["type": "research", "id": def.id]) { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle(enabled: store.snapshot?.researchActive == nil))
                if store.snapshot?.researchActive != nil {
                    Text("One project at a time. Wait for the current one to finish.").font(.caption).foregroundStyle(Theme.faint)
                }
            case "early_access":
                ComingSoonCard(title: "Planned for a future update", text: "This part of the development tree is not available in Early Access yet.", icon: "hammer.fill")
            case "done":
                Label("Completed", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.green)
            case "active":
                Label("In progress", systemImage: "hourglass").foregroundStyle(Theme.teal)
            default:
                Label("Complete the prerequisites first", systemImage: "lock.fill").foregroundStyle(Theme.orange)
            }
        }
        .padding(22)
        .presentationBackground(Theme.panel)
    }
}

import SwiftUI

struct OfficeSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $section) {
                    Text("Milestones").tag(0)
                    Text("News").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(14)
                if let s = store.snapshot {
                    ScrollView {
                        VStack(spacing: 10) {
                            if section == 0 {
                                goals(s)
                            } else {
                                ForEach(s.log) { e in logRow(e) }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 20)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Office")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { store.save(); store.showToast("Saved", ok: true) } label: { Label("Save now", systemImage: "square.and.arrow.down") }
                        Button { showAbout = true } label: { Label("About & roadmap", systemImage: "info.circle") }
                        Button(role: .destructive) {
                            dismiss()
                            store.quitToMenu()
                        } label: { Label("Save & quit to menu", systemImage: "rectangle.portrait.and.arrow.right") }
                    } label: { Image(systemName: "gearshape.fill") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
        .presentationBackground(Theme.bg)
    }

    private func goals(_ s: Snapshot) -> some View {
        let open = s.goals.filter { !$0.done }
        let done = s.goals.filter(\.done)
        return VStack(spacing: 10) {
            ForEach(open) { g in goalRow(g) }
            if !done.isEmpty {
                SectionTitle(text: "Completed", trailing: "\(done.count)/\(s.goals.count)")
                    .padding(.top, 6)
                ForEach(done) { g in goalRow(g) }
            }
        }
    }

    private func goalRow(_ g: GoalView) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: g.done ? "trophy.fill" : "flag.fill").foregroundStyle(g.done ? Theme.gold : Theme.teal)
                    Text(g.title).font(.subheadline.bold())
                    Spacer()
                    Text(reward(g)).font(.caption.bold()).foregroundStyle(Theme.gold)
                }
                Text(g.description).font(.caption).foregroundStyle(Theme.dim)
                if !g.done {
                    HStack(spacing: 8) {
                        ProgressView(value: min(1, g.progress / max(1e-9, g.target))).tint(Theme.teal)
                        Text("\(amount(g.progress, g.target)) / \(amount(g.target, g.target))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .opacity(g.done ? 0.6 : 1)
    }

    private func amount(_ v: Double, _ target: Double) -> String {
        if target >= 100_000 { return Fmt.money(v) }
        if v.rounded(.down) != v { return String(format: "%.1f", (v * 10).rounded(.down) / 10) }
        return Fmt.grouped(v)
    }

    private func reward(_ g: GoalView) -> String {
        var parts: [String] = []
        if g.rewardCash > 0 { parts.append(Fmt.money(g.rewardCash)) }
        if g.rewardRep > 0 { parts.append("+\(Int(g.rewardRep))★") }
        return parts.joined(separator: " ")
    }

    private func logRow(_ e: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Theme.tone(e.tone)).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(e.title).font(.subheadline.bold())
                    Spacer()
                    Text("Day \(e.day + 1) · \(Fmt.hour(e.hour))").font(.caption2).foregroundStyle(Theme.faint)
                }
                Text(e.text).font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
    }
}

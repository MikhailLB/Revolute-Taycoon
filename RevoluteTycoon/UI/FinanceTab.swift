import Charts
import SwiftUI

struct FinanceTab: View {
    @Environment(GameStore.self) private var store
    #if DEBUG
    @State private var section = Int(GameStore.debugArg("-sub") ?? "") ?? 0
    #else
    @State private var section = 0
    #endif

    var body: some View {
        if let s = store.snapshot {
            VStack(spacing: 0) {
                Picker("", selection: $section) {
                    Text("Overview").tag(0)
                    Text("P&L").tag(1)
                    Text("Bank").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(14)
                ScrollView {
                    switch section {
                    case 0: OverviewSection(s: s)
                    case 1: PnLSection(s: s)
                    default: BankSection(s: s)
                    }
                }
            }
        }
    }
}

private struct OverviewSection: View {
    let s: Snapshot

    var body: some View {
        let c = s.company
        let last = s.reports.last
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatTile(title: "Net worth", value: Fmt.money(c.netWorth), color: Theme.gold)
                StatTile(title: "EBITDA (ann.)", value: Fmt.money(c.ebitdaAnnual), color: c.ebitdaAnnual >= 0 ? Theme.green : Theme.red)
                StatTile(title: "Debt", value: Fmt.money(c.debt), sub: "rating \(c.rating)")
                StatTile(title: "Assets (book)", value: Fmt.money(c.assets))
                StatTile(title: "Tax loss c/f", value: Fmt.money(c.lossCarryforward))
                StatTile(title: "Economy", value: String(format: "%.0f", c.economy * 100), sub: c.economy >= 1.05 ? "boom" : c.economy <= 0.92 ? "recession" : "stable",
                         color: c.economy >= 1 ? Theme.green : Theme.orange)
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Daily revenue vs costs", trailing: "last \(s.companyDays.count) days")
                    Chart {
                        ForEach(s.companyDays) { d in
                            BarMark(x: .value("Day", d.day), y: .value("Revenue", d.revenue))
                                .foregroundStyle(Theme.green.opacity(0.8))
                            LineMark(x: .value("Day", d.day), y: .value("Costs", d.costs))
                                .foregroundStyle(Theme.red)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 150)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Cash balance")
                    Chart(s.companyDays) { d in
                        AreaMark(x: .value("Day", d.day), y: .value("Cash", d.cash))
                            .foregroundStyle(LinearGradient(colors: [Theme.gold.opacity(0.5), Theme.gold.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", d.day), y: .value("Cash", d.cash))
                            .foregroundStyle(Theme.gold)
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 120)
                }
            }

            if !s.reports.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(text: "Monthly GGR and EBITDA")
                        Chart {
                            ForEach(s.reports.suffix(12)) { r in
                                BarMark(x: .value("Month", r.label), y: .value("Amount", r.ggr))
                                    .foregroundStyle(Theme.violet.opacity(0.75))
                                    .position(by: .value("Series", "GGR"))
                                BarMark(x: .value("Month", r.label), y: .value("Amount", r.ebitda))
                                    .foregroundStyle(r.ebitda >= 0 ? Theme.green : Theme.red)
                                    .position(by: .value("Series", "EBITDA"))
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in AxisValueLabel().font(.system(size: 7)) }
                        }
                        .frame(height: 160)
                    }
                }
            }

            if let r = last {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Industry KPIs", trailing: r.label)
                        let machines = max(1, s.venues.reduce(0) { $0 + $1.machines })
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            StatTile(title: "Win / unit / day", value: Fmt.money(r.slotGgr / Double(machines) / 30), sub: "slot WPUD")
                            StatTile(title: "GGR per visit", value: Fmt.money(r.ggr / max(1, r.visitors), cents: true))
                            StatTile(title: "Effective gaming tax", value: Fmt.pct(r.gamingTax / max(1, r.ggr), digits: 1))
                            StatTile(title: "EBITDA margin", value: Fmt.pct(r.ebitda / max(1, r.netRevenue), digits: 1), color: r.ebitda >= 0 ? Theme.green : Theme.red)
                            StatTile(title: "Payroll / revenue", value: Fmt.pct((r.wages + r.payrollTax) / max(1, r.netRevenue), digits: 1))
                            StatTile(title: "Non-gaming share", value: Fmt.pct(r.nonGamingNet / max(1, r.netRevenue), digits: 1))
                        }
                    }
                }

                if r.venues.count > 1 {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "Branches", trailing: r.label)
                            ForEach(r.venues) { v in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(v.name).font(.subheadline.weight(.semibold))
                                        Text("\(Fmt.count(v.visitors)) guests · GGR \(Fmt.money(v.ggr))").font(.caption).foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                    Text(Fmt.money(v.ebitda)).font(.subheadline.bold()).foregroundStyle(v.ebitda >= 0 ? Theme.green : Theme.red)
                                }
                                Divider().overlay(Theme.stroke)
                            }
                        }
                    }
                }
            } else {
                Card {
                    Text("The first monthly report arrives when the books close in \(s.clock.daysToClose) days. Gaming tax, VAT, license fees, insurance, loan payments and corporate tax are settled at month end.")
                        .font(.footnote).foregroundStyle(Theme.dim)
                }
            }

            ComingSoonCard(title: "Investors & IPO", text: "Raise equity, list the holding company and acquire rival chains.", icon: "chart.line.uptrend.xyaxis")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }
}

private struct PnLSection: View {
    let s: Snapshot
    @State private var index: Int?

    var body: some View {
        VStack(spacing: 12) {
            if s.reports.isEmpty {
                runningMonth
            } else {
                let i = min(index ?? s.reports.count - 1, s.reports.count - 1)
                let r = s.reports[i]
                HStack {
                    Button { index = max(0, i - 1) } label: { Image(systemName: "chevron.left") }.disabled(i == 0)
                    Spacer()
                    Text(r.label).font(.headline)
                    Spacer()
                    Button { index = min(s.reports.count - 1, i + 1) } label: { Image(systemName: "chevron.right") }.disabled(i >= s.reports.count - 1)
                }
                .padding(.horizontal, 6)
                statement(r)
                runningMonth
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }

    private var runningMonth: some View {
        let ledgers = s.venues.map(\.month)
        let sum: (KeyPath<Ledger, Double>) -> Double = { kp in ledgers.reduce(0) { $0 + $1[keyPath: kp] } }
        let ggr = ledgers.reduce(0) { $0 + $1.ggr }
        let costs = ledgers.reduce(0) { $0 + $1.costs }
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "Running month", trailing: "\(s.clock.monthLabel), day \(s.clock.dayOfMonth)")
                line("GGR so far", ggr, bold: true)
                line("Food, beverage & shows", sum(\.fnbRevenue) + sum(\.showRevenue))
                line("Operating costs paid", -costs)
                line("Guests", sum(\.visitors), money: false)
                line("Turned away (no seat)", sum(\.turnedAway), money: false)
                Text("Gaming tax, VAT, license fees, insurance, interest and income tax are settled at month end.")
                    .font(.caption2).foregroundStyle(Theme.faint)
            }
        }
    }

    private func statement(_ r: MonthReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 5) {
                SectionTitle(text: "Income statement")
                group("Gaming")
                line("Slots & electronic", r.slotGgr)
                line("Live tables", r.tableGgr)
                line("Poker rake", r.pokerRake)
                line("VIP / high limit", r.vipGgr)
                line("Gross gaming revenue", r.ggr, bold: true)
                line("Gaming tax", -r.gamingTax)
                line("Comps & promotions", -r.comps)
                line("Net gaming revenue", r.netGaming, bold: true)
                group("Non-gaming")
                line("F&B and shows (gross)", r.nonGamingGross)
                line("VAT", -r.vat)
                line("Net revenue", r.netRevenue, bold: true)
                group("Operating expenses")
                line("Cost of goods", -r.cogs)
                line("Wages", -r.wages)
                line("Payroll taxes", -r.payrollTax)
                line("Rent", -r.rent)
                line("Utilities", -r.utilities)
                line("Equipment upkeep & fees", -r.upkeep)
                line("Repairs", -r.repairs)
                line("Marketing", -r.marketing)
                line("G&A overhead", -r.overhead)
                line("License fees", -r.licenseFees)
                line("Insurance", -r.insurance)
                line("Fraud losses", -r.fraud)
                line("Fines", -r.fines)
                line("Development & other", -r.other)
                line("EBITDA", r.ebitda, bold: true)
                line("Depreciation", -r.depreciation)
                line("Interest", -r.interest)
                line("Profit before tax", r.ebt, bold: true)
                line("Corporate income tax", -r.incomeTax)
                line("Net income", r.netIncome, bold: true, highlight: true)
                Divider().overlay(Theme.stroke)
                line("Cash at close", r.cashEnd)
                line("Guests", r.visitors, money: false)
            }
        }
    }

    private func group(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.faint).padding(.top, 6)
    }

    private func line(_ title: String, _ v: Double, bold: Bool = false, highlight: Bool = false, money: Bool = true) -> some View {
        HStack {
            Text(title).font(bold ? .subheadline.weight(.bold) : .subheadline).foregroundStyle(bold ? .white : Theme.dim)
            Spacer()
            Text(money ? Fmt.money(v) : Fmt.count(v))
                .font(.subheadline.weight(bold ? .bold : .regular).monospacedDigit())
                .foregroundStyle(highlight ? (v >= 0 ? Theme.green : Theme.red) : (v < 0 ? Theme.red.opacity(0.85) : .white))
        }
    }
}

private struct BankSection: View {
    @Environment(GameStore.self) private var store
    let s: Snapshot
    @State private var amounts: [String: Double] = [:]

    var body: some View {
        VStack(spacing: 12) {
            Card {
                HStack {
                    StatTile(title: "Credit rating", value: s.company.rating, color: Theme.teal)
                    StatTile(title: "Total debt", value: Fmt.money(s.company.debt))
                    StatTile(title: "Missed payments", value: "\(s.company.missedPayments)", color: s.company.missedPayments > 0 ? Theme.red : .white)
                }
            }
            Text("Banks lend against your trailing EBITDA and the book value of your assets. Your rating sets the spread over the base rate. Payments are due when the books close.")
                .font(.caption).foregroundStyle(Theme.faint)

            ForEach(s.loanOffers) { o in
                if let def = store.catalog.loan(o.id) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(def.name).font(.headline)
                                Spacer()
                                Text("\(String(format: "%.1f", o.rate * 100))% · \(def.months) mo").font(.subheadline.bold()).foregroundStyle(Theme.gold)
                            }
                            if o.limit >= 1000 {
                                let amt = amounts[o.id] ?? min(o.limit, max(1000, o.limit / 2))
                                Text("Approved up to \(Fmt.money(o.limit))").font(.caption).foregroundStyle(Theme.dim)
                                Slider(value: Binding(get: { amt }, set: { amounts[o.id] = ($0 / 1000).rounded() * 1000 }), in: 1000...max(1001, o.limit))
                                HStack {
                                    Text("\(Fmt.money(amt)) → \(Fmt.money(annuity(amt, o.rate, def.months)))/mo")
                                        .font(.caption.monospacedDigit())
                                    Spacer()
                                    Button("Borrow") {
                                        store.send(["type": "take_loan", "offer": o.id, "amount": amt])
                                        amounts[o.id] = nil
                                    }
                                    .buttonStyle(ChipButtonStyle(color: Theme.gold))
                                    .foregroundStyle(.black)
                                }
                            } else {
                                Text("Not available: build a track record of profitable months.").font(.caption).foregroundStyle(Theme.faint)
                            }
                        }
                    }
                }
            }

            if !s.loans.isEmpty {
                SectionTitle(text: "Active loans")
                ForEach(s.loans) { l in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(l.name).font(.subheadline.bold())
                                Spacer()
                                Text(Fmt.money(l.balance)).font(.subheadline.bold())
                            }
                            Text("\(String(format: "%.1f", l.annualRate * 100))% · \(Fmt.money(l.payment))/mo · \(l.monthsLeft) months left")
                                .font(.caption).foregroundStyle(Theme.dim)
                            HStack {
                                Button("Repay 25%") { store.send(["type": "repay_loan", "id": l.id, "amount": l.balance * 0.25]) }
                                Button("Repay all") { store.send(["type": "repay_loan", "id": l.id, "amount": l.balance]) }
                            }
                            .buttonStyle(ChipButtonStyle())
                            .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }

    private func annuity(_ p: Double, _ rate: Double, _ months: Int) -> Double {
        let r = rate / 12
        return p * r / (1 - pow(1 + r, -Double(months)))
    }
}

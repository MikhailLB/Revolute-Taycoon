import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0D0A1C)
    static let bgDeep = Color(hex: 0x07050F)
    static let panel = Color(hex: 0x17122E)
    static let panelHi = Color(hex: 0x221A42)
    static let stroke = Color.white.opacity(0.08)
    static let gold = Color(hex: 0xF5C451)
    static let goldDeep = Color(hex: 0xC8902A)
    static let pink = Color(hex: 0xFF4D8D)
    static let teal = Color(hex: 0x3DDBD9)
    static let green = Color(hex: 0x46D17F)
    static let red = Color(hex: 0xFF5A5F)
    static let orange = Color(hex: 0xFF9F43)
    static let violet = Color(hex: 0x9B6BFF)
    static let text = Color.white
    static let dim = Color.white.opacity(0.6)
    static let faint = Color.white.opacity(0.35)

    static func tone(_ t: String) -> Color {
        switch t {
        case "good": green
        case "bad": red
        case "warn": orange
        case "goal": gold
        default: teal
        }
    }

    static func meter(_ v: Double) -> Color {
        v >= 70 ? green : v >= 45 ? gold : v >= 25 ? orange : red
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Fmt {
    static func money(_ v: Double, cents: Bool = false) -> String {
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        if a >= 1e9 { return "\(sign)$\(String(format: "%.2f", a / 1e9))B" }
        if a >= 1e6 { return "\(sign)$\(String(format: "%.2f", a / 1e6))M" }
        if a >= 1e4 { return "\(sign)$\(String(format: "%.1f", a / 1e3))K" }
        if cents { return "\(sign)$\(String(format: "%.2f", a))" }
        return "\(sign)$\(grouped(a))"
    }

    static func grouped(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }

    static func count(_ v: Double) -> String {
        if v >= 1e6 { return String(format: "%.1fM", v / 1e6) }
        if v >= 1e4 { return String(format: "%.1fK", v / 1e3) }
        return grouped(v)
    }

    static func pct(_ v: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", v * 100)
    }

    static func hour(_ h: Int) -> String {
        String(format: "%02d:00", h % 24)
    }
}

// MARK: - Reusable pieces

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
            )
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Theme.gold)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(Theme.dim)
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var sub: String? = nil
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub ?? " ")
                .font(.system(size: 10))
                .foregroundStyle(Theme.faint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelHi))
    }
}

struct Meter: View {
    let title: String
    let value: Double
    var max: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                Spacer()
                Text("\(Int(value.rounded()))").font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.meter(value / max * 100))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Theme.meter(value / max * 100))
                        .frame(width: g.size.width * CGFloat(min(1, Swift.max(0, value / max))))
                }
            }
            .frame(height: 6)
        }
    }
}

struct EarlyAccessBadge: View {
    var body: some View {
        Label("Coming soon", systemImage: "lock.fill")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.violet.opacity(0.25)))
            .foregroundStyle(Theme.violet)
    }
}

/// Placeholder for sections that ship in a later Early Access update.
struct ComingSoonCard: View {
    let title: String
    let text: String
    var icon: String = "sparkles"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.violet)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    EarlyAccessBadge()
                }
                Text(text).font(.footnote).foregroundStyle(Theme.dim)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.panel.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(Theme.violet.opacity(0.5))
                )
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.gold
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(enabled ? color : Color.white.opacity(0.1))
            )
            .foregroundStyle(enabled ? Color.black : Theme.faint)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ChipButtonStyle: ButtonStyle {
    var color: Color = Theme.panelHi

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(color))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

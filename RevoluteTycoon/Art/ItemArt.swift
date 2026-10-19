import SwiftUI

/// Hand-written vector art for every floor object, drawn top-down.
enum ItemArt {
    static func draw(_ id: String, in r: CGRect, ctx: GraphicsContext, t: Double, broken: Bool = false, occupied: Double = 0) {
        let inset = r.insetBy(dx: r.width * 0.06, dy: r.height * 0.06)
        switch id {
        case "slot_classic": slot(inset, ctx, t, body: Color(hex: 0xB3243B), trim: Theme.gold, screen: Color(hex: 0x2A0F18), reels: true)
        case "slot_video": slot(inset, ctx, t, body: Color(hex: 0x23305E), trim: Theme.teal, screen: Color(hex: 0x123C6E), reels: false)
        case "slot_progressive": progressive(inset, ctx, t)
        case "etg_stadium": etg(inset, ctx, t)
        case "table_blackjack": blackjack(inset, ctx)
        case "table_roulette": roulette(inset, ctx, t)
        case "table_baccarat": baccarat(inset, ctx)
        case "table_poker": poker(inset, ctx)
        case "vip_salon": vip(inset, ctx, t)
        case "cashier": cashier(inset, ctx)
        case "bar": bar(inset, ctx, t)
        case "restaurant": restaurant(inset, ctx)
        case "stage": stage(inset, ctx, t)
        case "lounge": lounge(inset, ctx)
        case "restroom": restroom(inset, ctx)
        case "security_post": security(inset, ctx)
        case "surveillance": surveillance(inset, ctx, t)
        case "plant": plant(inset, ctx)
        case "fountain": fountain(inset, ctx, t)
        default:
            ctx.fill(Path(roundedRect: inset, cornerRadius: 4), with: .color(.gray))
        }
        if broken {
            let s = min(r.width, r.height) * 0.42
            let b = CGRect(x: r.maxX - s - 1, y: r.minY + 1, width: s, height: s)
            ctx.fill(Path(ellipseIn: b), with: .color(Theme.red))
            var x = Path()
            x.move(to: CGPoint(x: b.minX + s * 0.3, y: b.minY + s * 0.3))
            x.addLine(to: CGPoint(x: b.maxX - s * 0.3, y: b.maxY - s * 0.3))
            x.move(to: CGPoint(x: b.maxX - s * 0.3, y: b.minY + s * 0.3))
            x.addLine(to: CGPoint(x: b.minX + s * 0.3, y: b.maxY - s * 0.3))
            ctx.stroke(x, with: .color(.white), lineWidth: max(1, s * 0.12))
        }
    }

    private static func rr(_ r: CGRect, _ k: CGFloat) -> Path {
        Path(roundedRect: r, cornerRadius: min(r.width, r.height) * k)
    }

    private static func blink(_ t: Double, _ phase: Double, speed: Double = 3) -> Double {
        0.55 + 0.45 * sin(t * speed + phase)
    }

    private static func chairs(_ ctx: GraphicsContext, around center: CGPoint, rx: CGFloat, ry: CGFloat, count: Int, from: Double, to: Double, size: CGFloat, color: Color) {
        for i in 0..<count {
            let a = from + (to - from) * (Double(i) + 0.5) / Double(count)
            let p = CGPoint(x: center.x + rx * cos(a), y: center.y + ry * sin(a))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)), with: .color(color))
        }
    }

    // MARK: Machines

    static func slot(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double, body: Color, trim: Color, screen: Color, reels: Bool) {
        ctx.fill(rr(r.offsetBy(dx: 1, dy: 2), 0.18), with: .color(.black.opacity(0.35)))
        ctx.fill(rr(r, 0.18), with: .linearGradient(Gradient(colors: [body, body.opacity(0.75)]), startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY)))
        ctx.stroke(rr(r, 0.18), with: .color(trim), lineWidth: max(1, r.width * 0.05))
        let sc = CGRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.18, width: r.width * 0.68, height: r.height * 0.42)
        ctx.fill(rr(sc, 0.12), with: .color(screen))
        if reels {
            let w = sc.width / 3
            let symbols: [Color] = [Theme.gold, Theme.red, Theme.green]
            for i in 0..<3 {
                let c = CGRect(x: sc.minX + CGFloat(i) * w + w * 0.2, y: sc.midY - w * 0.3, width: w * 0.6, height: w * 0.6)
                ctx.fill(Path(ellipseIn: c), with: .color(symbols[(i + Int(t * 2)) % 3].opacity(0.9)))
            }
        } else {
            let glow = blink(t, Double(r.minX), speed: 2)
            ctx.fill(rr(sc.insetBy(dx: 1, dy: 1), 0.12), with: .linearGradient(Gradient(colors: [Theme.teal.opacity(glow), Theme.violet.opacity(glow)]), startPoint: sc.origin, endPoint: CGPoint(x: sc.maxX, y: sc.maxY)))
        }
        let btn = CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.7, width: r.width * 0.6, height: r.height * 0.12)
        ctx.fill(rr(btn, 0.5), with: .color(trim.opacity(blink(t, Double(r.minY)))))
    }

    static func progressive(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        slot(r, ctx, t, body: Color(hex: 0x4B1C7A), trim: Theme.pink, screen: Color(hex: 0x220A3A), reels: true)
        let m = CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.02, width: r.width * 0.8, height: r.height * 0.12)
        ctx.fill(rr(m, 0.5), with: .color(Theme.gold.opacity(blink(t, 0, speed: 6))))
    }

    static func etg(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(rr(r, 0.2), with: .color(Color(hex: 0x1F2B4A)))
        ctx.stroke(rr(r, 0.2), with: .color(Theme.teal), lineWidth: 1.5)
        let d = min(r.width, r.height) * 0.62
        let wheel = CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)
        wheelArt(wheel, ctx, t)
        for i in 0..<4 {
            let x = r.minX + r.width * (0.1 + 0.27 * CGFloat(i)) - (i >= 2 ? -r.width * 0.07 : 0)
            let s = CGRect(x: x, y: r.maxY - r.height * 0.22, width: r.width * 0.12, height: r.height * 0.16)
            if i == 1 || i == 2 { continue }
            ctx.fill(rr(s, 0.3), with: .color(Theme.teal.opacity(0.8)))
        }
    }

    // MARK: Tables

    static func felt(_ r: CGRect, _ ctx: GraphicsContext, color: Color) -> Path {
        let p = Path(roundedRect: r, cornerSize: CGSize(width: r.width * 0.45, height: r.height * 0.5))
        ctx.fill(p.offsetBy(dx: 1, dy: 2), with: .color(.black.opacity(0.35)))
        ctx.fill(p, with: .color(Color(hex: 0x5A3416)))
        let inner = Path(roundedRect: r.insetBy(dx: r.width * 0.06, dy: r.height * 0.08), cornerSize: CGSize(width: r.width * 0.4, height: r.height * 0.45))
        ctx.fill(inner, with: .radialGradient(Gradient(colors: [color.opacity(1), color.opacity(0.7)]), center: CGPoint(x: r.midX, y: r.midY), startRadius: 0, endRadius: r.width * 0.6))
        return inner
    }

    static func blackjack(_ r: CGRect, _ ctx: GraphicsContext) {
        let table = r.insetBy(dx: r.width * 0.08, dy: r.height * 0.16)
        chairs(ctx, around: CGPoint(x: r.midX, y: r.midY - r.height * 0.05), rx: r.width * 0.46, ry: r.height * 0.44, count: 6, from: 0.15, to: Double.pi - 0.15, size: r.width * 0.12, color: Color(hex: 0x8A1E2E))
        _ = felt(table, ctx, color: Color(hex: 0x1E7A45))
        var arc = Path()
        arc.addArc(center: CGPoint(x: table.midX, y: table.minY), radius: table.width * 0.36, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
        ctx.stroke(arc, with: .color(Theme.gold.opacity(0.7)), lineWidth: 1)
        for i in 0..<3 {
            let c = CGRect(x: table.midX - table.width * 0.2 + CGFloat(i) * table.width * 0.14, y: table.minY + table.height * 0.12, width: table.width * 0.1, height: table.height * 0.16)
            ctx.fill(rr(c, 0.15), with: .color(.white))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: table.midX - 3, y: table.minY - 2, width: 6, height: 6)), with: .color(Theme.gold))
    }

    static func wheelArt(_ w: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(Path(ellipseIn: w), with: .color(Color(hex: 0x6B3A12)))
        let c = CGPoint(x: w.midX, y: w.midY)
        let rad = w.width * 0.44
        let n = 18
        for i in 0..<n {
            var p = Path()
            let a0 = Angle.radians(t * 1.5 + Double(i) / Double(n) * 2 * .pi)
            let a1 = Angle.radians(t * 1.5 + Double(i + 1) / Double(n) * 2 * .pi)
            p.move(to: c)
            p.addArc(center: c, radius: rad, startAngle: a0, endAngle: a1, clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: .color(i == 0 ? Theme.green : (i % 2 == 0 ? Color(hex: 0xC0182B) : Color(hex: 0x141414))))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - rad * 0.45, y: c.y - rad * 0.45, width: rad * 0.9, height: rad * 0.9)), with: .color(Theme.gold))
    }

    static func roulette(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        let table = r.insetBy(dx: r.width * 0.06, dy: r.height * 0.14)
        chairs(ctx, around: CGPoint(x: r.midX, y: r.midY), rx: r.width * 0.48, ry: r.height * 0.46, count: 8, from: 0.2, to: Double.pi - 0.2, size: r.width * 0.1, color: Color(hex: 0x8A1E2E))
        _ = felt(table, ctx, color: Color(hex: 0x1E7A45))
        let d = table.height * 0.8
        wheelArt(CGRect(x: table.minX + table.width * 0.06, y: table.midY - d / 2, width: d, height: d), ctx, t)
        let grid = CGRect(x: table.minX + table.width * 0.5, y: table.minY + table.height * 0.22, width: table.width * 0.42, height: table.height * 0.56)
        for row in 0..<3 {
            for col in 0..<4 {
                let cell = CGRect(x: grid.minX + CGFloat(col) * grid.width / 4, y: grid.minY + CGFloat(row) * grid.height / 3, width: grid.width / 4 - 1, height: grid.height / 3 - 1)
                ctx.fill(Path(cell), with: .color((row + col) % 2 == 0 ? Color(hex: 0xC0182B) : Color(hex: 0x141414)))
            }
        }
    }

    static func baccarat(_ r: CGRect, _ ctx: GraphicsContext) {
        let table = r.insetBy(dx: r.width * 0.06, dy: r.height * 0.14)
        chairs(ctx, around: CGPoint(x: r.midX, y: r.midY), rx: r.width * 0.48, ry: r.height * 0.46, count: 7, from: 0.15, to: Double.pi - 0.15, size: r.width * 0.1, color: Color(hex: 0x2B2B6E))
        let surface = Self.felt(table, ctx, color: Color(hex: 0x173E7A))
        ctx.stroke(surface, with: .color(Theme.gold.opacity(0.8)), lineWidth: 1)
        let labels: [Color] = [Theme.red, Theme.gold, Color(hex: 0x3D8BFF)]
        for (i, c) in labels.enumerated() {
            let b = CGRect(x: table.minX + table.width * (0.22 + 0.2 * CGFloat(i)), y: table.midY, width: table.width * 0.16, height: table.height * 0.2)
            ctx.fill(rr(b, 0.4), with: .color(c.opacity(0.8)))
        }
    }

    static func poker(_ r: CGRect, _ ctx: GraphicsContext) {
        let table = r.insetBy(dx: r.width * 0.1, dy: r.height * 0.16)
        chairs(ctx, around: CGPoint(x: r.midX, y: r.midY), rx: r.width * 0.46, ry: r.height * 0.44, count: 9, from: 0, to: 2 * Double.pi, size: r.height * 0.13, color: Color(hex: 0x3A2A1A))
        let p = Path(roundedRect: table, cornerSize: CGSize(width: table.height * 0.5, height: table.height * 0.5))
        ctx.fill(p, with: .color(Color(hex: 0x4A2B12)))
        let inner = Path(roundedRect: table.insetBy(dx: table.height * 0.1, dy: table.height * 0.1), cornerSize: CGSize(width: table.height * 0.4, height: table.height * 0.4))
        ctx.fill(inner, with: .color(Color(hex: 0x1B6B3C)))
        for i in 0..<5 {
            let c = CGRect(x: table.midX - table.width * 0.18 + CGFloat(i) * table.width * 0.08, y: table.midY - table.height * 0.12, width: table.width * 0.06, height: table.height * 0.24)
            ctx.fill(rr(c, 0.15), with: .color(.white))
        }
    }

    static func vip(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(rr(r, 0.08), with: .color(Color(hex: 0x2A1A08)))
        ctx.stroke(rr(r, 0.08), with: .color(Theme.gold), lineWidth: 2.5)
        let rug = r.insetBy(dx: r.width * 0.12, dy: r.height * 0.12)
        ctx.fill(rr(rug, 0.1), with: .color(Color(hex: 0x5A0F24)))
        ctx.stroke(rr(rug.insetBy(dx: 3, dy: 3), 0.1), with: .color(Theme.gold.opacity(0.5)), lineWidth: 1)
        let table = rug.insetBy(dx: rug.width * 0.18, dy: rug.height * 0.3)
        baccarat(table, ctx)
        let star = CGRect(x: r.minX + 4, y: r.minY + 4, width: r.width * 0.14, height: r.width * 0.14)
        ctx.fill(Path(ellipseIn: star), with: .color(Theme.gold.opacity(blink(t, 1))))
    }

    // MARK: Service & hospitality

    static func cashier(_ r: CGRect, _ ctx: GraphicsContext) {
        ctx.fill(rr(r, 0.12), with: .color(Color(hex: 0x3B3F4A)))
        let counter = CGRect(x: r.minX, y: r.maxY - r.height * 0.35, width: r.width, height: r.height * 0.35)
        ctx.fill(rr(counter, 0.2), with: .color(Color(hex: 0x8C6A3A)))
        var bars = Path()
        let n = 7
        for i in 1..<n {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(n)
            bars.move(to: CGPoint(x: x, y: r.minY + 2))
            bars.addLine(to: CGPoint(x: x, y: counter.minY))
        }
        ctx.stroke(bars, with: .color(Theme.gold.opacity(0.85)), lineWidth: 1.2)
        let sign = CGRect(x: r.midX - r.width * 0.15, y: r.minY + r.height * 0.18, width: r.width * 0.3, height: r.height * 0.25)
        ctx.fill(rr(sign, 0.3), with: .color(Theme.green))
        ctx.draw(Text("$").font(.system(size: max(6, sign.height * 0.8), weight: .black)).foregroundColor(.black), at: CGPoint(x: sign.midX, y: sign.midY))
    }

    static func bar(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        let counter = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.55)
        ctx.fill(rr(counter, 0.25), with: .linearGradient(Gradient(colors: [Color(hex: 0x7A4A22), Color(hex: 0x4E2D12)]), startPoint: counter.origin, endPoint: CGPoint(x: counter.minX, y: counter.maxY)))
        let colors: [Color] = [Theme.pink, Theme.teal, Theme.gold, Theme.green, Theme.violet]
        for i in 0..<8 {
            let b = CGRect(x: counter.minX + counter.width * (0.06 + CGFloat(i) * 0.115), y: counter.minY + counter.height * 0.2, width: counter.width * 0.05, height: counter.height * 0.45)
            ctx.fill(rr(b, 0.4), with: .color(colors[i % colors.count].opacity(blink(t, Double(i), speed: 1.5))))
        }
        for i in 0..<5 {
            let s = r.height * 0.26
            let c = CGRect(x: r.minX + r.width * (0.08 + CGFloat(i) * 0.19), y: r.maxY - s - 1, width: s, height: s)
            ctx.fill(Path(ellipseIn: c), with: .color(Color(hex: 0xB3243B)))
            ctx.stroke(Path(ellipseIn: c), with: .color(Theme.gold.opacity(0.6)), lineWidth: 0.8)
        }
    }

    static func restaurant(_ r: CGRect, _ ctx: GraphicsContext) {
        ctx.fill(rr(r, 0.06), with: .color(Color(hex: 0x3A2C22)))
        var tiles = Path()
        let step = r.width / 6
        for i in 1..<6 {
            tiles.move(to: CGPoint(x: r.minX + CGFloat(i) * step, y: r.minY))
            tiles.addLine(to: CGPoint(x: r.minX + CGFloat(i) * step, y: r.maxY))
            tiles.move(to: CGPoint(x: r.minX, y: r.minY + CGFloat(i) * step))
            tiles.addLine(to: CGPoint(x: r.maxX, y: r.minY + CGFloat(i) * step))
        }
        ctx.stroke(tiles, with: .color(.white.opacity(0.05)), lineWidth: 1)
        ctx.stroke(rr(r, 0.06), with: .color(Theme.gold.opacity(0.6)), lineWidth: 1.5)
        for row in 0..<2 {
            for col in 0..<2 {
                let cx = r.minX + r.width * (0.28 + 0.44 * CGFloat(col))
                let cy = r.minY + r.height * (0.3 + 0.42 * CGFloat(row))
                let d = r.width * 0.2
                chairs(ctx, around: CGPoint(x: cx, y: cy), rx: d * 0.75, ry: d * 0.75, count: 4, from: 0.78, to: 0.78 + 2 * .pi, size: d * 0.3, color: Color(hex: 0x8A1E2E))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)), with: .color(.white.opacity(0.9)))
                ctx.fill(Path(ellipseIn: CGRect(x: cx - d * 0.15, y: cy - d * 0.15, width: d * 0.3, height: d * 0.3)), with: .color(Theme.gold))
            }
        }
    }

    static func stage(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(rr(r, 0.08), with: .color(Color(hex: 0x1A1028)))
        let deck = CGRect(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.1, width: r.width * 0.84, height: r.height * 0.55)
        ctx.fill(rr(deck, 0.1), with: .color(Color(hex: 0x3B2614)))
        let curtain = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.14)
        ctx.fill(Path(curtain), with: .color(Color(hex: 0x9E1030)))
        for i in 0..<3 {
            let a = blink(t, Double(i) * 2, speed: 2.5)
            let cx = deck.minX + deck.width * (0.2 + 0.3 * CGFloat(i))
            let beam = CGRect(x: cx - deck.width * 0.12, y: deck.midY - deck.height * 0.3, width: deck.width * 0.24, height: deck.height * 0.6)
            ctx.fill(Path(ellipseIn: beam), with: .radialGradient(Gradient(colors: [Theme.gold.opacity(0.7 * a), .clear]), center: CGPoint(x: beam.midX, y: beam.midY), startRadius: 0, endRadius: beam.width * 0.6))
        }
        for row in 0..<2 {
            for i in 0..<8 {
                let s = r.width * 0.06
                let c = CGRect(x: r.minX + r.width * (0.08 + CGFloat(i) * 0.11), y: r.maxY - r.height * (0.12 + CGFloat(row) * 0.14), width: s, height: s)
                ctx.fill(Path(ellipseIn: c), with: .color(Color(hex: 0x5A1830)))
            }
        }
    }

    static func lounge(_ r: CGRect, _ ctx: GraphicsContext) {
        ctx.fill(rr(r, 0.15), with: .color(Color(hex: 0x2B2148)))
        let sofa = Color(hex: 0x6E3FA8)
        ctx.fill(rr(CGRect(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.08, width: r.width * 0.84, height: r.height * 0.22), 0.4), with: .color(sofa))
        ctx.fill(rr(CGRect(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.08, width: r.width * 0.22, height: r.height * 0.8), 0.4), with: .color(sofa))
        ctx.fill(Path(ellipseIn: CGRect(x: r.midX - r.width * 0.05, y: r.midY - r.height * 0.05, width: r.width * 0.36, height: r.height * 0.36)), with: .color(Color(hex: 0x8C6A3A)))
        ctx.fill(Path(ellipseIn: CGRect(x: r.midX + r.width * 0.08, y: r.midY + r.height * 0.08, width: r.width * 0.1, height: r.height * 0.1)), with: .color(Theme.teal))
    }

    static func restroom(_ r: CGRect, _ ctx: GraphicsContext) {
        ctx.fill(rr(r, 0.15), with: .color(Color(hex: 0x2E4A5E)))
        ctx.stroke(rr(r, 0.15), with: .color(.white.opacity(0.5)), lineWidth: 1)
        ctx.draw(Text("WC").font(.system(size: max(6, r.height * 0.36), weight: .heavy, design: .rounded)).foregroundColor(.white), at: CGPoint(x: r.midX, y: r.midY))
    }

    static func security(_ r: CGRect, _ ctx: GraphicsContext) {
        ctx.fill(rr(r, 0.2), with: .color(Color(hex: 0x1D2638)))
        var shield = Path()
        let w = r.width * 0.56, h = r.height * 0.64
        let o = CGPoint(x: r.midX - w / 2, y: r.midY - h / 2)
        shield.move(to: CGPoint(x: o.x, y: o.y))
        shield.addLine(to: CGPoint(x: o.x + w, y: o.y))
        shield.addLine(to: CGPoint(x: o.x + w, y: o.y + h * 0.5))
        shield.addQuadCurve(to: CGPoint(x: o.x + w / 2, y: o.y + h), control: CGPoint(x: o.x + w, y: o.y + h * 0.85))
        shield.addQuadCurve(to: CGPoint(x: o.x, y: o.y + h * 0.5), control: CGPoint(x: o.x, y: o.y + h * 0.85))
        shield.closeSubpath()
        ctx.fill(shield, with: .color(Color(hex: 0x3D8BFF)))
        ctx.stroke(shield, with: .color(Theme.gold), lineWidth: 1)
    }

    static func surveillance(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(rr(r, 0.1), with: .color(Color(hex: 0x10141E)))
        for row in 0..<3 {
            for col in 0..<3 {
                let cw = r.width * 0.26, ch = r.height * 0.2
                let c = CGRect(x: r.minX + r.width * 0.08 + CGFloat(col) * (cw + r.width * 0.03), y: r.minY + r.height * 0.08 + CGFloat(row) * (ch + r.height * 0.04), width: cw, height: ch)
                let a = blink(t, Double(row * 3 + col), speed: 1.2)
                ctx.fill(Path(c), with: .color(Theme.teal.opacity(0.25 + 0.4 * a)))
            }
        }
        let desk = CGRect(x: r.minX + r.width * 0.1, y: r.maxY - r.height * 0.18, width: r.width * 0.8, height: r.height * 0.12)
        ctx.fill(rr(desk, 0.3), with: .color(Color(hex: 0x3B3F4A)))
    }

    static func plant(_ r: CGRect, _ ctx: GraphicsContext) {
        let pot = CGRect(x: r.midX - r.width * 0.22, y: r.midY - r.height * 0.22, width: r.width * 0.44, height: r.height * 0.44)
        ctx.fill(Path(ellipseIn: pot.offsetBy(dx: 1, dy: 2)), with: .color(.black.opacity(0.3)))
        ctx.fill(Path(ellipseIn: pot), with: .color(Color(hex: 0x8C5A2B)))
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi
            let leaf = CGRect(x: r.midX + r.width * 0.2 * cos(a) - r.width * 0.17, y: r.midY + r.height * 0.2 * sin(a) - r.height * 0.17, width: r.width * 0.34, height: r.height * 0.34)
            ctx.fill(Path(ellipseIn: leaf), with: .color(i % 2 == 0 ? Color(hex: 0x2E9E58) : Color(hex: 0x46C774)))
        }
    }

    static func fountain(_ r: CGRect, _ ctx: GraphicsContext, _ t: Double) {
        ctx.fill(Path(ellipseIn: r), with: .color(Color(hex: 0xBFB6A3)))
        let water = r.insetBy(dx: r.width * 0.1, dy: r.height * 0.1)
        ctx.fill(Path(ellipseIn: water), with: .radialGradient(Gradient(colors: [Color(hex: 0x7FD8FF), Color(hex: 0x1D6FB8)]), center: CGPoint(x: water.midX, y: water.midY), startRadius: 0, endRadius: water.width * 0.55))
        for i in 0..<3 {
            let ph = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let s = water.width * CGFloat(0.2 + 0.75 * ph)
            ctx.stroke(Path(ellipseIn: CGRect(x: water.midX - s / 2, y: water.midY - s / 2, width: s, height: s)), with: .color(.white.opacity(0.6 * (1 - ph))), lineWidth: 1)
        }
        let c = r.width * 0.16
        ctx.fill(Path(ellipseIn: CGRect(x: r.midX - c / 2, y: r.midY - c / 2, width: c, height: c)), with: .color(Theme.gold))
    }
}

/// Small static rendering of an item for menus.
struct ItemIcon: View {
    let id: String
    var w: Int = 1
    var h: Int = 1
    var size: CGFloat = 44

    var body: some View {
        Canvas { ctx, sz in
            let scale = min(sz.width / CGFloat(w), sz.height / CGFloat(h))
            let rw = CGFloat(w) * scale, rh = CGFloat(h) * scale
            let r = CGRect(x: (sz.width - rw) / 2, y: (sz.height - rh) / 2, width: rw, height: rh)
            ItemArt.draw(id, in: r, ctx: ctx, t: 0.6)
        }
        .frame(width: size, height: size)
    }
}

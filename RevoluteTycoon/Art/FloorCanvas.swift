import SwiftUI

/// Top-down casino floor: carpet, walls, objects and animated guests.
struct FloorCanvas: View {
    let venue: VenueView
    let catalog: Catalog
    let hour: Int
    /// Footprint being placed or moved, drawn as a ghost at `ghost`.
    var ghostItem: ItemDef?
    var ghost: (x: Int, y: Int)?
    var ghostValid = true
    var selectedId: Int?
    var showGrid = false
    var onTap: (Int, Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let tile = tileSize(for: geo.size)
            let w = CGFloat(venue.gridW) * tile
            let h = CGFloat(venue.gridH) * tile
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, _ in
                        draw(ctx: ctx, tile: tile, t: t)
                    }
                    .frame(width: w + tile, height: h + tile * 1.4)
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { loc in
                    let x = Int((loc.x - tile / 2) / tile)
                    let y = Int((loc.y - tile / 2) / tile)
                    if x >= 0, y >= 0, x < venue.gridW, y < venue.gridH {
                        onTap(x, y)
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
    }

    private func tileSize(for size: CGSize) -> CGFloat {
        let fit = min((size.width - 8) / CGFloat(venue.gridW + 1), (size.height - 8) / (CGFloat(venue.gridH) + 1.4))
        return max(26, min(54, fit))
    }

    private func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, tile: CGFloat) -> CGRect {
        CGRect(x: tile / 2 + CGFloat(x) * tile, y: tile / 2 + CGFloat(y) * tile, width: CGFloat(w) * tile, height: CGFloat(h) * tile)
    }

    private func draw(ctx: GraphicsContext, tile: CGFloat, t: Double) {
        let floor = rect(0, 0, venue.gridW, venue.gridH, tile: tile)

        // Walls and carpet.
        let wall = floor.insetBy(dx: -tile * 0.3, dy: -tile * 0.3)
        ctx.fill(Path(roundedRect: wall, cornerRadius: tile * 0.25), with: .color(Color(hex: 0x2A2140)))
        ctx.fill(Path(floor), with: .color(Color(hex: 0x3A0F2A)))
        carpet(ctx: ctx, floor: floor, tile: tile)
        ctx.stroke(Path(roundedRect: wall, cornerRadius: tile * 0.25), with: .color(Theme.gold.opacity(0.55)), lineWidth: 2)

        // Entrance at the bottom wall.
        let door = CGRect(x: floor.midX - tile, y: floor.maxY - 2, width: tile * 2, height: tile * 0.45)
        ctx.fill(Path(door), with: .color(Theme.gold.opacity(0.9)))
        ctx.draw(Text("ENTRANCE").font(.system(size: max(7, tile * 0.22), weight: .heavy)).foregroundColor(Theme.gold), at: CGPoint(x: floor.midX, y: door.maxY + tile * 0.3))

        if showGrid {
            var g = Path()
            for x in 0...venue.gridW {
                let px = floor.minX + CGFloat(x) * tile
                g.move(to: CGPoint(x: px, y: floor.minY)); g.addLine(to: CGPoint(x: px, y: floor.maxY))
            }
            for y in 0...venue.gridH {
                let py = floor.minY + CGFloat(y) * tile
                g.move(to: CGPoint(x: floor.minX, y: py)); g.addLine(to: CGPoint(x: floor.maxX, y: py))
            }
            ctx.stroke(g, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
        }

        // Objects.
        var seatSpots: [CGPoint] = []
        for p in venue.items {
            guard let d = catalog.item(p.item) else { continue }
            let r = rect(p.x, p.y, d.w, d.h, tile: tile)
            ItemArt.draw(p.item, in: r, ctx: ctx, t: t, broken: p.brokenDays > 0)
            if p.id == selectedId {
                ctx.stroke(Path(roundedRect: r.insetBy(dx: -2, dy: -2), cornerRadius: 6), with: .color(Theme.teal), style: StrokeStyle(lineWidth: 2, dash: [5, 3], dashPhase: t * 12))
            }
            if ["slot", "table"].contains(d.category), p.brokenDays == 0 {
                for i in 0..<d.seats {
                    let a = Double(i) / Double(max(1, d.seats)) * .pi
                    let spot = d.category == "slot"
                        ? CGPoint(x: r.midX + CGFloat(i % 4) * tile * 0.25 - CGFloat(min(d.seats, 4) - 1) * tile * 0.125, y: r.maxY + tile * 0.12)
                        : CGPoint(x: r.midX + r.width * 0.46 * cos(a), y: r.midY + r.height * 0.44 * sin(a))
                    seatSpots.append(spot)
                }
            }
        }

        // Seated guests.
        let seated = venue.openNow ? Int((venue.occupancyNow * Double(seatSpots.count)).rounded()) : 0
        let palette: [Color] = [Color(hex: 0xFFD3A5), Color(hex: 0xE0A27A), Color(hex: 0x9C6B4E), Color(hex: 0xF2C9A0), Color(hex: 0x6B4A3A)]
        let shirts: [Color] = [Theme.teal, Theme.pink, Theme.gold, Theme.green, .white, Theme.violet]
        if seated > 0 {
            var order = Array(0..<seatSpots.count)
            var rng = SplitMix(seed: UInt64(venue.id &* 7919 &+ 17))
            order.shuffle(using: &rng)
            for k in 0..<min(seated, order.count) {
                let s = seatSpots[order[k]]
                guest(ctx: ctx, at: s, tile: tile, skin: palette[k % palette.count], shirt: shirts[k % shirts.count])
            }
        }

        // Guests walking the aisles.
        if venue.openNow {
            let walkers = min(36, max(0, Int(venue.guestsNow.rounded()) - seated))
            for i in 0..<walkers {
                let fi = Double(i)
                let sx = 0.5 + 0.45 * sin(t * (0.07 + 0.013 * fi.truncatingRemainder(dividingBy: 5)) + fi * 1.7)
                let sy = 0.5 + 0.45 * sin(t * (0.05 + 0.011 * fi.truncatingRemainder(dividingBy: 7)) + fi * 2.3)
                let p = CGPoint(x: floor.minX + floor.width * sx, y: floor.minY + floor.height * sy)
                guest(ctx: ctx, at: p, tile: tile, skin: palette[i % palette.count], shirt: shirts[(i + 2) % shirts.count])
            }
        }

        // Ghost footprint.
        if let gi = ghostItem, let g = ghost {
            let r = rect(g.x, g.y, gi.w, gi.h, tile: tile)
            var c = ctx
            c.opacity = 0.65
            ItemArt.draw(gi.id, in: r, ctx: c, t: t)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color((ghostValid ? Theme.green : Theme.red).opacity(0.25)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(ghostValid ? Theme.green : Theme.red), lineWidth: 2)
        }

        // Night tint and closed overlay.
        let night = nightAmount(hour)
        if night > 0 {
            ctx.fill(Path(wall), with: .color(Color(hex: 0x050320).opacity(night * 0.28)))
        }
        if !venue.openNow {
            ctx.fill(Path(wall), with: .color(.black.opacity(0.45)))
            let label = venue.constructionDays > 0 ? "UNDER CONSTRUCTION" : "CLOSED"
            ctx.draw(Text(label).font(.system(size: max(12, tile * 0.5), weight: .black, design: .rounded)).foregroundColor(.white.opacity(0.85)), at: CGPoint(x: floor.midX, y: floor.midY))
        }
    }

    private func carpet(ctx: GraphicsContext, floor: CGRect, tile: CGFloat) {
        let step = tile
        var diamonds = Path()
        var dots = Path()
        var y = floor.minY
        var row = 0
        while y < floor.maxY {
            var x = floor.minX + (row % 2 == 0 ? 0 : step / 2)
            while x < floor.maxX {
                let c = CGPoint(x: x + step / 2, y: y + step / 2)
                let s = step * 0.32
                diamonds.move(to: CGPoint(x: c.x, y: c.y - s))
                diamonds.addLine(to: CGPoint(x: c.x + s, y: c.y))
                diamonds.addLine(to: CGPoint(x: c.x, y: c.y + s))
                diamonds.addLine(to: CGPoint(x: c.x - s, y: c.y))
                diamonds.closeSubpath()
                dots.addEllipse(in: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3))
                x += step
            }
            y += step / 2
            row += 1
        }
        var c = ctx
        c.clip(to: Path(floor))
        c.stroke(diamonds, with: .color(Color(hex: 0x6E1F45).opacity(0.8)), lineWidth: 1)
        c.fill(dots, with: .color(Theme.gold.opacity(0.35)))
    }

    private func guest(ctx: GraphicsContext, at p: CGPoint, tile: CGFloat, skin: Color, shirt: Color) {
        let b = tile * 0.24
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - b / 2, y: p.y - b * 0.2, width: b, height: b * 0.75)), with: .color(shirt))
        let hd = b * 0.55
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - hd / 2, y: p.y - hd * 0.75, width: hd, height: hd)), with: .color(skin))
    }

    private func nightAmount(_ h: Int) -> Double {
        switch h {
        case 20...23, 0...4: 1
        case 5...7: 0.5
        case 18...19: 0.4
        default: 0
        }
    }
}

/// Deterministic generator so seated guests keep their seats between frames.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

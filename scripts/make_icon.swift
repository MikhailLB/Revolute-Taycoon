// Renders the 1024×1024 App Store icon: a gold casino chip with an "R".
// Usage: swift scripts/make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background: deep violet radial glow.
let bg = CGGradient(colorsSpace: cs, colors: [color(0x3A1A6E), color(0x0D0A1C)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bg, startCenter: CGPoint(x: size / 2, y: size * 0.55), startRadius: 0,
                       endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size * 0.75, options: [.drawsAfterEndLocation])

// Carpet diamonds.
ctx.setStrokeColor(color(0xF5C451, 0.07))
ctx.setLineWidth(3)
var y: CGFloat = 0
var row = 0
while y < size {
    var x: CGFloat = row % 2 == 0 ? 0 : 64
    while x < size {
        ctx.move(to: CGPoint(x: x + 64, y: y + 20))
        ctx.addLine(to: CGPoint(x: x + 108, y: y + 64))
        ctx.addLine(to: CGPoint(x: x + 64, y: y + 108))
        ctx.addLine(to: CGPoint(x: x + 20, y: y + 64))
        ctx.closePath()
        x += 128
    }
    y += 64
    row += 1
}
ctx.strokePath()

let c = CGPoint(x: size / 2, y: size / 2)
let r: CGFloat = 360

// Chip shadow and body.
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0x000000, 0.6))
ctx.setFillColor(color(0xC8902A))
ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
ctx.setShadow(offset: .zero, blur: 0, color: nil)

let gold = CGGradient(colorsSpace: cs, colors: [color(0xFFE9A8), color(0xF5C451), color(0xB57A1E)] as CFArray, locations: [0, 0.5, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
ctx.clip()
ctx.drawLinearGradient(gold, start: CGPoint(x: c.x, y: c.y + r), end: CGPoint(x: c.x, y: c.y - r), options: [])
ctx.restoreGState()

// Edge stripes.
ctx.setStrokeColor(color(0xFFFFFF))
ctx.setLineWidth(56)
for i in 0..<8 {
    let a0 = CGFloat(i) * .pi / 4 + 0.12
    ctx.addArc(center: c, radius: r * 0.9, startAngle: a0, endAngle: a0 + .pi / 8, clockwise: false)
    ctx.strokePath()
}

// Inner face.
ctx.setFillColor(color(0x1A1033))
ctx.fillEllipse(in: CGRect(x: c.x - r * 0.72, y: c.y - r * 0.72, width: r * 1.44, height: r * 1.44))
ctx.setStrokeColor(color(0xF5C451))
ctx.setLineWidth(10)
ctx.setLineDash(phase: 0, lengths: [26, 18])
ctx.strokeEllipse(in: CGRect(x: c.x - r * 0.64, y: c.y - r * 0.64, width: r * 1.28, height: r * 1.28))
ctx.setLineDash(phase: 0, lengths: [])

// Letter.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = ns
let font = NSFont(name: "Georgia-Bold", size: 400) ?? NSFont.boldSystemFont(ofSize: 400)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: color(0xF5C451))!]
let text = NSAttributedString(string: "R", attributes: attrs)
let ts = text.size()
text.draw(at: CGPoint(x: c.x - ts.width / 2, y: c.y - ts.height / 2 + 10))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")

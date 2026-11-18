// Draws the 1024×1024 app icon: swift tools/make_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Squircle on the macOS icon grid: 824×824 with 100px inset.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(20, 20, 24)); ctx.fillPath()
ctx.restoreGState()

// Background: graphite gradient.
ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [rgb(52, 52, 60), rgb(18, 18, 22)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Soft top highlight.
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: [rgb(255, 255, 255, 0.10), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 900), endRadius: 520, options: [])
ctx.restoreGState()

// Rings.
let c = CGPoint(x: 512, y: 512)
func ring(radius: CGFloat, width: CGFloat, fraction: CGFloat, color: CGColor) {
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.08))
    ctx.addArc(center: c, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    // Clockwise from 12 o'clock.
    let start = CGFloat.pi / 2
    ctx.setStrokeColor(color)
    ctx.addArc(center: c, radius: radius, startAngle: start, endAngle: start - .pi * 2 * fraction, clockwise: true)
    ctx.strokePath()
}
ring(radius: 268, width: 62, fraction: 0.72, color: rgb(217, 120, 87))   // Claude
ring(radius: 178, width: 62, fraction: 0.42, color: rgb(92, 158, 250))   // Codex

// Hairline edge.
ctx.addPath(shape); ctx.setStrokeColor(rgb(255, 255, 255, 0.10)); ctx.setLineWidth(3); ctx.strokePath()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("ok: \(out)")

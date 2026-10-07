// Draws the HyperMac logo (a happy mint droplet) and writes every icon asset.
// Usage: swift scripts/make-icons.swift   (run from the repo root)
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

/// Droplet outline in a 1024×1024, y-down design space.
func dropletPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512, y: 238))
    p.addCurve(to: CGPoint(x: 728, y: 590), control1: CGPoint(x: 566, y: 330), control2: CGPoint(x: 728, y: 440))
    p.addArc(center: CGPoint(x: 512, y: 590), radius: 216, startAngle: 0, endAngle: .pi, clockwise: false)
    p.addCurve(to: CGPoint(x: 512, y: 238), control1: CGPoint(x: 296, y: 440), control2: CGPoint(x: 458, y: 330))
    p.closeSubpath()
    return p
}

func render(size: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(size))   // y-down, 1024 design units
    ctx.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawFace(_ ctx: CGContext, eye: NSColor) {
    for x in [446.0, 578.0] {                                   // eyes
        ctx.setFillColor(eye.cgColor)
        ctx.fillEllipse(in: CGRect(x: x - 23, y: 560, width: 46, height: 66))
        ctx.setFillColor(NSColor.white.cgColor)                   // sparkle
        ctx.fillEllipse(in: CGRect(x: x - 6, y: 571, width: 17, height: 17))
    }
    ctx.setFillColor(hex(0xFF8FAB, 0.75).cgColor)                 // blush
    ctx.fillEllipse(in: CGRect(x: 360, y: 640, width: 66, height: 34))
    ctx.fillEllipse(in: CGRect(x: 598, y: 640, width: 66, height: 34))
    ctx.setStrokeColor(eye.cgColor)                               // smile
    ctx.setLineWidth(15)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 486, y: 652))
    ctx.addQuadCurve(to: CGPoint(x: 538, y: 652), control: CGPoint(x: 512, y: 684))
    ctx.strokePath()
}

func drawDroplet(_ ctx: CGContext) {
    let path = dropletPath()
    // soft glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: hex(0x97FCE4, 0.45).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(hex(0x97FCE4).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    // body gradient
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [hex(0xB8FFEE).cgColor, hex(0x97FCE4).cgColor, hex(0x50D2C1).cgColor] as CFArray,
                       locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 238), end: CGPoint(x: 512, y: 806), options: [])
    // glossy highlight
    ctx.translateBy(x: 392, y: 470)
    ctx.rotate(by: -0.45)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
    ctx.fillEllipse(in: CGRect(x: -26, y: -62, width: 52, height: 124))
    ctx.restoreGState()
    drawFace(ctx, eye: hex(0x0A1F24))
}

func appIcon() -> NSBitmapImageRep {
    render(size: 1024) { ctx in
        let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                          cornerWidth: 186, cornerHeight: 186, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(body)
        ctx.setFillColor(hex(0x0F1A1F).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                            colors: [hex(0x17333A).cgColor, hex(0x0B1519).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [hex(0x97FCE4, 0.22).cgColor, hex(0x97FCE4, 0).cgColor] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
        ctx.restoreGState()
        ctx.addPath(body)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(3)
        ctx.strokePath()
        drawDroplet(ctx)
    }
}

/// Just the droplet, transparent background (README / in-app mark).
func logoMark() -> NSBitmapImageRep {
    render(size: 1024) { ctx in
        ctx.translateBy(x: 512, y: 522)
        ctx.scaleBy(x: 1.55, y: 1.55)
        ctx.translateBy(x: -512, y: -522)
        drawDroplet(ctx)
    }
}

/// Monochrome template for the menu bar: droplet with eyes cut out.
func menuIcon(px: Int) -> NSBitmapImageRep {
    render(size: px) { ctx in
        ctx.translateBy(x: 512, y: 522)
        ctx.scaleBy(x: 1.72, y: 1.72)
        ctx.translateBy(x: -512, y: -522)
        ctx.addPath(dropletPath())
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.setBlendMode(.clear)
        for x in [440.0, 584.0] { ctx.fillEllipse(in: CGRect(x: x - 34, y: 545, width: 68, height: 96)) }
        ctx.setLineWidth(26)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: 478, y: 672))
        ctx.addQuadCurve(to: CGPoint(x: 546, y: 672), control: CGPoint(x: 512, y: 712))
        ctx.strokePath()
    }
}

func write(_ rep: NSBitmapImageRep, _ path: String) {
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// app icon → .iconset → .icns
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = appIcon()
write(master, "assets/icon.png")
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for s in scales {
        let px = pt * s
        let img = NSImage(size: NSSize(width: px, height: px))
        img.addRepresentation(master)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current!.imageInterpolation = .high
        master.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(pt)x\(pt)\(s == 2 ? "@2x" : "").png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
write(logoMark(), "assets/logo.png")
write(logoMark(), "Resources/LogoMark.png")
write(menuIcon(px: 18), "Resources/MenuIcon.png")
write(menuIcon(px: 36), "Resources/MenuIcon@2x.png")
print("icons written")

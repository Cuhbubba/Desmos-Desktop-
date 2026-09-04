// Renders AppIcon.icns: dark rounded tile, faint grid, a Desmos-style curve. Run: swift make-icon.swift
import AppKit

func render(_ px: Int) -> NSImage {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.05
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.21, yRadius: s * 0.21)
    NSGradient(starting: NSColor(calibratedWhite: 0.20, alpha: 1),
               ending: NSColor(calibratedWhite: 0.09, alpha: 1))!.draw(in: path, angle: -90)
    path.addClip()

    // grid
    NSColor(calibratedWhite: 1, alpha: 0.07).setStroke()
    let step = tile.width / 8
    for i in 1..<8 {
        let g = NSBezierPath(); g.lineWidth = max(1, s * 0.006)
        g.move(to: NSPoint(x: tile.minX + step * CGFloat(i), y: tile.minY)); g.line(to: NSPoint(x: tile.minX + step * CGFloat(i), y: tile.maxY)); g.stroke()
        g.removeAllPoints()
        g.move(to: NSPoint(x: tile.minX, y: tile.minY + step * CGFloat(i))); g.line(to: NSPoint(x: tile.maxX, y: tile.minY + step * CGFloat(i))); g.stroke()
    }
    // axes
    NSColor(calibratedWhite: 1, alpha: 0.25).setStroke()
    let ax = NSBezierPath(); ax.lineWidth = max(1, s * 0.012)
    ax.move(to: NSPoint(x: tile.minX, y: tile.midY)); ax.line(to: NSPoint(x: tile.maxX, y: tile.midY))
    ax.move(to: NSPoint(x: tile.midX, y: tile.minY)); ax.line(to: NSPoint(x: tile.midX, y: tile.maxY)); ax.stroke()

    // curve  y = sin-ish  (Desmos blue)
    let curve = NSBezierPath(); curve.lineWidth = s * 0.055; curve.lineCapStyle = .round; curve.lineJoinStyle = .round
    let n = 120
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let x = tile.minX + tile.width * (0.08 + 0.84 * t)
        let y = tile.midY + tile.height * 0.26 * sin((t - 0.5) * .pi * 2.2)
        i == 0 ? curve.move(to: NSPoint(x: x, y: y)) : curve.line(to: NSPoint(x: x, y: y))
    }
    NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.85, alpha: 1).setStroke(); curve.stroke()

    // parabola (Desmos green)
    let par = NSBezierPath(); par.lineWidth = s * 0.055; par.lineCapStyle = .round
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let u = (t - 0.5) * 2
        let x = tile.minX + tile.width * (0.15 + 0.70 * t)
        let y = tile.minY + tile.height * (0.18 + 0.62 * u * u)
        i == 0 ? par.move(to: NSPoint(x: x, y: y)) : par.line(to: NSPoint(x: x, y: y))
    }
    NSColor(calibratedRed: 0.22, green: 0.66, blue: 0.36, alpha: 1).setStroke(); par.stroke()
    img.unlockFocus()
    return img
}

let out = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),
                   ("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let img = render(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("iconset written")

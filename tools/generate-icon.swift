import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")

try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
        set()
    }
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FastVPNIcon", code: 1)
    }
    try data.write(to: url)
}

func iconRep(size: Int) -> NSBitmapImageRep {
    let side = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    NSColor.clear.setFill()
    rect.fill()

    let inset = side * 0.075
    let shapeRect = rect.insetBy(dx: inset, dy: inset)
    let radius = side * 0.215
    let shape = NSBezierPath(roundedRect: shapeRect, xRadius: radius, yRadius: radius)

    NSShadow().apply {
        $0.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
        $0.shadowBlurRadius = side * 0.045
        $0.shadowOffset = NSSize(width: 0, height: -side * 0.018)
    }

    NSGradient(colors: [
        NSColor(calibratedRed: 0.035, green: 0.50, blue: 0.92, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.78, blue: 0.70, alpha: 1),
        NSColor(calibratedRed: 0.28, green: 0.91, blue: 0.45, alpha: 1)
    ])?.draw(in: shape, angle: 42)

    NSGraphicsContext.saveGraphicsState()
    shape.setClip()
    let shine = NSBezierPath(ovalIn: NSRect(x: side * 0.02, y: side * 0.55, width: side * 0.72, height: side * 0.52))
    NSColor.white.withAlphaComponent(0.18).setFill()
    shine.fill()

    let lowerShade = NSBezierPath(ovalIn: NSRect(x: side * 0.30, y: -side * 0.25, width: side * 0.80, height: side * 0.62))
    NSColor.black.withAlphaComponent(0.08).setFill()
    lowerShade.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSShadow().apply {
        $0.shadowColor = NSColor.black.withAlphaComponent(0.20)
        $0.shadowBlurRadius = side * 0.018
        $0.shadowOffset = NSSize(width: 0, height: -side * 0.010)
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = NSFont.systemFont(ofSize: side * 0.56, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph
    ]
    NSString(string: "V").draw(
        in: NSRect(x: side * 0.02, y: side * 0.205, width: side * 0.96, height: side * 0.62),
        withAttributes: attrs
    )

    NSShadow().set()
    let accent = NSBezierPath()
    accent.lineCapStyle = .round
    accent.lineJoinStyle = .round
    accent.lineWidth = max(1.0, side * 0.028)
    accent.move(to: NSPoint(x: side * 0.63, y: side * 0.69))
    accent.line(to: NSPoint(x: side * 0.73, y: side * 0.77))
    accent.line(to: NSPoint(x: side * 0.84, y: side * 0.70))
    NSColor.white.withAlphaComponent(0.86).setStroke()
    accent.stroke()

    for point in [
        NSPoint(x: side * 0.63, y: side * 0.69),
        NSPoint(x: side * 0.73, y: side * 0.77),
        NSPoint(x: side * 0.84, y: side * 0.70)
    ] {
        let dot = NSBezierPath(ovalIn: NSRect(
            x: point.x - side * 0.032,
            y: point.y - side * 0.032,
            width: side * 0.064,
            height: side * 0.064
        ))
        NSColor.white.setFill()
        dot.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconFiles {
    try writePNG(iconRep(size: size), to: iconset.appendingPathComponent(name))
}

try writePNG(iconRep(size: 1024), to: assets.appendingPathComponent("FastVPNSwitcherIcon.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconset.path,
    "-o", assets.appendingPathComponent("AppIcon.icns").path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "FastVPNIcon", code: Int(process.terminationStatus))
}

print("Generated \(assets.appendingPathComponent("AppIcon.icns").path)")

import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_dmg_bg.swift <output-png-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let pointSize = NSSize(width: 660, height: 420)
let pixelWidth = Int(pointSize.width * 2)
let pixelHeight = Int(pointSize.height * 2)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Failed to allocate bitmap image rep\n", stderr)
    exit(1)
}

rep.size = pointSize

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("Failed to create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

let cs = CGColorSpaceCreateDeviceRGB()

// Deep obsidian dark base gradient
let bgColors = [
    NSColor(red: 0.025, green: 0.042, blue: 0.088, alpha: 1.0).cgColor,
    NSColor(red: 0.036, green: 0.068, blue: 0.145, alpha: 1.0).cgColor,
    NSColor(red: 0.020, green: 0.036, blue: 0.080, alpha: 1.0).cgColor
] as CFArray
if let bgGrad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 0.55, 1.0]) {
    cg.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: pointSize.height), end: CGPoint(x: pointSize.width, y: 0), options: [])
}

// Bottom Horizon Blue atmospheric glow
let glowColors = [
    NSColor(red: 0.14, green: 0.56, blue: 1.00, alpha: 0.34).cgColor,
    NSColor(red: 0.08, green: 0.32, blue: 0.85, alpha: 0.12).cgColor,
    NSColor(red: 0.05, green: 0.16, blue: 0.45, alpha: 0.0).cgColor
] as CFArray
if let glowGrad = CGGradient(colorsSpace: cs, colors: glowColors, locations: [0.0, 0.45, 1.0]) {
    cg.drawRadialGradient(
        glowGrad,
        startCenter: CGPoint(x: pointSize.width * 0.5, y: 12),
        startRadius: 0,
        endCenter: CGPoint(x: pointSize.width * 0.5, y: 12),
        endRadius: 360,
        options: []
    )
}

// Subtle top ambient highlight orb
let topOrbColors = [
    NSColor(red: 0.25, green: 0.72, blue: 1.00, alpha: 0.15).cgColor,
    NSColor(red: 0.10, green: 0.38, blue: 0.90, alpha: 0.0).cgColor
] as CFArray
if let topOrb = CGGradient(colorsSpace: cs, colors: topOrbColors, locations: [0.0, 1.0]) {
    cg.drawRadialGradient(
        topOrb,
        startCenter: CGPoint(x: pointSize.width * 0.28, y: pointSize.height * 0.86),
        startRadius: 0,
        endCenter: CGPoint(x: pointSize.width * 0.28, y: pointSize.height * 0.86),
        endRadius: 230,
        options: []
    )
}

// Header title and subtitle (AppKit coordinates: origin bottom-left)
let titleAttr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .bold),
    .foregroundColor: NSColor(white: 0.96, alpha: 1.0)
]
let titleStr = NSAttributedString(string: "LoopSearch", attributes: titleAttr)
let titleSize = titleStr.size()
titleStr.draw(at: NSPoint(x: (pointSize.width - titleSize.width) / 2, y: pointSize.height - 62))

let subAttr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
    .foregroundColor: NSColor(red: 0.70, green: 0.82, blue: 0.98, alpha: 0.78)
]
let subStr = NSAttributedString(string: "Version 1.0.1 • Drag LoopSearch into Applications to install", attributes: subAttr)
let subSize = subStr.size()
subStr.draw(at: NSPoint(x: (pointSize.width - subSize.width) / 2, y: pointSize.height - 86))

// Two subtle glass drop-zone plates behind left app icon (175, 222 from top -> CG 198)
// and right Applications icon (485, 222 from top -> CG 198), with bright label pills at CG y=104..128.
let iconCenters = [CGPoint(x: 175, y: 198), CGPoint(x: 485, y: 198)]
for (idx, center) in iconCenters.enumerated() {
    let boxRect = CGRect(x: center.x - 90, y: center.y - 102, width: 180, height: 186)
    let boxPath = CGPath(roundedRect: boxRect, cornerWidth: 22, cornerHeight: 22, transform: nil)
    cg.saveGState()
    cg.addPath(boxPath)
    cg.setFillColor(NSColor(red: 0.09, green: 0.14, blue: 0.26, alpha: idx == 1 ? 0.42 : 0.34).cgColor)
    cg.fillPath()

    cg.addPath(boxPath)
    if idx == 1 {
        cg.setLineDash(phase: 0, lengths: [6, 5])
        cg.setStrokeColor(NSColor(red: 0.34, green: 0.78, blue: 1.00, alpha: 0.48).cgColor)
        cg.setLineWidth(1.5)
    } else {
        cg.setStrokeColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
        cg.setLineWidth(1.0)
    }
    cg.strokePath()

    // Frosted light label pill right where macOS Finder draws dark icon titles ("LoopSearch" / "Applications")
    let labelPillRect = CGRect(x: center.x - 64, y: 108, width: 128, height: 24)
    let labelPillPath = CGPath(roundedRect: labelPillRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
    cg.addPath(labelPillPath)
    cg.setLineDash(phase: 0, lengths: [])
    cg.setFillColor(NSColor(red: 0.92, green: 0.96, blue: 1.00, alpha: 0.92).cgColor)
    cg.fillPath()

    cg.addPath(labelPillPath)
    cg.setStrokeColor(NSColor(white: 1.0, alpha: 0.75).cgColor)
    cg.setLineWidth(0.8)
    cg.strokePath()
    cg.restoreGState()
}

// Glowing curved directional arrow from LoopSearch -> Applications
cg.saveGState()
let arrowPath = CGMutablePath()
arrowPath.move(to: CGPoint(x: 274, y: 205))
arrowPath.addQuadCurve(to: CGPoint(x: 386, y: 205), control: CGPoint(x: 330, y: 226))
cg.addPath(arrowPath)
cg.setStrokeColor(NSColor(red: 0.34, green: 0.80, blue: 1.00, alpha: 0.82).cgColor)
cg.setLineWidth(2.4)
cg.setLineCap(.round)
cg.strokePath()

// Arrowhead at (386, 205)
let headPath = CGMutablePath()
headPath.move(to: CGPoint(x: 377, y: 213))
headPath.addLine(to: CGPoint(x: 388, y: 205))
headPath.addLine(to: CGPoint(x: 379, y: 196))
cg.addPath(headPath)
cg.setStrokeColor(NSColor(red: 0.48, green: 0.88, blue: 1.00, alpha: 0.92).cgColor)
cg.setLineWidth(2.4)
cg.setLineCap(.round)
cg.setLineJoin(.round)
cg.strokePath()
cg.restoreGState()

// Footer note
let footAttr: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
    .foregroundColor: NSColor(red: 0.65, green: 0.76, blue: 0.92, alpha: 0.56)
]
let footStr = NSAttributedString(string: "macOS 14+ Universal (Apple Silicon & Intel) • By Aveesha Senevirathne", attributes: footAttr)
let footSize = footStr.size()
footStr.draw(at: NSPoint(x: (pointSize.width - footSize.width) / 2, y: 26))

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}
try pngData.write(to: outputURL, options: .atomic)
print("Generated Retina DMG background: \(outputURL.path)")

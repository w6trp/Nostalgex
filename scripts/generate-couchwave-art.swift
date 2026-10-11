import AppKit
import Foundation

// Reproducible provisional artwork for the CouchWave beta. No upstream pixels
// are used. Run with `swift scripts/generate-couchwave-art.swift` at repo root.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Nostalgex/Nostalgex/Assets.xcassets")
let original = assets.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
let destination = assets.appendingPathComponent("CouchWave.brandassets")
let fm = FileManager.default
for case let file as URL in fm.enumerator(at: original, includingPropertiesForKeys: nil)! {
    guard file.lastPathComponent == "Contents.json" else { continue }
    let relative = String(file.path.dropFirst(original.path.count + 1))
    let target = destination.appendingPathComponent(relative)
    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contentsOf: file).write(to: target)
}

func render(_ path: String, _ width: Int, _ height: Int, layer: String, scale: Int = 1) throws {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
        pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    let w = CGFloat(width), h = CGFloat(height)
    let rect = NSRect(x: 0, y: 0, width: w, height: h)
    if layer != "front" {
        NSGradient(starting: NSColor(red: 0.025, green: 0.055, blue: 0.13, alpha: 1),
            ending: NSColor(red: 0.075, green: 0.13, blue: 0.22, alpha: 1))!.draw(in: rect, angle: 25)
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: -w * 0.1, y: h * 0.28))
        wave.curve(to: NSPoint(x: w * 1.1, y: h * 0.60),
            controlPoint1: NSPoint(x: w * 0.45, y: h * 0.92),
            controlPoint2: NSPoint(x: w * 0.55, y: -h * 0.22))
        NSColor.cyan.withAlphaComponent(0.16).setStroke()
        wave.lineWidth = h * 0.09
        wave.stroke()
    }
    if layer != "back" {
        let title = "CouchWave" as NSString
        let size = min(h * 0.26, w * 0.115)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .heavy),
            .foregroundColor: NSColor(red: 0.65, green: 0.98, blue: 1, alpha: 1)
        ]
        let textSize = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: (w - textSize.width) / 2, y: h * 0.48 - textSize.height * 0.3), withAttributes: attributes)
        let subtitle = "B E T A" as NSString
        let small: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: h * 0.06, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.65)
        ]
        let smallSize = subtitle.size(withAttributes: small)
        subtitle.draw(at: NSPoint(x: (w - smallSize.width) / 2, y: h * 0.26), withAttributes: small)
    }
    NSGraphicsContext.restoreGraphicsState()
    try image.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(path))
}

for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    try render("App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon-back\(suffix).png", 400, 240, layer: "back", scale: scale)
    try render("App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon-front\(suffix).png", 400, 240, layer: "front", scale: scale)
    try render("Top Shelf Image.imageset/topshelf\(suffix).png", 1920, 720, layer: "all", scale: scale)
    try render("Top Shelf Image Wide.imageset/topshelf-wide\(suffix).png", 2320, 720, layer: "all", scale: scale)
}
try render("App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/icon-store-back.png", 1280, 768, layer: "back")
try render("App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/icon-store-front.png", 1280, 768, layer: "front")
print("Generated CouchWave beta artwork")

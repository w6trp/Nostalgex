import AppKit
import Foundation

// Export the checked-in original artwork into tvOS asset sizes. This does not
// regenerate the artwork. Run from the repository root with Swift on macOS.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Nostalgex/Nostalgex/Assets.xcassets/CouchWave.brandassets")
let source = root.appendingPathComponent("branding/couchwave")
let icon = NSImage(contentsOf: source.appendingPathComponent("app-icon.png"))!
let wordmark = NSImage(contentsOf: source.appendingPathComponent("wordmark.png"))!

func export(_ path: String, _ width: Int, _ height: Int, artwork: NSImage?, opaque: Bool) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    let bounds = NSRect(x: 0, y: 0, width: width, height: height)
    NSColor.clear.setFill(); bounds.fill()
    if opaque {
        NSColor(red: 0.035, green: 0.075, blue: 0.149, alpha: 1).setFill()
        bounds.fill()
    }
    if let artwork {
        let available = artwork === icon ? bounds : bounds.insetBy(dx: CGFloat(width) * 0.12, dy: CGFloat(height) * 0.08)
        let scale = min(available.width / artwork.size.width, available.height / artwork.size.height)
        let size = NSSize(width: artwork.size.width * scale, height: artwork.size.height * scale)
        artwork.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: assets.appendingPathComponent(path))
}
for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    try export("App Icon.imagestack/Back.imagestacklayer/Content.imageset/icon-back\(suffix).png", 400 * scale, 240 * scale, artwork: icon, opaque: true)
    try export("App Icon.imagestack/Front.imagestacklayer/Content.imageset/icon-front\(suffix).png", 400 * scale, 240 * scale, artwork: nil, opaque: false)
    try export("Top Shelf Image.imageset/topshelf\(suffix).png", 1920 * scale, 720 * scale, artwork: wordmark, opaque: true)
    try export("Top Shelf Image Wide.imageset/topshelf-wide\(suffix).png", 2320 * scale, 720 * scale, artwork: wordmark, opaque: true)
}
try export("App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/icon-store-back.png", 1280, 768, artwork: icon, opaque: true)
try export("App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/icon-store-front.png", 1280, 768, artwork: nil, opaque: false)
print("Exported CouchWave app icons and Top Shelf artwork")

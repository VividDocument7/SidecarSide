// Renders AppIcon.iconset PNGs: usage `make-icon <output.iconset>`
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824pt body inset 100pt, ~185pt corner radius.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.62, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.08, green: 0.36, blue: 0.92, alpha: 1))!.draw(in: path, angle: -90)

    func symbol(_ name: String, _ size: CGFloat, alpha: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: size * s, weight: .medium)
            .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(alpha)]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    }
    let mac = symbol("laptopcomputer", 330, alpha: 1)
    let pad = symbol("ipad.landscape", 230, alpha: 0.85)
    let gap = 26 * s
    let total = mac.size.width + gap + pad.size.width
    let x0 = (CGFloat(px) - total) / 2
    mac.draw(in: NSRect(x: x0, y: (CGFloat(px) - mac.size.height) / 2, width: mac.size.width, height: mac.size.height))
    pad.draw(in: NSRect(x: x0 + mac.size.width + gap, y: (CGFloat(px) - pad.size.height) / 2 + 10 * s,
                        width: pad.size.width, height: pad.size.height))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

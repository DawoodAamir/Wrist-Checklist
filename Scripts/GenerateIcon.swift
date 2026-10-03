import AppKit
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.055, green: 0.14, blue: 0.16, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let paper = NSBezierPath(roundedRect: NSRect(x: 230, y: 150, width: 564, height: 724), xRadius: 72, yRadius: 72)
NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); paper.fill()
for i in 0..<3 {
    let y = CGFloat(700 - i * 182)
    NSColor(calibratedRed: 0.17, green: 0.50, blue: 0.43, alpha: 1).setStroke()
    let check = NSBezierPath(); check.lineWidth = 26; check.lineCapStyle = .round; check.lineJoinStyle = .round
    check.move(to: NSPoint(x: 300, y: y)); check.line(to: NSPoint(x: 328, y: y - 26)); check.line(to: NSPoint(x: 372, y: y + 30)); check.stroke()
    NSColor(calibratedWhite: 0.38, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 436, y: y - 12, width: 254, height: 24), xRadius: 12, yRadius: 12).fill()
}
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using: .png, properties: [:])!
for catalog in ["Phone", "Watch"] {
    try data.write(to: URL(fileURLWithPath: "Resources/\(catalog).xcassets/AppIcon.appiconset/Icon.png"))
}

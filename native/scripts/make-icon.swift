import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 40, y: CGFloat(pixels) / 40)
        context.cgContext.translateBy(x: 0, y: 40)
        context.cgContext.scaleBy(x: 1, y: -1)
        let rect = NSRect(x: 2, y: 2, width: 36, height: 36)
        let background = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSColor(calibratedRed: 0.208, green: 0.420, blue: 0.980, alpha: 1).setFill(); background.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke(); background.lineWidth = 0.35; background.stroke()
        // The same S ribbon as the navigation mark, inset to the macOS icon safe area.
        context.cgContext.translateBy(x: 2, y: 2); context.cgContext.scaleBy(x: 0.9, y: 0.9)
        let ribbon = NSBezierPath()
        ribbon.move(to: NSPoint(x: 27, y: 11)); ribbon.line(to: NSPoint(x: 17, y: 11))
        ribbon.curve(to: NSPoint(x: 17, y: 20), controlPoint1: NSPoint(x: 8, y: 11), controlPoint2: NSPoint(x: 8, y: 20))
        ribbon.line(to: NSPoint(x: 23, y: 20))
        ribbon.curve(to: NSPoint(x: 23, y: 29), controlPoint1: NSPoint(x: 32, y: 20), controlPoint2: NSPoint(x: 32, y: 29))
        ribbon.line(to: NSPoint(x: 13, y: 29))
        NSColor.white.setStroke(); ribbon.lineWidth = 3.4; ribbon.lineCapStyle = .round; ribbon.lineJoinStyle = .round; ribbon.stroke()
        NSColor(calibratedRed: 0.722, green: 0.824, blue: 1, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 28.4, y: 7.2, width: 4, height: 4), xRadius: 1, yRadius: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
// ICNS supports PNG payloads directly. Pack every standard density without relying on iconutil.
let entries = [("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
               ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
               ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
               ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
               ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")]
func lengthBytes(_ count: Int) -> Data {
    var value = UInt32(count).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var payload = Data()
for (type, filename) in entries {
    let png = try Data(contentsOf: output.appendingPathComponent(filename))
    payload.append(Data(type.utf8)); payload.append(lengthBytes(png.count + 8)); payload.append(png)
}
var icon = Data("icns".utf8)
icon.append(lengthBytes(payload.count + 8)); icon.append(payload)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)

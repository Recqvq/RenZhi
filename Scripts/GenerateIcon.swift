import AppKit

// All artwork is drawn here; no downloaded images or fonts are required.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let variants = [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),
                ("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),
                ("512x512",512),("512x512@2x",1024)]
for (name, size) in variants {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 230, yRadius: 230)
    NSGradient(starting: NSColor(srgbRed: 0.14, green: 0.54, blue: 0.94, alpha: 1),
               ending: NSColor(srgbRed: 0.09, green: 0.31, blue: 0.79, alpha: 1))!.draw(in: tile, angle: -90)
    let ring = NSBezierPath(ovalIn: NSRect(x: 232, y: 232, width: 560, height: 560))
    NSColor.white.withAlphaComponent(0.9).setStroke(); ring.lineWidth = 43; ring.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x:512,y:512), radius:280, startAngle:90, endAngle:230, clockwise:true)
    NSColor(srgbRed:0.45,green:0.95,blue:0.8,alpha:1).setStroke()
    arc.lineWidth=43; arc.lineCapStyle = .round; arc.stroke()
    let hands = NSBezierPath()
    hands.move(to:NSPoint(x:512,y:685)); hands.line(to:NSPoint(x:512,y:512)); hands.line(to:NSPoint(x:640,y:430))
    NSColor.white.setStroke(); hands.lineWidth=35; hands.lineCapStyle = .round; hands.lineJoinStyle = .round; hands.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to:output.appendingPathComponent("icon_\(name).png"))
}

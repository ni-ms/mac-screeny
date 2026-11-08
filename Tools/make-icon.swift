import AppKit

// Reproducible vector artwork, rasterized at every macOS icon size.
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
func render(_ size: Int) -> Data {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(size)); c.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    let tile = CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864), cornerWidth: 192, cornerHeight: 192, transform: nil)
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: CGColor(gray: 0, alpha: 0.2))
    c.setFillColor(color(0.47, 0.37, 0.88)); c.addPath(tile); c.fillPath(); c.restoreGState()
    c.saveGState(); c.addPath(tile); c.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0.62, 0.52, 0.98), color(0.36, 0.25, 0.75)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: 180, y: 80), end: CGPoint(x: 840, y: 944), options: [])
    c.restoreGState()
    let paper = CGPath(roundedRect: CGRect(x: 210, y: 234, width: 604, height: 510), cornerWidth: 64, cornerHeight: 64, transform: nil)
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: CGColor(gray: 0, alpha: 0.2))
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.addPath(paper); c.fillPath(); c.restoreGState()
    c.saveGState(); c.addPath(paper); c.clip()
    c.setFillColor(color(0.94, 0.92, 1)); c.fill(CGRect(x: 210, y: 234, width: 604, height: 100))
    c.setFillColor(color(0.72, 0.65, 0.89))
    for x in [266, 308, 350] { c.fillEllipse(in: CGRect(x: x, y: 275, width: 18, height: 18)) }
    c.restoreGState()
    c.setStrokeColor(color(0.47, 0.37, 0.88)); c.setLineWidth(38); c.setLineCap(.round)
    c.move(to: CGPoint(x: 285, y: 583))
    c.addCurve(to: CGPoint(x: 454, y: 548), control1: CGPoint(x: 316, y: 408), control2: CGPoint(x: 480, y: 419))
    c.addCurve(to: CGPoint(x: 638, y: 492), control1: CGPoint(x: 414, y: 704), control2: CGPoint(x: 629, y: 681))
    c.strokePath()
    c.saveGState(); c.translateBy(x: 737, y: 666); c.rotate(by: .pi / 4)
    c.setShadow(offset: CGSize(width: 3, height: 6), blur: 12, color: CGColor(gray: 0, alpha: 0.16))
    let pen = CGMutablePath(); pen.addRoundedRect(in: CGRect(x: -32, y: -171, width: 64, height: 252), cornerWidth: 22, cornerHeight: 22)
    c.setFillColor(color(0.30, 0.21, 0.61)); c.setStrokeColor(CGColor(gray: 1, alpha: 1)); c.setLineWidth(12)
    c.addPath(pen); c.drawPath(using: .fillStroke)
    c.setShadow(offset: .zero, blur: 0)
    c.move(to: CGPoint(x: -30, y: 81)); c.addLine(to: CGPoint(x: 30, y: 81)); c.addLine(to: CGPoint(x: 0, y: 143)); c.closePath()
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath()
    c.move(to: CGPoint(x: -10, y: 120)); c.addLine(to: CGPoint(x: 10, y: 120)); c.addLine(to: CGPoint(x: 0, y: 143)); c.closePath()
    c.setFillColor(color(0.30, 0.21, 0.61)); c.fillPath(); c.restoreGState()
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let data = render(points * scale)
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if points == 512 && scale == 2 { try data.write(to: root.appendingPathComponent("Assets/AppIcon.png")) }
    }
}

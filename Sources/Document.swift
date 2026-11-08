import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

struct Item {
    let id = UUID()
    var path: CGPath?
    var image: CGImage?
    var color = NSColor.labelColor
    var width: CGFloat = 6
    var filled = false
    var offset = CGPoint.zero
    var erasures: [CGPath] = []
    var localBounds: CGRect {
        if let image { return CGRect(x: 0, y: 0, width: image.width, height: image.height) }
        return (path?.boundingBoxOfPath ?? .zero).insetBy(dx: -width / 2, dy: -width / 2)
    }
    var bounds: CGRect { localBounds.offsetBy(dx: offset.x, dy: offset.y) }
    private static let hitContext = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    func hit(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        guard image != nil || color.alphaComponent > 0 else { return false }
        let p = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
        guard !erasures.contains(where: { $0.contains(p) }) else { return false }
        if let image {
            guard localBounds.contains(p), let pixel = image.cropping(to: CGRect(x: floor(p.x), y: floor(p.y), width: 1, height: 1)) else { return false }
            let c = Self.hitContext
            c.setBlendMode(.copy); c.interpolationQuality = .none
            c.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return c.data!.assumingMemoryBound(to: UInt8.self)[3] > 0
        }
        guard let path else { return false }
        return filled ? path.contains(p) : path.copy(strokingWithWidth: width + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(p)
    }
    func draw(_ c: CGContext) {
        c.saveGState()
        c.translateBy(x: offset.x, y: offset.y)
        if !erasures.isEmpty {
            c.clip(to: localBounds.insetBy(dx: -1, dy: -1))
            c.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        if let image {
            c.saveGState()
            c.translateBy(x: 0, y: CGFloat(image.height))
            c.scaleBy(x: 1, y: -1)
            c.draw(image, in: localBounds)
            c.restoreGState()
        } else if let path {
            c.setStrokeColor(color.cgColor); c.setFillColor(color.cgColor)
            c.setLineWidth(width); c.setLineCap(.round); c.setLineJoin(.round)
            c.addPath(path)
            if filled { c.fillPath() } else { c.strokePath() }
        }
        if !erasures.isEmpty {
            c.setBlendMode(.clear)
            for mask in erasures { c.addPath(mask); c.fillPath() }
            c.endTransparencyLayer()
        }
        c.restoreGState()
    }
}

struct Scene {
    var size = CGSize(width: 1600, height: 1000)
    var items: [Item] = []
    var revision = UUID()
    var isEmpty: Bool { items.isEmpty }
    func render(_ c: CGContext) {
        c.saveGState(); c.clip(to: CGRect(origin: .zero, size: size))
        for item in items { item.draw(c) }
        c.restoreGState()
    }
    func image(jpeg: Bool = false) -> CGImage? {
        guard let c = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if jpeg { c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(origin: .zero, size: size)) }
        c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
        render(c)
        return c.makeImage()
    }
}

// Snapshots share immutable paths and images; no raster snapshots while drawing.
final class Document {
    var scene = Scene()
    var savedRevision: UUID?
    var undoStack: [Scene] = []
    var redoStack: [Scene] = []
    let undoLimit = 128 * 1024 * 1024
    var changed: (() -> Void)?
    var dirty: Bool { savedRevision.map { $0 != scene.revision } ?? !scene.items.isEmpty }
    func commit(_ before: Scene) {
        undoStack.append(before); redoStack.removeAll(); scene.revision = UUID()
        trim(); changed?()
    }
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(scene); scene = previous; trim(); changed?()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(scene); scene = next; trim(); changed?()
    }
    func reset(_ replacement: Scene = Scene(), saved: Bool = true) {
        scene = replacement; undoStack.removeAll(); redoStack.removeAll()
        savedRevision = saved ? scene.revision : nil; changed?()
    }
    var retainedUndoBytes: Int {
        var live = Set(scene.items.compactMap { $0.image.map { ObjectIdentifier($0) } })
        var bytes = 0
        for s in undoStack + redoStack {
            bytes += s.items.count * 256
            for item in s.items {
                if let image = item.image, live.insert(ObjectIdentifier(image)).inserted { bytes += image.bytesPerRow * image.height }
                if let p = item.path { bytes += pathCost(p) }
                for mask in item.erasures { bytes += pathCost(mask) }
            }
        }
        return bytes
    }
    private func trim() {
        while undoStack.count + redoStack.count > 50 || retainedUndoBytes > undoLimit {
            if !undoStack.isEmpty { undoStack.removeFirst() }
            else if !redoStack.isEmpty { redoStack.removeFirst() }
            else { break }
        }
    }
    func insert(_ images: [CGImage]) {
        guard !images.isEmpty else { return }
        let before = scene
        if scene.isEmpty && images.count == 1 { scene.size = CGSize(width: images[0].width, height: images[0].height) }
        for (i, image) in images.enumerated() {
            let x = max(0, (scene.size.width - CGFloat(image.width)) / 2) + CGFloat(i * 20)
            let y = max(0, (scene.size.height - CGFloat(image.height)) / 2) + CGFloat(i * 20)
            scene.items.append(Item(image: image, offset: CGPoint(x: x, y: y)))
        }
        commit(before)
    }
    func crop(_ rect: CGRect) {
        let r = rect.integral.intersection(CGRect(origin: .zero, size: scene.size))
        guard r.width >= 1, r.height >= 1 else { return }
        let before = scene
        for i in scene.items.indices { scene.items[i].offset.x -= r.minX; scene.items[i].offset.y -= r.minY }
        scene.size = r.size; commit(before)
    }
}

func pathCost(_ path: CGPath) -> Int {
    var count = 0
    path.applyWithBlock { _ in count += 64 }
    return count
}

func decodeImage(_ data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    // Own the decoded pixels so history cannot retain an unaccounted compressed source.
    c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return c.makeImage()
}

func clipboardImages(_ board: NSPasteboard) -> [CGImage] {
    var result: [CGImage] = []
    for item in board.pasteboardItems ?? [] {
        // One result per pasteboard item, irrespective of alternative encodings.
        var image: CGImage?
        let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff]
        let types = preferred + item.types.filter { !preferred.contains($0) && (UTType($0.rawValue)?.conforms(to: .image) ?? false) }
        for type in types {
            if let data = item.data(forType: type), let decoded = decodeImage(data) { image = decoded; break }
        }
        if image == nil, let string = item.string(forType: .fileURL), let url = URL(string: string), url.isFileURL,
           let data = try? Data(contentsOf: url) { image = decodeImage(data) }
        if let image { result.append(image) }
    }
    return result
}

func imageData(_ image: CGImage, jpeg: Bool = false) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, (jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

final class ImageHistory {
    struct Entry { let id = UUID(); let image: CGImage; var bytes: Int { image.bytesPerRow * image.height } }
    var entries: [Entry] = []
    let limit = 64 * 1024 * 1024
    var bytes: Int { entries.reduce(0) { $0 + $1.bytes } }
    func add(_ images: [CGImage]) {
        for image in images {
            let entry = Entry(image: image)
            guard entry.bytes <= limit else { continue }
            entries.append(entry)
            while entries.count > 5 || bytes > limit { entries.removeFirst() }
        }
    }
    func clear() { entries.removeAll() }
}

func textPath(_ string: String, size: CGFloat) -> CGPath {
    let font = CTFontCreateWithName(".AppleSystemUIFont" as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n), points = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &points)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        for i in 0..<n {
            if let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                path.addPath(glyph, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: points[i].x, ty: size - points[i].y))
            }
        }
    }
    return path
}

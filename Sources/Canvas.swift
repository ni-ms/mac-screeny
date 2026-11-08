import AppKit

enum Tool: String, CaseIterable { case move = "Move", brush = "Brush", eraser = "Eraser", arrow = "Arrow", rectangle = "Rectangle", ellipse = "Ellipse", text = "Text", crop = "Select / Crop" }

final class Canvas: NSView, NSTextViewDelegate {
    let document: Document
    var tool = Tool.brush { didSet { finishText(switchToMove: false); cancelEdit(); selection = nil; needsDisplay = true; window?.invalidateCursorRects(for: self); toolChanged?() } }
    var objectEraser = false
    var color = NSColor(calibratedWhite: 0.12, alpha: 1)
    var strokeWidth: CGFloat = 6
    var textSize: CGFloat = 24
    var zoom: CGFloat = 0.5
    var angle: CGFloat = 0
    var pan = CGPoint.zero
    var isFit = true
    var toolChanged: (() -> Void)?
    var editor: InlineTextView?
    var textOrigin = CGPoint.zero
    var horizontalScroller = NSScroller(frame: CGRect(x: 0, y: 0, width: 100, height: 14))
    var verticalScroller = NSScroller(frame: CGRect(x: 0, y: 0, width: 14, height: 100))
    var scrollRange = CGSize.zero
    var viewport: CGRect { CGRect(x: 0, y: 0, width: max(1, bounds.width - 14), height: max(1, bounds.height - 14)) }
    var navigationChanged: (() -> Void)?
    var droppedImages: (([CGImage]) -> Void)?
    var selection: CGRect?
    var selected = Set<UUID>()
    var before: Scene?
    var start = CGPoint.zero
    var last = CGPoint.zero
    var path = CGMutablePath()
    var preview: Item?
    var moving: [UUID: CGPoint] = [:]
    var editChanged = false
    var gestureActive = false
    var scrolling = false
    var suppressMouse = false
    var spaceDown = false
    var panning = false
    init(_ document: Document) {
        self.document = document
        super.init(frame: .zero)
        clipsToBounds = true
        for scroller in [horizontalScroller, verticalScroller] {
            scroller.scrollerStyle = .legacy; scroller.controlSize = .small; scroller.isEnabled = true
            scroller.target = self; scroller.action = #selector(scrollbarChanged(_:)); addSubview(scroller)
        }
        horizontalScroller.setAccessibilityLabel("Horizontal canvas position")
        verticalScroller.setAccessibilityLabel("Vertical canvas position")
        registerForDraggedTypes([.fileURL, .png, .tiff])
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("Drawing canvas")
        setAccessibilityHelp("Choose a tool to draw. Space drag pans. Use the View menu for zoom and rotation.")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var transform: CGAffineTransform {
        let a = zoom * cos(angle), b = zoom * sin(angle), c = -b, d = a
        let s = document.scene.size
        return CGAffineTransform(a: a, b: b, c: c, d: d, tx: viewport.midX + pan.x - a * s.width / 2 - c * s.height / 2, ty: viewport.midY + pan.y - b * s.width / 2 - d * s.height / 2)
    }
    func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }
    func canvasPoint(_ event: NSEvent) -> CGPoint { point(event).applying(transform.inverted()) }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); if isFit { fit() } else { syncNavigation() } }
    func fit() {
        finishText()
        let size = document.scene.size
        zoom = min((viewport.width - 48) / size.width, (viewport.height - 48) / size.height)
        zoom = max(0.01, zoom); pan = .zero; angle = 0; isFit = true
        needsDisplay = true; syncNavigation()
    }
    func navigate(zoom newZoom: CGFloat? = nil, rotation: CGFloat? = nil, anchor: CGPoint? = nil) {
        finishText(); cancelEdit(); suppressMouse = true
        let anchor = anchor ?? CGPoint(x: viewport.midX, y: viewport.midY)
        let pixel = anchor.applying(transform.inverted())
        if let newZoom { zoom = max(0.01, min(32, newZoom)) }
        if let rotation { angle = rotation }
        let after = pixel.applying(transform)
        pan.x += anchor.x - after.x; pan.y += anchor.y - after.y
        isFit = false; needsDisplay = true; syncNavigation()
    }
    override func draw(_ dirtyRect: NSRect) {
        ScreenyStyle.workspace.setFill(); dirtyRect.fill()
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); c.clip(to: viewport); c.concatenate(transform)
        let canvas = CGRect(origin: .zero, size: document.scene.size)
        c.saveGState(); c.clip(to: canvas)
        c.setFillColor(NSColor.white.cgColor); c.fill(canvas)
        document.scene.render(c); preview?.draw(c)
        c.restoreGState()
        c.setStrokeColor(NSColor.separatorColor.cgColor); c.setLineWidth(1 / zoom); c.stroke(canvas)
        c.setStrokeColor(ScreenyStyle.accent.cgColor); c.setLineWidth(1 / zoom)
        c.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
        if let selection { c.stroke(selection) }
        for item in document.scene.items where selected.contains(item.id) { c.stroke(item.bounds.insetBy(dx: -2 / zoom, dy: -2 / zoom)) }
        c.restoreGState()
    }
    func invalidate(_ rect: CGRect) { setNeedsDisplay(rect.applying(transform).insetBy(dx: -4, dy: -4)) }
    func cancelEdit() {
        if let before { document.scene = before; needsDisplay = true }
        before = nil; preview = nil; moving.removeAll(); editChanged = false
    }
    override func mouseDown(with event: NSEvent) {
        if editor != nil { finishText() }
        window?.makeFirstResponder(self)
        suppressMouse = false
        if gestureActive || scrolling { suppressMouse = true; return }
        if spaceDown || event.buttonNumber == 2 { panning = true; last = point(event); cancelEdit(); return }
        let p = canvasPoint(event)
        guard CGRect(origin: .zero, size: document.scene.size).contains(p) else { return }
        before = document.scene; start = p; last = p; editChanged = false
        path = CGMutablePath(); path.move(to: p); path.addLine(to: CGPoint(x: p.x + 0.001, y: p.y))
        selected = tool == .move ? selected : []
        switch tool {
        case .move:
            if let item = document.scene.items.reversed().first(where: { $0.hit(p, tolerance: 3 / zoom) }) {
                if event.modifierFlags.contains(.shift) { if !selected.insert(item.id).inserted { selected.remove(item.id) } }
                else if !selected.contains(item.id) { selected = [item.id] }
                moving = Dictionary(uniqueKeysWithValues: document.scene.items.filter { selected.contains($0.id) }.map { ($0.id, $0.offset) })
            } else { selected.removeAll() }
            needsDisplay = true
        case .text:
            before = nil; insertText(at: p)
        case .eraser: erase(at: p)
        case .crop: selection = CGRect(origin: p, size: .zero); needsDisplay = true
        default: updatePreview(to: p)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        if panning { let p = point(event); pan.x += p.x - last.x; pan.y += p.y - last.y; last = p; isFit = false; needsDisplay = true; syncNavigation(); return }
        guard !suppressMouse, !gestureActive, !scrolling, before != nil else { return }
        let p = canvasPoint(event)
        switch tool {
        case .move:
            for i in document.scene.items.indices {
                if let offset = moving[document.scene.items[i].id] { document.scene.items[i].offset = CGPoint(x: offset.x + p.x - start.x, y: offset.y + p.y - start.y); editChanged = true }
            }
            needsDisplay = true
        case .brush: path.addLine(to: p); updatePreview(to: p)
        case .eraser: path.addLine(to: p); erase(at: p)
        case .crop: selection = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y)); needsDisplay = true
        default: updatePreview(to: p)
        }
        last = p
    }
    override func mouseUp(with event: NSEvent) {
        if panning { panning = false; return }
        guard !suppressMouse, let old = before else { cancelEdit(); return }
        let created = preview
        if let preview { document.scene.items.append(preview); editChanged = true }
        before = nil; preview = nil; moving.removeAll()
        if editChanged { document.commit(old) }
        if let created { selected = [created.id]; tool = .move }
        needsDisplay = true
    }
    override func otherMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }
    func updatePreview(to p: CGPoint) {
        let previous = preview?.bounds
        let shape = CGMutablePath()
        let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        switch tool {
        case .brush: shape.addPath(path)
        case .rectangle: shape.addRect(rect)
        case .ellipse: shape.addEllipse(in: rect)
        case .arrow:
            shape.move(to: start); shape.addLine(to: p)
            let angle = atan2(p.y - start.y, p.x - start.x), length = max(12, strokeWidth * 3)
            for sign: CGFloat in [-1, 1] { shape.move(to: p); shape.addLine(to: CGPoint(x: p.x - length * cos(angle + sign * .pi / 6), y: p.y - length * sin(angle + sign * .pi / 6))) }
        default: return
        }
        preview = Item(path: shape.copy(), color: color, width: strokeWidth)
        if tool == .brush {
            invalidate(CGRect(x: min(last.x, p.x), y: min(last.y, p.y), width: abs(p.x-last.x), height: abs(p.y-last.y)).insetBy(dx: -strokeWidth, dy: -strokeWidth))
        } else { if let previous { invalidate(previous) }; invalidate(preview!.bounds) }
    }
    func erase(at p: CGPoint) {
        if objectEraser {
            // Imported images are single objects; their internal pixels are never inferred as objects.
            let steps = max(1, Int(ceil(hypot(p.x - last.x, p.y - last.y) * 2)))
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let hit = CGPoint(x: last.x + (p.x - last.x) * t, y: last.y + (p.y - last.y) * t)
                guard CGRect(origin: .zero, size: document.scene.size).contains(hit) else { continue }
                if let index = document.scene.items.lastIndex(where: { $0.hit(hit) }) {
                    invalidate(document.scene.items[index].bounds); document.scene.items.remove(at: index); editChanged = true
                }
            }
        } else if let before {
            let mask = path.copy(strokingWithWidth: strokeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
            let bounds = mask.boundingBoxOfPath
            document.scene.items = before.items.map { original in
                var item = original
                if item.bounds.intersects(bounds) {
                    var t = CGAffineTransform(translationX: -item.offset.x, y: -item.offset.y)
                    if let local = mask.copy(using: &t) { item.erasures.append(local); editChanged = true }
                }
                return item
            }
            invalidate(CGRect(x: min(last.x, p.x), y: min(last.y, p.y), width: abs(p.x-last.x), height: abs(p.y-last.y)).insetBy(dx: -strokeWidth, dy: -strokeWidth))
        }
    }
    func insertText(at p: CGPoint) {
        finishText()
        textOrigin = p
        let width = max(40, document.scene.size.width - p.x)
        let storage = NSTextStorage()
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0; container.widthTracksTextView = false; container.heightTracksTextView = false; layout.addTextContainer(container)
        let editor = InlineTextView(frame: CGRect(x: 0, y: 0, width: width, height: textSize * 1.5), textContainer: container)
        editor.font = .systemFont(ofSize: textSize); editor.textColor = color
        editor.insertionPointColor = ScreenyStyle.accent; editor.drawsBackground = false
        editor.isRichText = false; editor.allowsUndo = true; editor.textContainerInset = .zero
        editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.delegate = self; editor.setAccessibilityLabel("Canvas text")
        editor.didResign = { [weak self] in self?.finishText(focus: false) }
        self.editor = editor; addSubview(editor, positioned: .below, relativeTo: horizontalScroller)
        positionEditor(); window?.makeFirstResponder(editor)
    }
    func positionEditor() {
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        layout.ensureLayout(for: container)
        let size = CGSize(width: container.size.width, height: max(textSize * 1.5, layout.usedRect(for: container).maxY + 4))
        editor.frameRotation = angle * 180 / .pi
        editor.setFrameSize(CGSize(width: size.width * zoom, height: size.height * zoom))
        editor.setBoundsSize(size)
        let target = textOrigin.applying(transform), origin = editor.convert(CGPoint.zero, to: self)
        editor.setFrameOrigin(CGPoint(x: editor.frame.origin.x + target.x - origin.x, y: editor.frame.origin.y + target.y - origin.y))
    }
    func updateTextStyle() {
        editor?.font = .systemFont(ofSize: textSize); editor?.textColor = color; positionEditor()
    }
    func textDidChange(_ notification: Notification) { positionEditor() }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishText(cancel: true); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { textView.insertText("\n", replacementRange: textView.selectedRange()) }
            else { finishText() }
            return true
        }
        return false
    }
    func finishText(cancel: Bool = false, switchToMove: Bool = true, focus: Bool = true) {
        guard let editor else { return }
        self.editor = nil; editor.didResign = nil
        if !cancel && !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let layout = editor.layoutManager, let container = editor.textContainer {
            layout.ensureLayout(for: container)
            let outline = CGMutablePath()
            layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                let string = (editor.string as NSString).substring(with: characters).trimmingCharacters(in: .newlines)
                let line = textPath(string, size: self.textSize)
                let baseline = layout.location(forGlyphAt: glyphs.location)
                outline.addPath(line, transform: CGAffineTransform(translationX: rect.minX + baseline.x, y: rect.minY + baseline.y - self.textSize))
            }
            let old = document.scene
            let item = Item(path: outline.copy(), color: editor.textColor ?? color, width: 0, filled: true, offset: textOrigin)
            document.scene.items.append(item); selected = [item.id]; document.commit(old)
        }
        editor.removeFromSuperview()
        if switchToMove { tool = .move }
        if focus { window?.makeFirstResponder(self) }
        needsDisplay = true
    }
    override func resetCursorRects() {
        addCursorRect(viewport, cursor: tool == .move ? .arrow : tool == .text ? .iBeam : .crosshair)
    }
    override func layout() {
        super.layout()
        horizontalScroller.frame = CGRect(x: 0, y: viewport.maxY, width: viewport.width, height: 14)
        verticalScroller.frame = CGRect(x: viewport.maxX, y: 0, width: 14, height: viewport.height)
        syncNavigation()
    }
    func syncNavigation() {
        let image = CGRect(origin: .zero, size: document.scene.size).applying(transform)
        scrollRange = CGSize(width: max(abs(pan.x), (viewport.width + image.width) / 2 - 24, 1), height: max(abs(pan.y), (viewport.height + image.height) / 2 - 24, 1))
        for (scroller, range, position, length) in [(horizontalScroller, scrollRange.width, pan.x, viewport.width), (verticalScroller, scrollRange.height, pan.y, viewport.height)] {
            scroller.doubleValue = Double((1 - position / range) / 2)
            scroller.knobProportion = length / (length + range * 2)
        }
        positionEditor(); navigationChanged?()
    }
    @objc func scrollbarChanged(_ sender: NSScroller) {
        finishText(); cancelEdit()
        let horizontal = sender === horizontalScroller
        let range = horizontal ? scrollRange.width : scrollRange.height
        let length = horizontal ? viewport.width : viewport.height
        var value = horizontal ? pan.x : pan.y
        switch sender.hitPart {
        case .decrementLine: value += 32
        case .incrementLine: value -= 32
        case .decrementPage: value += length * 0.85
        case .incrementPage: value -= length * 0.85
        default: value = range * (1 - CGFloat(sender.doubleValue) * 2)
        }
        if horizontal { pan.x = max(-range, min(range, value)) } else { pan.y = max(-range, min(range, value)) }
        isFit = false; needsDisplay = true; syncNavigation()
    }
    func center() { finishText(); cancelEdit(); pan = .zero; isFit = false; needsDisplay = true; syncNavigation() }
    override func beginGesture(with event: NSEvent) { finishText(); cancelEdit(); gestureActive = true; suppressMouse = true }
    override func endGesture(with event: NSEvent) { gestureActive = false }
    override func magnify(with event: NSEvent) { navigate(zoom: zoom * (1 + event.magnification), anchor: point(event)) }
    override func rotate(with event: NSEvent) { navigate(rotation: angle - CGFloat(event.rotation) * .pi / 180, anchor: point(event)) }
    override func smartMagnify(with event: NSEvent) { if isFit { navigate(zoom: 1, anchor: point(event)) } else { cancelEdit(); fit() } }
    override func scrollWheel(with event: NSEvent) {
        finishText(); cancelEdit(); suppressMouse = true
        scrolling = event.phase == .began || event.phase == .changed || event.momentumPhase == .began || event.momentumPhase == .changed
        let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        if event.modifierFlags.contains(.command) { navigate(zoom: zoom * exp(event.scrollingDeltaY * 0.01), anchor: point(event)) }
        else { pan.x += event.scrollingDeltaX * factor; pan.y += event.scrollingDeltaY * factor; isFit = false; needsDisplay = true; syncNavigation() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { spaceDown = true; return }
        if event.keyCode == 53 { cancelEdit(); selection = nil; selected.removeAll(); needsDisplay = true; return }
        if event.keyCode == 36 { cropSelection(); return }
        if event.keyCode == 51 || event.keyCode == 117 {
            let old = document.scene; document.scene.items.removeAll { selected.contains($0.id) }
            if old.items.count != document.scene.items.count { selected.removeAll(); document.commit(old) }; return
        }
        let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let shifts: [UInt16: CGPoint] = [123: CGPoint(x: -delta, y: 0), 124: CGPoint(x: delta, y: 0), 125: CGPoint(x: 0, y: delta), 126: CGPoint(x: 0, y: -delta)]
        if let shift = shifts[event.keyCode] {
            if selected.isEmpty { pan.x += shift.x * 20; pan.y += shift.y * 20; isFit = false; needsDisplay = true; syncNavigation() }
            else { let old = document.scene; for i in document.scene.items.indices where selected.contains(document.scene.items[i].id) { document.scene.items[i].offset.x += shift.x; document.scene.items[i].offset.y += shift.y }; document.commit(old) }
            return
        }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { spaceDown = false } else { super.keyUp(with: event) } }
    func cropSelection() { if let selection { cancelEdit(); document.crop(selection); self.selection = nil; tool = .move; fit() } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = clipboardImages(sender.draggingPasteboard)
        guard !images.isEmpty else { return false }; droppedImages?(images); return true
    }
}

final class InlineTextView: NSTextView {
    var didResign: (() -> Void)?
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { didResign?() }
        return result
    }
}

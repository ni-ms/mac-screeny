import AppKit

// These events exercise screeny's native NSView event handlers without global input injection.
final class GestureEvent: NSEvent {
    var location = CGPoint.zero
    var mag: CGFloat = 0
    var degrees: Float = 0
    var dx: CGFloat = 0, dy: CGFloat = 0
    var scrollStage: NSEvent.Phase = []
    var momentum: NSEvent.Phase = []
    override var locationInWindow: NSPoint { location }
    override var magnification: CGFloat { mag }
    override var rotation: Float { degrees }
    override var scrollingDeltaX: CGFloat { dx }
    override var scrollingDeltaY: CGFloat { dy }
    override var phase: NSEvent.Phase { scrollStage }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
}

func runTests(app: App) -> Int32 {
    var checks = 0, failures = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { print("FAIL: \(name)"); failures += 1; fflush(stdout); return }
        checks += 1; print("PASS: \(name)"); fflush(stdout)
    }
    func fixture(_ w: Int, _ h: Int) -> CGImage {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(NSColor(calibratedRed: 0.2, green: 0.5, blue: 0.8, alpha: 1).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        c.setFillColor(NSColor.red.cgColor); c.fill(CGRect(x: 0, y: h - 80, width: 100, height: 80))
        c.clear(CGRect(x: w / 2, y: h / 2, width: 40, height: 40))
        return c.makeImage()!
    }
    func rgba(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let c = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = c.data!.assumingMemoryBound(to: UInt8.self); let i = (y * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: bytes + i, count: 4))
    }
    func mouse(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
        let viewPoint = p.applying(app.canvas.transform)
        return NSEvent.mouseEvent(with: type, location: app.canvas.convert(viewPoint, to: nil), modifierFlags: [], timestamp: 0, windowNumber: app.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    func gesture(_ points: [CGPoint]) {
        app.canvas.mouseDown(with: mouse(.leftMouseDown, points[0]))
        for p in points.dropFirst() { app.canvas.mouseDragged(with: mouse(.leftMouseDragged, p)) }
        app.canvas.mouseUp(with: mouse(.leftMouseUp, points.last!))
    }
    check(app.canvas.viewport.width > 600 && app.canvas.viewport.height > 400, "compact window reserves a usable canvas viewport")
    let savePanel = NSSavePanel(); savePanel.nameFieldStringValue = "Untitled.png"; app.exportPanel = savePanel
    let format = NSPopUpButton(); format.addItems(withTitles: ["PNG", "JPEG"]); format.selectItem(at: 1)
    app.exportFormatChanged(format)
    check(savePanel.nameFieldStringValue == "Untitled.jpeg" && savePanel.allowedContentTypes == [.jpeg], "JPEG format updates native dialog extension and allowed type")
    app.exportPanel = nil
    app.colorWell.openPicker()
    check(NSColorPanel.shared.isVisible && NSColorPanel.shared.showsAlpha, "full native color panel opens with opacity enabled")
    NSColorPanel.shared.close()
    let started = ProcessInfo.processInfo.systemUptime
    let board = NSPasteboard.general
    let saved = (board.pasteboardItems ?? []).map { item -> NSPasteboardItem in
        let copy = NSPasteboardItem(); for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }; return copy
    }
    defer { board.clearContents(); if !saved.isEmpty { board.writeObjects(saved) } }
    let image = fixture(3840, 2160)
    let png = imageData(image)!
    check(rgba(decodeImage(png)!, 10, 10) == rgba(image, 10, 10), "single image decode preserves orientation")
    let bitmap = NSBitmapImageRep(cgImage: image)
    let tiff = bitmap.tiffRepresentation!
    let one = NSPasteboardItem(); one.setData(png, forType: .png); one.setData(tiff, forType: .tiff)
    board.clearContents(); board.writeObjects([one])
    check(clipboardImages(board).count == 1, "PNG and TIFF alternatives read as one clipboard image")
    app.pasteImage()
    check(app.document.scene.size == CGSize(width: 3840, height: 2160), "single paste into empty canvas adopts original pixels")
    check(app.document.scene.items.count == 1 && app.history.entries.count == 1, "paste inserts image and records session history")
    app.copyImage()
    let copied = clipboardImages(board)
    check(copied.count == 1 && copied[0].width == 3840 && copied[0].height == 2160, "Copy uses original resolution")
    check(rgba(copied[0], 1930, 1050)[3] == 0, "Copy preserves PNG transparency")
    check(rgba(copied[0], 10, 10) == rgba(image, 10, 10), "copy preserves image orientation")
    let two = NSPasteboardItem(); two.setData(png, forType: .png)
    let multiOne = NSPasteboardItem(); multiOne.setData(png, forType: .png); multiOne.setData(tiff, forType: .tiff)
    board.clearContents(); board.writeObjects([multiOne, two])
    let oldCount = app.document.scene.items.count, undoCount = app.document.undoStack.count
    app.pasteImage()
    check(app.document.scene.items.count == oldCount + 2 && app.document.undoStack.count == undoCount + 1, "multi-item paste is one undo action")
    let suffix = Array(app.document.scene.items.suffix(2))
    check(suffix[0].id != suffix[1].id && suffix[0].offset != suffix[1].offset, "multi-paste creates distinct offset objects")
    app.undo(); check(app.document.scene.items.count == oldCount, "undo removes whole paste batch")
    app.redo(); check(app.document.scene.items.count == oldCount + 2, "redo restores paste batch")
    app.canvas.tool = .move
    gesture([CGPoint(x: 500, y: 500), CGPoint(x: 600, y: 550)])
    check(abs(app.document.scene.items.last!.offset.x - suffix[1].offset.x - 100) < 0.001, "pasted images move at document coordinates")
    app.history.clear(); app.history.add([image, image, image])
    check(app.history.entries.count == 2 && app.history.bytes <= app.history.limit, "64 MiB cap evicts oldest large screenshots")
    let small = fixture(32, 32); app.history.clear(); app.history.add(Array(repeating: small, count: 7))
    check(app.history.entries.count == 5, "history keeps at most five entries")
    let ids = app.history.entries.map(\.id); app.history.add([small]); check(!app.history.entries.contains { $0.id == ids.first }, "oldest history entry is evicted first")
    autoreleasepool {
        let huge = fixture(5000, 4000)
        app.history.clear(); app.insert([huge])
        check(app.history.entries.isEmpty && app.document.scene.items.last!.image!.width == 5000, "oversized image pastes but is omitted from history")
    }
    app.history.add([image]); let countBeforeClear = app.document.scene.items.count
    app.clearHistory()
    check(app.document.scene.items.count == countBeforeClear && app.history.entries.isEmpty, "clearing history preserves document images")
    app.rebuildHistory(); check(!app.insertButton.isEnabled && app.historyChecks.isEmpty, "empty history disables Insert selected")
    app.history.add([small, image]); app.rebuildHistory()
    app.historyChecks.forEach { $0.state = .on }; app.historySelectionChanged()
    check(app.insertButton.isEnabled, "history selection enables insertion")
    let beforeHistory = app.document.scene.items.count; app.insertHistory()
    check(app.document.scene.items.count == beforeHistory + 2, "selected historical images insert together")
    app.undo(); check(app.document.scene.items.count == beforeHistory, "historical batch undoes together")
    app.document.reset(Scene(size: CGSize(width: 3840, height: 2160), items: [Item(image: image)]))
    app.canvas.fit(); app.canvas.tool = .brush; app.canvas.strokeWidth = 20; app.canvas.color = .red
    gesture([CGPoint(x: 100, y: 200), CGPoint(x: 500, y: 200)])
    let stroke = app.document.scene.items.last!
    check(app.document.scene.items.count == 2, "brush creates an editable stroke")
    app.canvas.tool = .eraser; app.canvas.objectEraser = false; app.canvas.strokeWidth = 40
    gesture([CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 240)])
    let partiallyErased = app.document.scene.items.last!
    check(partiallyErased.id == stroke.id && !partiallyErased.hit(CGPoint(x: 300, y: 200)) && partiallyErased.hit(CGPoint(x: 150, y: 200)), "pixel eraser preserves identity and accurate visible hit geometry")
    let erased = app.document.scene.image()!
    check(rgba(erased, 300, 210)[3] == 0, "pixel eraser clears screenshot and annotation to transparency")
    let jpeg = decodeImage(imageData(app.document.scene.image(jpeg: true)!, jpeg: true)!)!
    check(rgba(jpeg, 300, 210).prefix(3).allSatisfy { $0 > 240 }, "JPEG flattens transparency to white")
    app.undo(); check(app.document.scene.items.last!.erasures.isEmpty, "pixel erase gesture undoes once")
    app.redo(); check(!app.document.scene.items.last!.erasures.isEmpty, "pixel erasure redoes")
    app.canvas.objectEraser = true
    let c = app.document.scene.items.count, u = app.document.undoStack.count
    gesture([CGPoint(x: 300, y: 210)])
    check(app.document.scene.items.count == c && app.document.undoStack.count == u, "object eraser on a pixel-erased area does nothing")
    let pastedID = app.document.scene.items.first!.id
    gesture([CGPoint(x: 700, y: 700)])
    check(app.document.scene.items.count == c - 1 && !app.document.scene.items.contains { $0.id == pastedID }, "object eraser removes a pasted image as one whole item")
    app.undo()
    check(app.document.scene.items.first!.id == pastedID && !app.document.scene.items.first!.erasures.isEmpty, "undo restores pasted image identity and existing pixel erasures")
    app.redo(); check(!app.document.scene.items.contains { $0.id == pastedID }, "redo removes the whole pasted image again")
    app.undo()
    gesture([CGPoint(x: 150, y: 200)])
    check(app.document.scene.items.count == 1 && app.document.scene.items[0].image != nil, "object eraser removes annotation and preserves screenshot")
    app.undo(); check(app.document.scene.items.last!.id == stroke.id, "object erase undo restores original identity")
    let p = CGMutablePath(); p.move(to: CGPoint(x: 100, y: 200)); p.addLine(to: CGPoint(x: 500, y: 200))
    let top = Item(path: p.copy(), color: .blue, width: 15); app.document.scene.items.append(top)
    gesture([CGPoint(x: 150, y: 200)])
    check(!app.document.scene.items.contains { $0.id == top.id } && app.document.scene.items.contains { $0.id == stroke.id }, "object eraser removes only topmost visible geometry per hit")
    app.document.scene.items.removeAll { $0.image != nil }
    app.canvas.tool = .rectangle; gesture([CGPoint(x: 600, y: 400), CGPoint(x: 800, y: 600)])
    app.canvas.tool = .ellipse; gesture([CGPoint(x: 900, y: 400), CGPoint(x: 1100, y: 600)])
    app.canvas.tool = .eraser; app.canvas.objectEraser = true
    let beforeShapes = app.document.scene.items.count
    gesture([CGPoint(x: 600, y: 500), CGPoint(x: 900, y: 500)])
    check(app.document.scene.items.count == beforeShapes - 2, "object erase drag removes multiple shapes")
    app.undo(); check(app.document.scene.items.count == beforeShapes, "multi-object erase is one undo action")
    let letters = Item(path: textPath("screeny", size: 48), width: 0, filled: true, offset: CGPoint(x: 1200, y: 400))
    app.document.scene.items.append(letters)
    var glyphPoint: CGPoint?
    for y in 400..<460 { for x in 1200..<1300 where letters.hit(CGPoint(x: x, y: y)) { glyphPoint = CGPoint(x: x, y: y); break }; if glyphPoint != nil { break } }
    check(glyphPoint != nil, "text retains visible glyph geometry")
    gesture([glyphPoint!]); check(!app.document.scene.items.contains { $0.id == letters.id }, "object eraser removes text item")
    let event = GestureEvent(); let anchor = CGPoint(x: 300, y: 280)
    event.location = app.canvas.convert(anchor, to: nil)
    let pixel = anchor.applying(app.canvas.transform.inverted())
    app.canvas.beginGesture(with: event); event.mag = 0.7; app.canvas.magnify(with: event); event.degrees = 37; app.canvas.rotate(with: event)
    let anchored = pixel.applying(app.canvas.transform)
    check(hypot(anchored.x-anchor.x, anchored.y-anchor.y) < 0.001, "pinch and rotation preserve pointer anchor")
    let itemCount = app.document.scene.items.count
    app.canvas.tool = .brush; gesture([CGPoint(x: 500, y: 500), CGPoint(x: 550, y: 550)])
    check(app.document.scene.items.count == itemCount, "navigation gesture prevents accidental drawing")
    app.canvas.endGesture(with: event)
    let previousPan = app.canvas.pan; event.dx = 30; event.dy = -20; event.scrollStage = .changed
    app.canvas.scrollWheel(with: event)
    check(app.canvas.pan == CGPoint(x: previousPan.x + 30, y: previousPan.y - 20), "two-finger scrolling respects AppKit natural-scroll deltas")
    event.scrollStage = []; event.momentum = .changed; app.canvas.scrollWheel(with: event)
    check(app.canvas.scrolling, "momentum keeps navigation edit guard active")
    event.momentum = .ended; event.dx = 0; event.dy = 0; app.canvas.scrollWheel(with: event)
    check(!app.canvas.scrolling, "momentum end releases edit guard")
    app.canvas.smartMagnify(with: event)
    check(app.canvas.isFit && app.canvas.angle == 0 && app.canvas.pan == .zero, "smart zoom returns to Fit and resets rotation and pan")
    app.canvas.smartMagnify(with: event); check(app.canvas.zoom == 1 && !app.canvas.isFit, "smart zoom toggles to 100 percent")
    app.canvas.navigate(zoom: 0.6, rotation: .pi / 5)
    app.canvas.tool = .eraser; app.canvas.objectEraser = true
    let visibleStroke = app.document.scene.items.first { $0.path != nil }!
    let hitPoint = CGPoint(x: 150, y: 200)
    gesture([hitPoint])
    check(!app.document.scene.items.contains { $0.id == visibleStroke.id }, "eraser hit testing remains accurate after zoom and rotation")
    check(app.document.scene.image()!.width == 3840 && app.document.scene.image()!.height == 2160, "navigation preserves export pixel dimensions")
    app.canvas.tool = .brush
    let startCount = app.document.scene.items.count
    app.canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 100))); app.canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 200, y: 100)))
    app.canvas.beginGesture(with: event); app.canvas.endGesture(with: event); app.canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 200, y: 100)))
    check(app.document.scene.items.count == startCount && app.canvas.preview == nil, "gesture cancels an in-progress stroke")
    let bounds = app.document.scene.size; app.document.crop(CGRect(x: 10, y: 10, width: 100, height: 200))
    check(app.document.scene.size == CGSize(width: 100, height: 200), "crop updates exact pixel dimensions")
    app.undo(); check(app.document.scene.size == bounds, "crop undoes without rasterizing objects")
    for _ in 0..<60 { let before = app.document.scene; app.document.scene.items.append(Item(path: p.copy())); app.document.commit(before) }
    check(app.document.undoStack.count <= 50 && app.document.retainedUndoBytes <= app.document.undoLimit, "undo memory and action count stay bounded")
    let invisible = Item(path: p.copy(), color: NSColor.clear, width: 20)
    check(!invisible.hit(CGPoint(x: 150, y: 200)), "fully transparent annotations do not hit-test as visible objects")
    autoreleasepool {
        let bounded = Document(); bounded.insert([fixture(7000, 5000)]); bounded.undo()
        check(bounded.retainedUndoBytes <= bounded.undoLimit && bounded.redoStack.isEmpty, "undo also caps redo retention for an image above 128 MiB")
    }
    app.document.reset(Scene(size: CGSize(width: 200, height: 200))); app.canvas.fit()
    app.insert([small, small]); app.canvas.tool = .eraser; app.canvas.objectEraser = true
    let pastedIDs = app.document.scene.items.map(\.id), pasteUndoCount = app.document.undoStack.count
    gesture([CGPoint(x: 110, y: 110)])
    check(app.document.scene.items.map(\.id) == [pastedIDs[0]], "object eraser removes only the topmost overlapping pasted element")
    app.undo()
    gesture([CGPoint(x: 90, y: 90), CGPoint(x: 130, y: 130)])
    check(app.document.scene.items.isEmpty && app.document.undoStack.count == pasteUndoCount + 1, "drag erases multiple pasted elements as one action")
    app.undo(); check(app.document.scene.items.map(\.id) == pastedIDs, "one undo restores all erased pasted elements")
    let transparentContext = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let transparentBytes = transparentContext.data!.assumingMemoryBound(to: UInt8.self)
    transparentBytes[(11 * 32 + 10) * 4] = 255; transparentBytes[(11 * 32 + 10) * 4 + 3] = 255
    let transparentItem = Item(image: transparentContext.makeImage()!)
    check(!transparentItem.hit(CGPoint(x: 5, y: 5)) && transparentItem.hit(CGPoint(x: 10, y: 11)), "pasted image hit testing ignores transparent pixels")
    app.document.reset(Scene(size: CGSize(width: 200, height: 200), items: [Item(image: small), transparentItem])); app.canvas.fit()
    gesture([CGPoint(x: 5, y: 5)])
    check(app.document.scene.items.map(\.id) == [transparentItem.id], "object erase reaches the visible pasted image behind transparent pixels")
    app.document.reset(); app.canvas.fit(); app.canvas.tool = .text
    let textStart = CGPoint(x: 100, y: 120)
    app.canvas.insertText(at: textStart)
    check(app.canvas.editor?.superview === app.canvas && app.window.firstResponder === app.canvas.editor, "text edits directly on canvas with native keyboard focus")
    app.canvas.editor!.insertText("screeny\nSecond line", replacementRange: NSRange(location: 0, length: 0))
    let textUndo = app.document.undoStack.count
    _ = app.canvas.textView(app.canvas.editor!, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    check(app.canvas.editor == nil && app.canvas.tool == .move && app.toolButtons[0].state == .on, "Return commits inline text and selects Move automatically")
    check(app.document.scene.items.count == 1 && app.document.scene.items[0].bounds.height > app.canvas.textSize && app.document.undoStack.count == textUndo + 1, "multiline text becomes one visible undoable item")
    app.undo(); check(app.document.scene.items.isEmpty, "inline text insertion undoes in one action")
    app.canvas.tool = .text; app.canvas.insertText(at: textStart)
    app.canvas.editor!.insertText("Cancel", replacementRange: NSRange(location: 0, length: 0))
    _ = app.canvas.textView(app.canvas.editor!, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    check(app.document.scene.items.isEmpty && app.canvas.tool == .move, "Escape cancels inline text without adding an object")
    app.canvas.tool = .text; app.canvas.insertText(at: textStart)
    app.canvas.editor!.insertText("Click away", replacementRange: NSRange(location: 0, length: 0))
    let undoMenu = NSMenuItem(title: "Undo", action: #selector(App.undo), keyEquivalent: "z")
    check(app.validateMenuItem(undoMenu), "Undo remains available while editing canvas text")
    app.window.makeFirstResponder(app.canvas)
    check(app.canvas.editor == nil && app.canvas.tool == .move && app.document.scene.items.count == 1, "clicking away commits text and switches to Move")
    app.undo(); check(app.document.scene.items.isEmpty, "click-away text insertion is one undo action")
    app.canvas.tool = .brush; gesture([CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150)])
    check(app.canvas.tool == .move && app.canvas.selected.contains(app.document.scene.items.last!.id), "completing a drawing selects the item and Move tool")
    app.canvas.navigate(zoom: 0.8, rotation: .pi / 6)
    app.canvas.tool = .text; app.canvas.insertText(at: textStart)
    let editorAxis = app.canvas.editor!.convert(CGPoint(x: 20, y: 0), to: app.canvas)
    let expectedAxis = CGPoint(x: textStart.x + 20, y: textStart.y).applying(app.canvas.transform)
    check(hypot(editorAxis.x - expectedAxis.x, editorAxis.y - expectedAxis.y) < 0.01, "inline editor matches canvas zoom and rotation")
    app.canvas.finishText(cancel: true)
    let scale = app.canvas.zoom, rotation = app.canvas.angle, size = app.document.scene.size
    app.canvas.horizontalScroller.doubleValue = 0.75; let horizontalRange = app.canvas.scrollRange.width
    app.canvas.scrollbarChanged(app.canvas.horizontalScroller)
    check(abs(app.canvas.pan.x + horizontalRange * 0.5) < 0.001, "horizontal scrollbar pans the viewport")
    app.canvas.verticalScroller.doubleValue = 0.25; let verticalRange = app.canvas.scrollRange.height
    app.canvas.scrollbarChanged(app.canvas.verticalScroller)
    check(abs(app.canvas.pan.y - verticalRange * 0.5) < 0.001, "vertical scrollbar pans the viewport")
    app.centerImage()
    check(app.canvas.pan == .zero && app.canvas.zoom == scale && app.canvas.angle == rotation && app.document.scene.size == size, "Center preserves zoom, rotation, and document pixels")
    check(abs(app.canvas.horizontalScroller.doubleValue - 0.5) < 0.001 && abs(app.canvas.verticalScroller.doubleValue - 0.5) < 0.001, "scrollbars synchronize with centered navigation")
    app.document.reset(); app.history.clear(); app.canvas.fit()
    print("RESULT: \(checks) checks passed; \(failures) failures in \(String(format: "%.2f", ProcessInfo.processInfo.systemUptime-started)) seconds; fixtures 3840×2160, 5000×4000, and 7000×5000; macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    fflush(stdout)
    return failures == 0 ? 0 : 1
}

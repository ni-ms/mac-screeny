import AppKit
import UniformTypeIdentifiers

final class App: NSResponder, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSPopoverDelegate {
    let document = Document()
    let history = ImageHistory()
    lazy var canvas = Canvas(document)
    var window: NSWindow!
    var info = NSTextField(labelWithString: "")
    var zoomLabel = NSTextField(labelWithString: "")
    var colorWell = ColorWell()
    var hex = NSTextField(string: "#202020")
    var opacity = NSSlider(value: 100, minValue: 0, maxValue: 100, target: nil, action: nil)
    var width = NSSlider(value: 6, minValue: 1, maxValue: 100, target: nil, action: nil)
    var widthLabel = NSTextField(labelWithString: "Width · 6 px")
    var opacityLabel = NSTextField(labelWithString: "Opacity · 100%")
    var eraseMode = NSSegmentedControl(labels: ["Pixel", "Object"], trackingMode: .selectOne, target: nil, action: nil)
    var toolButtons: [NSButton] = []
    var colorGroup = NSStackView()
    var widthGroup = NSStackView()
    var pasteButton: NSButton!
    var cropButton: NSButton!
    var toolLabel = NSTextField(labelWithString: "Brush")
    let popover = NSPopover()
    var historyChecks: [NSButton] = []
    var insertButton: NSButton!
    weak var exportPanel: NSSavePanel?
    var exportURL: URL?
    var closing = false
    let launchStart = ProcessInfo.processInfo.systemUptime

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu(); buildWindow()
        document.changed = { [weak self] in self?.refresh() }
        canvas.navigationChanged = { [weak self] in self?.refreshZoom() }
        canvas.droppedImages = { [weak self] in self?.insert($0) }
        document.reset(); canvas.fit()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--measure-launch") {
            window.displayIfNeeded()
            print(String(format: "window-ready-ms %.2f", (ProcessInfo.processInfo.systemUptime - launchStart) * 1000)); fflush(stdout)
        }
        #if SCREENY_TEST
        if CommandLine.arguments.contains("--self-test") { exit(runTests(app: self)) }
        #endif
    }
    func button(_ title: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let b = ScreenyButton(title: title, target: self, action: action); b.isBordered = false
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: title.isEmpty ? 28 : textWidth + (symbol == nil ? 20 : 42)).isActive = true
        if let symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); b.imagePosition = .imageLeading }
        b.setAccessibilityLabel(title); return b
    }
    func stack(_ views: [NSView], vertical: Bool = false, spacing: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: views); s.orientation = vertical ? .vertical : .horizontal
        s.alignment = vertical ? .leading : .centerY; s.spacing = spacing; return s
    }
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "screeny"; window.minSize = NSSize(width: 740, height: 500); window.center(); window.delegate = self
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.backgroundColor = ScreenyStyle.chrome
        window.tabbingMode = .disallowed; window.isReleasedWhenClosed = false
        let root = NSView(); window.contentView = root
        let brand = NSTextField(labelWithString: "screeny")
        brand.font = NSFont(descriptor: NSFont.systemFont(ofSize: 16, weight: .semibold).fontDescriptor.withDesign(.rounded)!, size: 16)
        info.font = .systemFont(ofSize: 11, weight: .medium); info.textColor = .secondaryLabelColor
        info.lineBreakMode = .byTruncatingMiddle
        let copy = button("Copy", #selector(copyImage), symbol: "square.on.square"); copy.toolTip = "Copy image (⌘C)"
        pasteButton = button("Paste", #selector(pasteImage), symbol: "doc.on.clipboard"); pasteButton.toolTip = "Paste images (⌘V)"
        let recent = button("", #selector(showHistory), symbol: "chevron.down"); recent.setAccessibilityLabel("Recent images"); recent.toolTip = "Recent images"
        let export = button("Export", #selector(exportImage), symbol: "square.and.arrow.up"); (export as? ScreenyButton)?.prominent = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        cropButton = button("Crop", #selector(crop)); cropButton.isHidden = true
        let top = stack([brand, info, spacer, cropButton, copy, stack([pasteButton, recent], spacing: 3), export], spacing: 10)
        let rail = NSStackView(); rail.orientation = .vertical; rail.alignment = .leading; rail.spacing = 12
        toolLabel.font = .systemFont(ofSize: 12, weight: .semibold); rail.addArrangedSubview(toolLabel)
        let symbols = ["cursorarrow", "paintbrush.pointed", "eraser", "arrow.up.right", "rectangle", "circle", "textformat", "crop"]
        for row in 0..<4 {
            var buttons: [NSView] = []
            for i in (row * 2)..<(row * 2 + 2) {
                let tool = Tool.allCases[i], b = button("", #selector(chooseTool(_:)), symbol: symbols[i]); b.tag = i
                b.setButtonType(.pushOnPushOff); b.imagePosition = .imageOnly
                b.widthAnchor.constraint(equalToConstant: 55).isActive = true
                b.setAccessibilityLabel(tool.rawValue); b.toolTip = tool.rawValue + " (⌥⌘\(i + 1))"
                buttons.append(b); toolButtons.append(b)
            }
            let rowView = stack(buttons, spacing: 6); rail.addArrangedSubview(rowView); rail.setCustomSpacing(6, after: rowView)
        }
        let line = NSBox(); line.boxType = .separator; line.widthAnchor.constraint(equalToConstant: 116).isActive = true
        rail.addArrangedSubview(line)
        eraseMode.selectedSegment = 0; eraseMode.target = self; eraseMode.action = #selector(eraseModeChanged)
        eraseMode.controlSize = .small; eraseMode.font = .systemFont(ofSize: 11); eraseMode.setAccessibilityLabel("Eraser mode")
        rail.addArrangedSubview(eraseMode)
        colorWell.color = canvas.color; colorWell.target = self; colorWell.action = #selector(colorChanged)
        colorWell.supportsAlpha = true; colorWell.setAccessibilityLabel("Color picker")
        colorWell.widthAnchor.constraint(equalToConstant: 28).isActive = true
        hex.widthAnchor.constraint(equalToConstant: 82).isActive = true; hex.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hex.controlSize = .small; hex.target = self; hex.action = #selector(hexChanged); hex.setAccessibilityLabel("Hex color, RRGGBB or RRGGBBAA")
        opacity.target = self; opacity.action = #selector(opacityChanged); opacity.isContinuous = true; opacity.setAccessibilityLabel("Opacity")
        width.target = self; width.action = #selector(widthChanged); width.isContinuous = true; width.setAccessibilityLabel("Stroke width")
        for slider in [opacity, width] { slider.controlSize = .small; slider.trackFillColor = ScreenyStyle.accent; slider.widthAnchor.constraint(equalToConstant: 116).isActive = true }
        for label in [opacityLabel, widthLabel] { label.font = .systemFont(ofSize: 11, weight: .medium); label.textColor = .secondaryLabelColor }
        let colorLabel = NSTextField(labelWithString: "Color"); colorLabel.font = .systemFont(ofSize: 11, weight: .medium); colorLabel.textColor = .secondaryLabelColor
        colorGroup = stack([colorLabel, stack([colorWell, hex], spacing: 6), opacityLabel, opacity], vertical: true, spacing: 6)
        widthGroup = stack([widthLabel, width], vertical: true, spacing: 6)
        rail.addArrangedSubview(colorGroup); rail.addArrangedSubview(widthGroup)
        let minus = button("", #selector(zoomOut), symbol: "minus"); minus.setAccessibilityLabel("Zoom out")
        let plus = button("", #selector(zoomIn), symbol: "plus"); plus.setAccessibilityLabel("Zoom in")
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium); zoomLabel.alignment = .center
        zoomLabel.widthAnchor.constraint(equalToConstant: 78).isActive = true; zoomLabel.setAccessibilityLabel("Zoom percentage")
        let center = button("Center", #selector(centerImage), symbol: "scope"); center.toolTip = "Center canvas without changing zoom or rotation (⇧⌘0)"
        let bottom = stack([minus, zoomLabel, plus, button("Fit", #selector(fit)), button("100%", #selector(actualSize)), center], spacing: 5)
        let rule = ScreenyDivider(); rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let railRule = ScreenyDivider(); railRule.widthAnchor.constraint(equalToConstant: 1).isActive = true
        for view in [top, rail, railRule, canvas, bottom, rule] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), top.topAnchor.constraint(equalTo: root.topAnchor), top.heightAnchor.constraint(equalToConstant: 42),
            rail.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), rail.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12), rail.widthAnchor.constraint(equalToConstant: 116),
            railRule.leadingAnchor.constraint(equalTo: rail.trailingAnchor, constant: 12), railRule.topAnchor.constraint(equalTo: top.bottomAnchor), railRule.bottomAnchor.constraint(equalTo: rule.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: railRule.trailingAnchor), canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor), canvas.topAnchor.constraint(equalTo: top.bottomAnchor), canvas.bottomAnchor.constraint(equalTo: rule.topAnchor),
            rule.leadingAnchor.constraint(equalTo: root.leadingAnchor), rule.trailingAnchor.constraint(equalTo: root.trailingAnchor), rule.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -4),
            bottom.centerXAnchor.constraint(equalTo: canvas.centerXAnchor), bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -5), bottom.heightAnchor.constraint(equalToConstant: 28)
        ])
        canvas.toolChanged = { [weak self] in self?.syncToolControls() }
        chooseTool(toolButtons[1]); window.makeFirstResponder(canvas)
    }
    func buildMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title; let menu = NSMenu(title: title); item.submenu = menu; main.addItem(item); return menu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ flags: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = flags; item.target = self; menu.addItem(item)
        }
        let app = menu("screeny"); add(app, "About screeny", #selector(about)); app.addItem(.separator()); add(app, "Hide screeny", #selector(hideApp), "h"); app.addItem(.separator()); add(app, "Quit screeny", #selector(quit), "q")
        let file = menu("File"); add(file, "New Canvas…", #selector(newCanvas), "n"); add(file, "Open Image…", #selector(openImage), "o"); add(file, "Export…", #selector(exportImage), "e", [.command, .shift]); add(file, "Export…", #selector(exportImage), "s"); file.addItem(.separator()); add(file, "Close", #selector(closeWindow), "w")
        let edit = menu("Edit"); add(edit, "Undo", #selector(undo), "z"); add(edit, "Redo", #selector(redo), "z", [.command, .shift]); edit.addItem(.separator())
        // Text fields retain native responder-chain editing shortcuts.
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(copy(_:)), "c"), ("Paste", #selector(paste(_:)), "v"), ("Select All", #selector(selectAll(_:)), "a")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); edit.addItem(item)
        }
        add(edit, "Recent Images…", #selector(historyFromMenu)); add(edit, "Crop Selection", #selector(crop), "k", [.command, .shift])
        let view = menu("View"); add(view, "Zoom In", #selector(zoomIn), "+"); add(view, "Zoom In", #selector(zoomIn), "="); add(view, "Zoom Out", #selector(zoomOut), "-"); add(view, "Fit", #selector(fit), "0"); add(view, "Center", #selector(centerImage), "0", [.command, .shift]); add(view, "Actual Size", #selector(actualSize), "1"); add(view, "Rotate Left", #selector(rotateLeft), "[", [.command, .option]); add(view, "Rotate Right", #selector(rotateRight), "]", [.command, .option]); add(view, "Reset Rotation", #selector(resetRotation))
        let tools = menu("Tools")
        for (i, tool) in Tool.allCases.enumerated() { let item = NSMenuItem(title: tool.rawValue, action: #selector(toolMenu(_:)), keyEquivalent: "\(i + 1)"); item.keyEquivalentModifierMask = [.command, .option]; item.target = self; item.tag = i; tools.addItem(item) }
        add(tools, "Show Colors", #selector(showColors), "c", [.command, .shift])
        let windows = menu("Window"); add(windows, "Minimize", #selector(minimize), "m"); NSApp.windowsMenu = windows
        NSApp.mainMenu = main
        // The app delegate participates in the responder chain.
        NSApp.nextResponder = self
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "screeny", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"]) }
    @objc func hideApp() { NSApp.hide(nil) }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func closeWindow() { window.performClose(nil) }
    @objc func minimize() { window.miniaturize(nil) }
    @objc func copy(_ sender: Any?) { copyImage() }
    @objc func paste(_ sender: Any?) { pasteImage() }
    override func selectAll(_ sender: Any?) { canvas.selected = Set(document.scene.items.map(\.id)); canvas.needsDisplay = true }
    @objc func undo() { if let editor = canvas.editor { editor.undoManager?.undo(); return }; canvas.cancelEdit(); document.undo(); if canvas.isFit { canvas.fit() } }
    @objc func redo() { if let editor = canvas.editor { editor.undoManager?.redo(); return }; canvas.cancelEdit(); document.redo(); if canvas.isFit { canvas.fit() } }
    @objc func chooseTool(_ sender: NSButton) {
        canvas.tool = Tool.allCases[sender.tag]
        syncToolControls(); window?.makeFirstResponder(canvas)
    }
    func syncToolControls() {
        toolLabel.stringValue = canvas.tool.rawValue
        for b in toolButtons { b.state = Tool.allCases[b.tag] == canvas.tool ? .on : .off; b.needsDisplay = true }
        eraseMode.isHidden = canvas.tool != .eraser
        colorGroup.isHidden = [.eraser, .move, .crop].contains(canvas.tool)
        widthGroup.isHidden = [.move, .crop].contains(canvas.tool) || (canvas.tool == .eraser && canvas.objectEraser)
        cropButton.isHidden = canvas.tool != .crop
        widthLabel.stringValue = canvas.tool == .text ? "Size · \(Int(canvas.textSize)) px" : "Width · \(Int(canvas.strokeWidth)) px"
        width.doubleValue = Double(canvas.tool == .text ? canvas.textSize : canvas.strokeWidth)
    }
    @objc func toolMenu(_ sender: NSMenuItem) { chooseTool(toolButtons[sender.tag]) }
    @objc func eraseModeChanged() { canvas.objectEraser = eraseMode.selectedSegment == 1; widthGroup.isHidden = canvas.objectEraser }
    @objc func widthChanged() { if canvas.tool == .text { canvas.textSize = CGFloat(width.doubleValue) } else { canvas.strokeWidth = CGFloat(width.doubleValue) }; widthLabel.stringValue = "\(canvas.tool == .text ? "Size" : "Width") · \(Int(width.doubleValue)) px"; canvas.updateTextStyle() }
    @objc func showColors() { colorWell.openPicker() }
    @objc func colorChanged() {
        guard let c = colorWell.color.usingColorSpace(.sRGB) else { return }; canvas.color = c
        canvas.updateTextStyle()
        opacity.doubleValue = c.alphaComponent * 100; opacityLabel.stringValue = "Opacity · \(Int(opacity.doubleValue))%"
        hex.stringValue = String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
    @objc func hexChanged() {
        let s = hex.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard (s.count == 6 || s.count == 8), let value = UInt32(s, radix: 16) else { NSSound.beep(); colorChanged(); return }
        let rgb = s.count == 8 ? value >> 8 : value
        let alpha = s.count == 8 ? CGFloat(value & 255) / 255 : canvas.color.alphaComponent
        colorWell.color = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: alpha); colorChanged()
    }
    @objc func opacityChanged() { colorWell.color = canvas.color.withAlphaComponent(CGFloat(opacity.doubleValue / 100)); colorChanged() }
    func refresh() {
        let s = document.scene.size; info.stringValue = "\(exportURL?.lastPathComponent ?? "Untitled") · \(Int(s.width)) × \(Int(s.height)) px"
        window?.isDocumentEdited = document.dirty; canvas.needsDisplay = true; canvas.syncNavigation()
    }
    func refreshZoom() { zoomLabel.stringValue = String(format: "%@%.0f%%", canvas.isFit ? "Fit · " : "", canvas.zoom * 100) }
    @objc func zoomIn() { canvas.navigate(zoom: canvas.zoom * 1.25) }
    @objc func zoomOut() { canvas.navigate(zoom: canvas.zoom / 1.25) }
    @objc func fit() { canvas.cancelEdit(); canvas.fit() }
    @objc func centerImage() { canvas.center() }
    @objc func actualSize() { canvas.navigate(zoom: 1) }
    @objc func rotateLeft() { canvas.navigate(rotation: canvas.angle - .pi / 12) }
    @objc func rotateRight() { canvas.navigate(rotation: canvas.angle + .pi / 12) }
    @objc func resetRotation() { canvas.navigate(rotation: 0) }
    @objc func crop() { canvas.cropSelection() }
    func insert(_ images: [CGImage]) {
        canvas.finishText(); canvas.cancelEdit(); let wasEmpty = document.scene.isEmpty
        document.insert(images); history.add(images)
        canvas.selected = Set(document.scene.items.suffix(images.count).map(\.id))
        chooseTool(toolButtons[0]); if wasEmpty { canvas.fit() }
        canvas.needsDisplay = true
    }
    @objc func copyImage() {
        canvas.finishText(); canvas.cancelEdit()
        guard let image = document.scene.image(), let data = imageData(image) else { error("Unable to copy image."); return }
        let board = NSPasteboard.general; board.clearContents()
        let item = NSPasteboardItem(); item.setData(data, forType: .png)
        if board.writeObjects([item]) { history.add([image]) } else { error("Unable to write to the clipboard.") }
    }
    @objc func pasteImage() {
        let images = clipboardImages(.general)
        if images.isEmpty { error("The clipboard contains no readable images.") } else { insert(images) }
    }
    @objc func historyFromMenu() { showHistory(pasteButton) }
    @objc func showHistory(_ sender: NSButton) {
        if popover.isShown { popover.close(); return }
        rebuildHistory(); popover.behavior = .transient; popover.delegate = self
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    func rebuildHistory() {
        let controller = NSViewController(); let content = NSView(); controller.view = content
        let title = NSTextField(labelWithString: "Recent images")
        let clear = button("Clear", #selector(clearHistory)); clear.isEnabled = !history.entries.isEmpty
        let gap = NSView(); gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let rows = stack([stack([title, gap, clear])], vertical: true, spacing: 10)
        historyChecks.removeAll()
        if history.entries.isEmpty {
            let label = NSTextField(wrappingLabelWithString: "No recent images\nImages copied or pasted in screeny appear here.")
            label.textColor = .secondaryLabelColor; label.font = .systemFont(ofSize: 12); rows.addArrangedSubview(label)
        } else {
            for (i, entry) in history.entries.enumerated().reversed() {
                let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(historySelectionChanged)); check.tag = i
                check.setAccessibilityLabel("Select image \(i + 1), \(entry.image.width) by \(entry.image.height) pixels"); historyChecks.append(check)
                let thumb = NSImageView(); thumb.image = NSImage(cgImage: entry.image, size: NSSize(width: entry.image.width, height: entry.image.height)); thumb.imageScaling = .scaleProportionallyUpOrDown
                thumb.widthAnchor.constraint(equalToConstant: 64).isActive = true; thumb.heightAnchor.constraint(equalToConstant: 46).isActive = true
                rows.addArrangedSubview(stack([check, thumb, NSTextField(labelWithString: "\(entry.image.width) × \(entry.image.height) px")]))
            }
        }
        insertButton = button("Insert selected", #selector(insertHistory)); insertButton.isEnabled = false; rows.addArrangedSubview(insertButton)
        rows.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(rows)
        NSLayoutConstraint.activate([rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14), rows.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14), rows.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), rows.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12), rows.widthAnchor.constraint(equalToConstant: 290)])
        popover.contentViewController = controller; popover.contentSize = rows.fittingSize + NSSize(width: 28, height: 24)
    }
    @objc func historySelectionChanged() { insertButton.isEnabled = historyChecks.contains { $0.state == .on } }
    @objc func insertHistory() {
        let images = historyChecks.filter { $0.state == .on }.sorted { $0.tag < $1.tag }.map { history.entries[$0.tag].image }
        popover.close(); insert(images)
    }
    @objc func clearHistory() { history.clear(); rebuildHistory() }
    func error(_ message: String) { let a = NSAlert(); a.messageText = message; a.runModal() }
    func allowDiscard() -> Bool {
        canvas.finishText(); canvas.cancelEdit(); guard document.dirty else { return true }
        let a = NSAlert(); a.messageText = "Export changes before closing?"; a.informativeText = "Unexported changes will be lost. PNG and JPEG exports do not retain editable objects."
        a.addButton(withTitle: "Export…"); a.addButton(withTitle: "Cancel"); a.addButton(withTitle: "Discard")
        switch a.runModal() { case .alertFirstButtonReturn: return export(); case .alertThirdButtonReturn: return true; default: return false }
    }
    @objc func newCanvas() {
        guard allowDiscard() else { return }
        let a = NSAlert(); a.messageText = "New Canvas"
        let w = NSTextField(string: "1600"), h = NSTextField(string: "1000")
        w.setAccessibilityLabel("Width in pixels"); h.setAccessibilityLabel("Height in pixels")
        let fields = stack([stack([NSTextField(labelWithString: "Width (px)"), w]), stack([NSTextField(labelWithString: "Height (px)"), h])], vertical: true)
        fields.frame = NSRect(x: 0, y: 0, width: 280, height: 60); a.accessoryView = fields
        a.addButton(withTitle: "Create"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard w.integerValue > 0, h.integerValue > 0, w.integerValue <= 32768, h.integerValue <= 32768, w.integerValue * h.integerValue <= 100_000_000 else { error("Enter dimensions between 1 and 32768 pixels, up to 100 million pixels total."); return }
        exportURL = nil; document.reset(Scene(size: CGSize(width: w.integerValue, height: h.integerValue))); canvas.selected.removeAll(); canvas.selection = nil; canvas.fit()
    }
    @objc func openImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url), let image = decodeImage(data) else { return }
        guard allowDiscard() else { return }
        exportURL = nil; document.reset(Scene(size: CGSize(width: image.width, height: image.height), items: [Item(image: image)])); canvas.selected.removeAll(); canvas.selection = nil; canvas.fit()
    }
    @objc func exportImage() { _ = export() }
    @discardableResult func export() -> Bool {
        canvas.finishText(); canvas.cancelEdit()
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = exportURL?.lastPathComponent ?? "Untitled.png"; panel.canSelectHiddenExtension = true
        let format = NSPopUpButton(); format.addItems(withTitles: ["PNG", "JPEG"]); format.target = self; format.action = #selector(exportFormatChanged(_:)); exportPanel = panel
        panel.accessoryView = stack([NSTextField(labelWithString: "Format"), format]); panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let jpeg = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) || format.indexOfSelectedItem == 1
        guard let image = document.scene.image(jpeg: jpeg), let data = imageData(image, jpeg: jpeg) else { error("Unable to render this image."); return false }
        do { try data.write(to: url, options: .atomic); exportURL = url; document.savedRevision = document.scene.revision; refresh(); return true }
        catch { self.error(error.localizedDescription); return false }
    }
    @objc func exportFormatChanged(_ sender: NSPopUpButton) {
        guard let panel = exportPanel else { return }
        let type: UTType = sender.indexOfSelectedItem == 0 ? .png : .jpeg
        panel.allowedContentTypes = [type]; panel.nameFieldStringValue = (panel.nameFieldStringValue as NSString).deletingPathExtension + "." + (type.preferredFilenameExtension ?? "png")
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { closing = allowDiscard(); return closing }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { (closing || allowDiscard()) ? .terminateNow : .terminateCancel }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undo) { return canvas.editor?.undoManager?.canUndo ?? !document.undoStack.isEmpty }
        if item.action == #selector(redo) { return canvas.editor?.undoManager?.canRedo ?? !document.redoStack.isEmpty }
        if item.action == #selector(crop) { return canvas.selection != nil }
        return true
    }
}

extension NSSize {
    static func + (lhs: NSSize, rhs: NSSize) -> NSSize { NSSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height) }
}

final class ColorWell: NSColorWell {
    func openPicker() { activate(true); NSColorPanel.shared.showsAlpha = true; NSColorPanel.shared.orderFront(nil) }
    override func mouseDown(with event: NSEvent) { openPicker() }
}

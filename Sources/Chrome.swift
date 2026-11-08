import AppKit

enum ScreenyStyle {
    static let accent = NSColor(srgbRed: 0.47, green: 0.37, blue: 0.88, alpha: 1)
    static let chrome = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.14, green: 0.14, blue: 0.17, alpha: 1) : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1) }
    static let workspace = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1) : NSColor(srgbRed: 0.89, green: 0.90, blue: 0.92, alpha: 1) }
}

// Native button behavior and accessibility, with one quiet visual treatment.
final class ScreenyButton: NSButton {
    var prominent = false
    override func draw(_ dirtyRect: NSRect) {
        let active = state == .on || prominent
        let fill = active ? ScreenyStyle.accent.withAlphaComponent(isHighlighted ? 0.8 : 1) : NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.12 : 0.045)
        fill.setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).fill()
        let color = (active ? NSColor.white : NSColor.labelColor).withAlphaComponent(isEnabled ? 1 : 0.35)
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attributes)
        let iconWidth: CGFloat = image == nil ? 0 : 16
        let gap: CGFloat = image == nil || title.isEmpty ? 0 : 6
        let total = iconWidth + gap + (imagePosition == .imageOnly ? 0 : size.width)
        let x = (bounds.width - total) / 2
        if let image {
            let tinted = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium).applying(NSImage.SymbolConfiguration(paletteColors: [color]))) ?? image
            let scale = min(16 / tinted.size.width, 16 / tinted.size.height)
            let size = CGSize(width: tinted.size.width * scale, height: tinted.size.height * scale)
            tinted.draw(in: NSRect(x: x + (16 - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
        }
        if imagePosition != .imageOnly { (title as NSString).draw(at: NSPoint(x: x + iconWidth + gap, y: (bounds.height - size.height) / 2), withAttributes: attributes) }
        if window?.firstResponder === self { NSFocusRingPlacement.only.set(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill() }
    }
}

final class ScreenyDivider: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor.separatorColor.setFill(); bounds.fill() }
}

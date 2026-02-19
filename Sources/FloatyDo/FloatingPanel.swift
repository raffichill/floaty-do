import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        // Unified dark background — title bar blends with content
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        hasShadow = true
    }
}

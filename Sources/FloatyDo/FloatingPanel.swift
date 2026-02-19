import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        // Rounded corners
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }
}

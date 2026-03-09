import AppKit

public final class FloatingPanel: NSPanel {
    private let customFieldEditor = CaretEndFieldEditor()
    private var observers: [NSObjectProtocol] = []

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        // Taller title bar via empty toolbar — matches Things-style traffic light padding
        let toolbar = NSToolbar(identifier: "main")
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        toolbarStyle = .unifiedCompact

        // Unified dark background — title bar blends with content
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        hasShadow = true

        // Configure custom field editor
        customFieldEditor.isFieldEditor = true
        customFieldEditor.isRichText = false

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
                self?.applyWindowChromeLayout()
            }
        )
        observers.append(
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: self, queue: .main) { [weak self] _ in
                self?.applyWindowChromeLayout()
            }
        )

        DispatchQueue.main.async { [weak self] in
            self?.applyWindowChromeLayout()
        }
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
    }

    // Allow key events even when the app isn't active (menu bar utility)
    public override var canBecomeKey: Bool { true }

    public override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if object is NSTextField {
            return customFieldEditor
        }
        return super.fieldEditor(createFlag, for: object)
    }

    private func applyWindowChromeLayout() {
        guard let closeButton = standardWindowButton(.closeButton),
              let miniButton = standardWindowButton(.miniaturizeButton),
              let zoomButton = standardWindowButton(.zoomButton),
              let buttonSuperview = closeButton.superview else {
            return
        }

        let buttons = [closeButton, miniButton, zoomButton]
        let targetCenterX = CGFloat(LayoutMetrics.rowHorizontalInset + (LayoutMetrics.circleHitSize / 2.0))
        let leadingX = targetCenterX - (closeButton.frame.width / 2.0)
        let topInset = CGFloat(LayoutMetrics.trafficLightTopInset)
        let spacing = CGFloat(LayoutMetrics.trafficLightSpacing)
        let buttonY = buttonSuperview.bounds.height - topInset - closeButton.frame.height

        var currentX = leadingX
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: currentX, y: buttonY))
            currentX += button.frame.width + spacing
        }
    }
}

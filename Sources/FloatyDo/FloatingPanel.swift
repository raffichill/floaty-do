import AppKit

public final class FloatingPanel: NSWindow {
    private let customFieldEditor = CaretEndFieldEditor()
    private let chromeToolbar = NSToolbar(identifier: "main")
    private var observers: [NSObjectProtocol] = []

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.managed, .fullScreenPrimary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        isMovableByWindowBackground = true
        isReleasedWhenClosed = false

        // Taller title bar via empty toolbar — matches Things-style traffic light padding
        chromeToolbar.showsBaselineSeparator = false
        self.toolbar = chromeToolbar
        toolbarStyle = .unifiedCompact

        // Unified dark background — title bar blends with content
        appearance = NSAppearance(named: .darkAqua)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Configure custom field editor
        customFieldEditor.isFieldEditor = true
        customFieldEditor.isRichText = false
        customFieldEditor.allowsUndo = true

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
    public override var canBecomeMain: Bool { true }

    public override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        if object is NSTextField {
            return customFieldEditor
        }
        return super.fieldEditor(createFlag, for: object)
    }

    public func applyTheme(preferences: AppPreferences) {
        appearance = NSAppearance(named: preferences.usesLightText ? .darkAqua : .aqua)
        backgroundColor = .clear
        alphaValue = 1.0
        hasShadow = true
        invalidateShadow()
        contentView?.needsDisplay = true
    }

    public func setFullScreenChromeHidden(_ hidden: Bool) {
        // Detaching the toolbar in native fullscreen causes AppKit to fall back
        // to an opaque titlebar region that sits on top of our custom header.
        // Keep the transparent toolbar attached and let fullscreen presentation
        // options auto-hide the system chrome instead.
        toolbar = chromeToolbar
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
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

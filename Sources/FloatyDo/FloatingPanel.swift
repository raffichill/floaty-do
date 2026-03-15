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

final class PanelSurfaceView: NSView {
    private enum SurfaceMode: Equatable {
        case solid
        case translucent
        case glass
    }

    private let contentContainer = NSView()
    private let solidSurface = NSView()
    private let translucentSurface = NSVisualEffectView()
    private let translucentTintOverlay = NSView()
    private var activeSurface: NSView?
    private var glassSurfaceStorage: NSView?

    var contentView: NSView {
        contentContainer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = false

        solidSurface.translatesAutoresizingMaskIntoConstraints = false
        solidSurface.wantsLayer = true

        translucentSurface.translatesAutoresizingMaskIntoConstraints = false
        translucentSurface.state = .active
        translucentSurface.blendingMode = .behindWindow
        translucentSurface.material = .hudWindow
        translucentSurface.isEmphasized = true
        translucentSurface.wantsLayer = true
        translucentSurface.layer?.backgroundColor = NSColor.clear.cgColor

        translucentTintOverlay.translatesAutoresizingMaskIntoConstraints = false
        translucentTintOverlay.wantsLayer = true
        translucentSurface.addSubview(translucentTintOverlay)
        NSLayoutConstraint.activate([
            translucentTintOverlay.leadingAnchor.constraint(equalTo: translucentSurface.leadingAnchor),
            translucentTintOverlay.trailingAnchor.constraint(equalTo: translucentSurface.trailingAnchor),
            translucentTintOverlay.topAnchor.constraint(equalTo: translucentSurface.topAnchor),
            translucentTintOverlay.bottomAnchor.constraint(equalTo: translucentSurface.bottomAnchor),
        ])

        addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        installSurface(solidSurface)
        apply(preferences: .default)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(preferences: AppPreferences) {
        switch resolvedSurfaceMode(for: preferences) {
        case .solid:
            installSurface(solidSurface)
            solidSurface.layer?.backgroundColor = preferences.panelBackgroundColor.cgColor
        case .translucent:
            installSurface(translucentSurface)
            translucentSurface.material = preferences.usesLightText ? .hudWindow : .underWindowBackground
            translucentTintOverlay.layer?.backgroundColor = preferences.translucentSurfaceTintColor.cgColor
        case .glass:
            if #available(macOS 26.0, *) {
                let glassSurface = resolvedGlassSurface()
                glassSurface.tintColor = preferences.glassTintColor
                installSurface(glassSurface)
            } else {
                installSurface(translucentSurface)
                translucentSurface.material = preferences.usesLightText ? .hudWindow : .underWindowBackground
                translucentTintOverlay.layer?.backgroundColor = preferences.fallbackGlassTintColor.cgColor
            }
        }
    }

    private func resolvedSurfaceMode(for preferences: AppPreferences) -> SurfaceMode {
        if preferences.glassEnabled {
            if #available(macOS 26.0, *) {
                return .glass
            }
            return .translucent
        }

        return preferences.usesTranslucentSurface ? .translucent : .solid
    }

    private func installSurface(_ surface: NSView) {
        if activeSurface !== surface {
            activeSurface?.removeFromSuperview()
            addSubview(surface, positioned: .below, relativeTo: contentContainer)
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: trailingAnchor),
                surface.topAnchor.constraint(equalTo: topAnchor),
                surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            activeSurface = surface
        }
    }

    @available(macOS 26.0, *)
    private func resolvedGlassSurface() -> NSGlassEffectView {
        if let glassSurface = glassSurfaceStorage as? NSGlassEffectView {
            return glassSurface
        }

        let glassSurface = NSGlassEffectView()
        glassSurface.translatesAutoresizingMaskIntoConstraints = false
        glassSurface.style = .regular
        glassSurface.cornerRadius = 0
        glassSurfaceStorage = glassSurface
        return glassSurface
    }
}

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
        hasShadow = false

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
        hasShadow = false
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
    }

    private let contentContainer = NSView()
    private let solidSurface = NSView()
    private let translucentSurface = NSVisualEffectView()
    private let translucentTintOverlay = NSView()
    private var activeSurface: NSView?
    private var modernTranslucentSurface: NSView?

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
        translucentSurface.material = .underWindowBackground
        translucentSurface.isEmphasized = false

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
        let surfaceMode = resolvedSurfaceMode(for: preferences)

        switch surfaceMode {
        case .solid:
            attachContentContainerToRoot()
            installSurface(solidSurface)
            solidSurface.layer?.backgroundColor = preferences.panelBackgroundColor.cgColor
        case .translucent:
            if #available(macOS 26.0, *) {
                let translucentHost = resolvedModernTranslucentSurface()
                configureModernTranslucentSurface(
                    translucentHost,
                    style: .regular,
                    tintColor: preferences.translucentSurfaceTintColor
                )
                installSurface(translucentHost)
            } else {
                attachContentContainerToRoot()
                translucentSurface.alphaValue = CGFloat(preferences.translucentEffectAlpha)
                translucentSurface.material = .underWindowBackground
                translucentTintOverlay.layer?.backgroundColor = preferences.translucentSurfaceTintColor.cgColor
                installSurface(translucentSurface)
            }
        }
    }

    private func resolvedSurfaceMode(for preferences: AppPreferences) -> SurfaceMode {
        return preferences.usesTranslucentSurface ? .translucent : .solid
    }

    private func installSurface(_ surface: NSView) {
        if activeSurface !== surface {
            if let currentSurface = activeSurface, currentSurface.superview === self {
                currentSurface.removeFromSuperview()
            }
            let relativeView = contentContainer.superview === self ? contentContainer : nil
            addSubview(surface, positioned: .below, relativeTo: relativeView)
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: trailingAnchor),
                surface.topAnchor.constraint(equalTo: topAnchor),
                surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            activeSurface = surface
        }
    }

    private func attachContentContainerToRoot() {
        guard contentContainer.superview !== self else { return }

        if #available(macOS 26.0, *),
           let translucentHost = modernTranslucentSurface as? NSGlassEffectView,
           translucentHost.contentView === contentContainer {
            translucentHost.contentView = nil
        }

        contentContainer.removeFromSuperview()
        addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(macOS 26.0, *)
    private func resolvedModernTranslucentSurface() -> NSGlassEffectView {
        if let translucentHost = modernTranslucentSurface as? NSGlassEffectView {
            return translucentHost
        }

        let translucentHost = NSGlassEffectView()
        translucentHost.translatesAutoresizingMaskIntoConstraints = false
        translucentHost.style = .clear
        translucentHost.cornerRadius = 0
        modernTranslucentSurface = translucentHost
        return translucentHost
    }

    @available(macOS 26.0, *)
    private func configureModernTranslucentSurface(
        _ translucentHost: NSGlassEffectView,
        style: NSGlassEffectView.Style,
        tintColor: NSColor
    ) {
        if translucentHost.contentView !== contentContainer {
            contentContainer.removeFromSuperview()
            translucentHost.contentView = contentContainer
        }

        translucentHost.style = style
        translucentHost.tintColor = tintColor
    }
}

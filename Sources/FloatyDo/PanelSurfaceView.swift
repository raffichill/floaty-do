import AppKit

final class PanelSurfaceView: NSView {
    private enum SurfaceMode: Equatable {
        case solid
        case compositedTranslucent
        case liveTranslucent
    }

    private let contentContainer = NSView()
    private let solidSurface = NSView()
    private let compositedTranslucentSurface = NSView()
    private let translucentSurface = NSVisualEffectView()
    private let translucentTintOverlay = NSView()
    private var activeSurface: NSView?
    private var activeSurfaceMode: SurfaceMode?
    private var modernTranslucentSurface: NSView?
    private var appliedPreferences: AppPreferences = .default
    private weak var observedWindow: NSWindow?
    private var windowObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []

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

        compositedTranslucentSurface.translatesAutoresizingMaskIntoConstraints = false
        compositedTranslucentSurface.wantsLayer = true

        translucentSurface.translatesAutoresizingMaskIntoConstraints = false
        translucentSurface.state = .followsWindowActiveState
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

    deinit {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        appObservers.forEach(center.removeObserver)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installBackdropRefreshObserversIfNeeded()
        refreshTranslucentBackdrop()
    }

    func apply(preferences: AppPreferences) {
        appliedPreferences = preferences
        let surfaceMode = resolvedSurfaceMode(for: preferences)
        switch surfaceMode {
        case .solid:
            attachContentContainerToRoot()
            installSurface(solidSurface)
            solidSurface.layer?.backgroundColor = preferences.panelBackgroundColor.cgColor
            solidSurface.layer?.borderWidth = 0
            solidSurface.layer?.borderColor = nil
        case .compositedTranslucent:
            attachContentContainerToRoot()
            compositedTranslucentSurface.layer?.backgroundColor = preferences.compositedTranslucentSurfaceFillColor.cgColor
            compositedTranslucentSurface.layer?.borderWidth = 1
            compositedTranslucentSurface.layer?.borderColor = preferences.compositedTranslucentSurfaceStrokeColor.cgColor
            installSurface(compositedTranslucentSurface)
        case .liveTranslucent:
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
                translucentSurface.state = .followsWindowActiveState
                translucentSurface.alphaValue = CGFloat(preferences.translucentEffectAlpha)
                translucentSurface.material = .underWindowBackground
                translucentTintOverlay.layer?.backgroundColor = preferences.translucentSurfaceTintColor.cgColor
                installSurface(translucentSurface)
            }
        }
        activeSurfaceMode = surfaceMode
        refreshTranslucentBackdrop()
    }

    private func resolvedSurfaceMode(for preferences: AppPreferences) -> SurfaceMode {
        guard preferences.usesTranslucentSurface else { return .solid }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return .solid
        }
        if prefersCompositedTranslucentSurface {
            return .compositedTranslucent
        }
        return .liveTranslucent
    }

    // macOS 26 can retain stale behind-window samples for floating translucent
    // panels on the physical display, so prefer regular alpha compositing there.
    private var prefersCompositedTranslucentSurface: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
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

    private func installBackdropRefreshObserversIfNeeded() {
        if observedWindow !== window {
            let center = NotificationCenter.default
            windowObservers.forEach(center.removeObserver)
            windowObservers.removeAll()
            observedWindow = window

            if let window {
                let notificationNames: [NSNotification.Name] = [
                    NSWindow.didBecomeKeyNotification,
                    NSWindow.didResignKeyNotification,
                    NSWindow.didExposeNotification,
                    NSWindow.didMoveNotification,
                    NSWindow.didResizeNotification,
                    NSWindow.didChangeOcclusionStateNotification,
                ]

                windowObservers = notificationNames.map { name in
                    center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.refreshTranslucentBackdrop()
                    }
                }
            }
        }

        guard appObservers.isEmpty else { return }

        let center = NotificationCenter.default
        appObservers = [
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                self?.refreshTranslucentBackdrop()
            },
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                self?.refreshTranslucentBackdrop()
            },
        ]

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveApplicationChange),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func handleActiveApplicationChange(_ notification: Notification) {
        refreshTranslucentBackdrop()
    }

    func refreshTranslucentBackdrop() {
        let surfaceMode = resolvedSurfaceMode(for: appliedPreferences)
        guard surfaceMode == activeSurfaceMode else {
            apply(preferences: appliedPreferences)
            return
        }

        switch surfaceMode {
        case .solid:
            return
        case .compositedTranslucent:
            compositedTranslucentSurface.layer?.backgroundColor =
                appliedPreferences.compositedTranslucentSurfaceFillColor.cgColor
            compositedTranslucentSurface.layer?.borderColor =
                appliedPreferences.compositedTranslucentSurfaceStrokeColor.cgColor
            window?.invalidateShadow()
            return
        case .liveTranslucent:
            break
        }

        if #available(macOS 26.0, *),
           let translucentHost = modernTranslucentSurface {
            translucentHost.needsDisplay = true
            translucentHost.displayIfNeeded()
            window?.invalidateShadow()
            return
        }

        let previousState = translucentSurface.state
        translucentSurface.state = .inactive
        translucentSurface.state = previousState
        translucentSurface.needsDisplay = true
        translucentTintOverlay.needsDisplay = true
        translucentSurface.displayIfNeeded()
        window?.invalidateShadow()
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

final class PanelSurfaceHostingViewController<ContentViewController: NSViewController>: NSViewController {
    private var preferences: AppPreferences
    private let hostedViewController: ContentViewController
    private let panelSurface: PanelSurfaceView

    init(preferences: AppPreferences, contentViewController: ContentViewController, frame: NSRect) {
        self.preferences = preferences
        self.hostedViewController = contentViewController
        self.panelSurface = PanelSurfaceView(frame: frame)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        panelSurface.apply(preferences: preferences)
        let container = panelSurface.contentView
        let hostedView = hostedViewController.view
        addChild(hostedViewController)
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: container.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = panelSurface
    }

    func apply(preferences: AppPreferences) {
        self.preferences = preferences
        guard isViewLoaded else { return }
        panelSurface.apply(preferences: preferences)
    }
}

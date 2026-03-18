import AppKit

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
        switch resolvedSurfaceMode(for: preferences) {
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
        preferences.usesTranslucentSurface ? .translucent : .solid
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

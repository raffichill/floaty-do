import AppKit

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum ChromeMetrics {
        static let trafficLightInset: CGFloat = 18
        static let trafficLightSpacing: CGFloat = 6
    }

    var onPreferencesChange: ((AppPreferences) -> Void)? {
        didSet {
            installPreferencesChangeHandler()
        }
    }

    var onWindowVisibilityChange: ((Bool) -> Void)?

    private let settingsViewController: SettingsViewController
    private let surfaceViewController: PanelSurfaceHostingViewController<SettingsViewController>

    init(preferences: AppPreferences) {
        self.settingsViewController = SettingsViewController(preferences: preferences)
        self.surfaceViewController = PanelSurfaceHostingViewController(
            preferences: preferences,
            contentViewController: settingsViewController,
            frame: NSRect(x: 0, y: 0, width: 880, height: 660)
        )

        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.center()
        window.minSize = NSSize(width: 820, height: 620)
        window.contentViewController = surfaceViewController

        let toolbar = NSToolbar(identifier: "settings")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        super.init(window: window)

        shouldCascadeWindows = false
        self.window?.delegate = self
        if let window = self.window {
            applyWindowTheme(preferences, to: window)
        }
        installPreferencesChangeHandler()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(attachedTo parentWindow: NSWindow?) {
        if let window, !window.isVisible {
            let visibleFrame = parentWindow?.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? window.screen?.visibleFrame
                ?? window.frame
            let origin = NSPoint(
                x: visibleFrame.midX - (window.frame.width / 2.0),
                y: visibleFrame.midY - (window.frame.height / 2.0)
            )
            window.setFrameOrigin(origin)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        applyWindowChromeLayout()
        DispatchQueue.main.async { [weak self] in
            self?.applyWindowChromeLayout()
        }
        NSApp.activate(ignoringOtherApps: true)
        onWindowVisibilityChange?(true)
    }

    func updatePreferences(_ preferences: AppPreferences) {
        settingsViewController.updatePreferences(preferences)
        applyDynamicTheme(preferences)
    }

    func windowWillClose(_ notification: Notification) {
        onWindowVisibilityChange?(false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyWindowChromeLayout()
        onWindowVisibilityChange?(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        onWindowVisibilityChange?(window?.isVisible == true)
    }

    func windowDidResize(_ notification: Notification) {
        applyWindowChromeLayout()
    }

    private func applyWindowChromeLayout() {
        guard let window,
              let closeButton = window.standardWindowButton(.closeButton),
              let miniButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let buttonSuperview = closeButton.superview else {
            return
        }

        let buttons = [closeButton, miniButton, zoomButton]
        let leadingInset = ChromeMetrics.trafficLightInset
        let topInset = ChromeMetrics.trafficLightInset
        let spacing = ChromeMetrics.trafficLightSpacing
        let buttonY = buttonSuperview.bounds.height - topInset - closeButton.frame.height

        var currentX = leadingInset
        for button in buttons {
            button.setFrameOrigin(NSPoint(x: currentX, y: buttonY))
            currentX += button.frame.width + spacing
        }
    }

    private func applyWindowTheme(_ preferences: AppPreferences, to window: NSWindow) {
        window.appearance = NSAppearance(named: preferences.usesLightText ? .darkAqua : .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
    }

    private func applyDynamicTheme(_ preferences: AppPreferences) {
        surfaceViewController.apply(preferences: preferences)
        if let window {
            applyWindowTheme(preferences, to: window)
        }
    }

    private func installPreferencesChangeHandler() {
        settingsViewController.onPreferencesChange = { [weak self] preferences in
            guard let self else { return }
            self.applyDynamicTheme(preferences)
            self.onPreferencesChange?(preferences)
        }
    }
}

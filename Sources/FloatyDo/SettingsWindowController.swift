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

    private enum WindowMetrics {
        static let width: CGFloat = SettingsViewController.preferredWindowWidth
        static let initialHeight: CGFloat = 560
        static let minimumHeight: CGFloat = 320
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
            frame: NSRect(x: 0, y: 0, width: WindowMetrics.width, height: WindowMetrics.initialHeight)
        )

        let window = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: WindowMetrics.width, height: WindowMetrics.initialHeight),
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
        window.minSize = NSSize(width: WindowMetrics.width, height: WindowMetrics.minimumHeight)
        window.maxSize = NSSize(width: WindowMetrics.width, height: CGFloat.greatestFiniteMagnitude)
        window.contentViewController = surfaceViewController

        let toolbar = NSToolbar(identifier: "settings")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        super.init(window: window)

        shouldCascadeWindows = false
        self.window?.delegate = self
        if let window = self.window {
            applyWindowTheme(preferences, to: window)
        }
        settingsViewController.onPreferredWindowHeightChange = { [weak self] height, animated in
            self?.resizeWindow(toHeight: height, animated: animated)
        }
        installPreferencesChangeHandler()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(attachedTo parentWindow: NSWindow?) {
        resizeWindowToPreferredHeight(animated: false)
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
            self?.resizeWindowToPreferredHeight(animated: false)
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
        window.hasShadow = true
    }

    private func applyDynamicTheme(_ preferences: AppPreferences) {
        surfaceViewController.apply(preferences: preferences)
        if let window {
            applyWindowTheme(preferences, to: window)
        }
    }

    private func resizeWindowToPreferredHeight(animated: Bool) {
        resizeWindow(toHeight: settingsViewController.preferredWindowHeight(), animated: animated)
    }

    private func resizeWindow(toHeight requestedHeight: CGFloat, animated: Bool) {
        guard let window else { return }

        let height = max(requestedHeight, WindowMetrics.minimumHeight)
        let oldFrame = window.frame
        let newFrame = NSRect(
            x: oldFrame.origin.x,
            y: oldFrame.maxY - height,
            width: oldFrame.width,
            height: height
        )

        guard abs(oldFrame.height - newFrame.height) > 0.5 else {
            return
        }

        guard animated, window.isVisible else {
            window.setFrame(newFrame, display: true, animate: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
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

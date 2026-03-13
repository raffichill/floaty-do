import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum ChromeMetrics {
        static let trafficLightInset: CGFloat = 18
        static let trafficLightSpacing: CGFloat = 6
    }

    var onPreferencesChange: ((AppPreferences) -> Void)? {
        didSet {
            settingsViewController.onPreferencesChange = onPreferencesChange
        }
    }

    var onWindowVisibilityChange: ((Bool) -> Void)?

    private let settingsViewController: SettingsViewController

    init(preferences: AppPreferences) {
        self.settingsViewController = SettingsViewController(preferences: preferences)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 820, height: 620)
        window.contentViewController = settingsViewController

        let toolbar = NSToolbar(identifier: "settings")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        super.init(window: window)

        shouldCascadeWindows = false
        self.window?.delegate = self
        settingsViewController.onPreferencesChange = { [weak self] preferences in
            self?.onPreferencesChange?(preferences)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.center()
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
}

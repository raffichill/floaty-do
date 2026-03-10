import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.minSize = NSSize(width: 760, height: 520)
        window.contentViewController = settingsViewController
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
        onWindowVisibilityChange?(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        onWindowVisibilityChange?(window?.isVisible == true)
    }
}

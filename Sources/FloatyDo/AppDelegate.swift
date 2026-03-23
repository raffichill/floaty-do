import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum DefaultsKeys {
        static let didShowAboutOnFirstLaunch = "FloatyDo.didShowAboutOnFirstLaunch"
        static let items = "floatydo.items"
        static let archive = "floatydo.archived"
        static let preferences = "floatydo.preferences"
    }

    private enum PanelSnapDirection {
        case left
        case right
        case up
        case down
    }

    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let store = TodoStore()
    private var todoVC: TodoViewController!
    private var appEventMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        syncLiveApplicationIcon()

        let initialWidth = max(CGFloat(store.preferences.panelWidth), CGFloat(LayoutMetrics.minPanelWidth))
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 300))
        panel.minSize = NSSize(width: LayoutMetrics.minPanelWidth, height: 200)
        panel.applyTheme(preferences: store.preferences)
        panel.delegate = self

        // AppKit view controller
        todoVC = TodoViewController(store: store)
        panel.contentViewController = todoVC

        // Menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "FloatyDo") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "✓"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // App-level shortcuts: cmd+1/cmd+2 switch main tabs unless settings is
        // visible, in which case cmd+1/cmd+2/cmd+3 switch settings tabs.
        // cmd+3 opens settings on About, cmd+, opens settings on Theme, cmd+Q
        // quits, cmd+W hides panel, cmd+0 resets the main window size,
        // cmd+z/cmd+shift+z undo/redo, and ctrl+option+arrow snaps the panel
        // to screen edges/corners.
        appEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let characters = event.charactersIgnoringModifiers?.lowercased()

            if mods.isEmpty, event.keyCode == 53, self.todoVC.closeSettingsWindowIfVisible() {
                return nil
            }

            if mods == [.control, .option] {
                switch event.keyCode {
                case 123:
                    self.pushPanel(.left)
                    return nil
                case 124:
                    self.pushPanel(.right)
                    return nil
                case 125:
                    self.pushPanel(.down)
                    return nil
                case 126:
                    self.pushPanel(.up)
                    return nil
                default:
                    break
                }
            }

            if mods == [.command, .control], characters == "f" {
                self.togglePanelFullScreen()
                return nil
            }

            if characters == "z" {
                if mods == .command {
                    return self.todoVC.performUndo() ? nil : event
                }
                if mods == [.command, .shift] {
                    return self.todoVC.performRedo() ? nil : event
                }
            }

            guard mods == .command else { return event }

            if characters == "q" {
                NSApp.terminate(nil)
                return nil
            }
            if characters == "w" {
                if self.todoVC.closeSettingsWindowIfVisible() {
                    return nil
                }
                self.panel.orderOut(nil)
                return nil
            }
            if characters == "," {
                self.todoVC.openSettingsWindow(initialTab: .appearance)
                return nil
            }
            if characters == "1" {
                if self.todoVC.isSettingsWindowVisible {
                    self.todoVC.openSettingsWindow(initialTab: .appearance)
                } else {
                    self.todoVC.showTasksTab()
                }
                return nil
            }
            if characters == "2" {
                if self.todoVC.isSettingsWindowVisible {
                    self.todoVC.openSettingsWindow(initialTab: .shortcuts)
                } else {
                    self.todoVC.showArchiveTab()
                }
                return nil
            }
            if characters == "3" {
                self.todoVC.openSettingsWindow(initialTab: .about)
                return nil
            }
            if characters == "0" {
                self.todoVC.resetWindowSize()
                return nil
            }
            return event
        }

        // Position panel near the status item and show it
        showPanel(activate: true)

        if shouldShowFirstLaunchOnboarding() {
            todoVC.openSettingsWindow(initialTab: .about)
            UserDefaults.standard.set(true, forKey: DefaultsKeys.didShowAboutOnFirstLaunch)
        }
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        guard panel != nil, !panel.isVisible else { return }
        showPanel(activate: true)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(activate: true)
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store.flushPendingSaves()
    }

    public func windowWillEnterFullScreen(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        todoVC.setNativeFullScreenState(active: true)
        panel.level = .normal
        panel.isMovableByWindowBackground = false
        panel.setFullScreenChromeHidden(true)
    }

    public func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        todoVC.syncToWindowBounds()
    }

    public func windowWillExitFullScreen(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        todoVC.syncToWindowBounds()
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        todoVC.setNativeFullScreenState(active: false)
        panel.setFullScreenChromeHidden(false)
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        positionPanel()
    }

    public func window(
        _ window: NSWindow,
        willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions
    ) -> NSApplication.PresentationOptions {
        guard window === panel else { return proposedOptions }
        return proposedOptions.union([.autoHideToolbar, .autoHideMenuBar])
    }

    public func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard window === panel else { return nil }
        return todoVC.undoManager
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        todoVC.recordUserResizedWindowSize(panel.frame.size)
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit FloatyDo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            if panel.isVisible {
                panel.orderOut(nil)
            } else {
                showPanel(activate: true)
            }
        }
    }

    private func showPanel(activate: Bool) {
        if !panel.styleMask.contains(.fullScreen) {
            positionPanel()
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFront(nil)
    }

    private func syncLiveApplicationIcon() {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 128, height: 128)
        NSApp.applicationIconImage = image
    }

    private func shouldShowFirstLaunchOnboarding() -> Bool {
        guard !UserDefaults.standard.bool(forKey: DefaultsKeys.didShowAboutOnFirstLaunch) else {
            return false
        }

        let hasPersistedState =
            UserDefaults.standard.object(forKey: DefaultsKeys.items) != nil ||
            UserDefaults.standard.object(forKey: DefaultsKeys.archive) != nil ||
            UserDefaults.standard.object(forKey: DefaultsKeys.preferences) != nil
        return !hasPersistedState
    }

    private func positionPanel() {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let padding = CGFloat(store.preferences.snapPadding)
        let visibleFrame = screen.visibleFrame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        let x = visibleFrame.maxX - panelWidth - padding
        let y = visibleFrame.maxY - panelHeight - padding

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func pushPanel(_ direction: PanelSnapDirection) {
        guard !panel.styleMask.contains(.fullScreen) else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        if !panel.isVisible {
            panel.orderFront(nil)
        }

        let visibleFrame = screen.visibleFrame
        let padding = CGFloat(store.preferences.snapPadding)
        let size = panel.frame.size
        let currentOrigin = panel.frame.origin

        let origin: NSPoint
        switch direction {
        case .left:
            origin = NSPoint(
                x: visibleFrame.minX + padding,
                y: currentOrigin.y
            )
        case .right:
            origin = NSPoint(
                x: visibleFrame.maxX - size.width - padding,
                y: currentOrigin.y
            )
        case .up:
            origin = NSPoint(
                x: currentOrigin.x,
                y: visibleFrame.maxY - size.height - padding
            )
        case .down:
            origin = NSPoint(
                x: currentOrigin.x,
                y: visibleFrame.minY + padding
            )
        }

        let clampedOrigin = NSPoint(
            x: min(max(origin.x, visibleFrame.minX + padding), visibleFrame.maxX - size.width - padding),
            y: min(max(origin.y, visibleFrame.minY + padding), visibleFrame.maxY - size.height - padding)
        )

        guard clampedOrigin != currentOrigin else { return }
        panel.setFrameOrigin(clampedOrigin)
    }

    private func togglePanelFullScreen() {
        if !panel.isVisible {
            showPanel(activate: true)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.toggleFullScreen(nil)
    }
}

import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
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

    private func debugLog(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/FloatyDo-launch.log")
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: url)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.regular)

        let initialWidth = max(CGFloat(store.preferences.panelWidth), CGFloat(LayoutMetrics.minPanelWidth))
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 300))
        panel.minSize = NSSize(width: LayoutMetrics.minPanelWidth, height: 200)
        panel.applyTheme(preferences: store.preferences)
        debugLog("panel created")

        // AppKit view controller
        todoVC = TodoViewController(store: store)
        panel.contentViewController = todoVC
        debugLog("content view controller attached")

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
            debugLog("status item button configured")
        } else {
            debugLog("status item button missing")
        }

        // App-level shortcuts: cmd+Q to quit, cmd+W to hide panel, cmd+, for theme
        appEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if mods.isEmpty, event.keyCode == 53, self.todoVC.closeSettingsWindowIfVisible() {
                return nil
            }

            guard mods == .command else { return event }

            if event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
            }
            if event.charactersIgnoringModifiers == "w" {
                if self.todoVC.closeSettingsWindowIfVisible() {
                    return nil
                }
                self.panel.orderOut(nil)
                return nil
            }
            if event.charactersIgnoringModifiers == "," {
                self.todoVC.openSettingsWindow()
                return nil
            }
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
            return event
        }

        // Position panel near the status item and show it
        showPanel(activate: true)
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        debugLog("applicationDidBecomeActive visible=\(panel?.isVisible ?? false)")
        guard panel != nil, !panel.isVisible else { return }
        showPanel(activate: true)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        debugLog("applicationShouldHandleReopen visible=\(flag)")
        showPanel(activate: true)
        return true
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
        debugLog("showPanel activate=\(activate)")
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
        debugLog("panel visible after show=\(panel.isVisible) frame=\(panel.frame.debugDescription)")
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
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        if !panel.isVisible {
            panel.orderFront(nil)
        }

        let visibleFrame = screen.visibleFrame
        let padding = CGFloat(store.preferences.snapPadding)
        let size = panel.frame.size

        let origin: NSPoint
        switch direction {
        case .left:
            origin = NSPoint(
                x: visibleFrame.minX + padding,
                y: visibleFrame.midY - (size.height / 2)
            )
        case .right:
            origin = NSPoint(
                x: visibleFrame.maxX - size.width - padding,
                y: visibleFrame.midY - (size.height / 2)
            )
        case .up:
            origin = NSPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.maxY - size.height - padding
            )
        case .down:
            origin = NSPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.minY + padding
            )
        }

        let clampedOrigin = NSPoint(
            x: min(max(origin.x, visibleFrame.minX + padding), visibleFrame.maxX - size.width - padding),
            y: min(max(origin.y, visibleFrame.minY + padding), visibleFrame.maxY - size.height - padding)
        )

        let targetFrame = NSRect(origin: clampedOrigin, size: size)
        panel.setFrame(targetFrame, display: true, animate: true)
    }
}

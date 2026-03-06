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

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        let initialWidth = max(CGFloat(store.preferences.panelWidth), CGFloat(LayoutMetrics.minPanelWidth))
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: 300))
        panel.minSize = NSSize(width: LayoutMetrics.minPanelWidth, height: 200)

        // AppKit view controller
        todoVC = TodoViewController(store: store)
        panel.contentViewController = todoVC

        // Menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "FloatyDo")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // App-level shortcuts: cmd+Q to quit, cmd+W to hide panel
        appEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command else { return event }

            if event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
            }
            if event.charactersIgnoringModifiers == "w" {
                self.panel.orderOut(nil)
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
        positionPanel()
        panel.orderFront(nil)
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
                positionPanel()
                panel.orderFront(nil)
            }
        }
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

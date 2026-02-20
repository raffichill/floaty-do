import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let store = TodoStore()
    private var todoVC: TodoViewController!
    private var appEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create floating panel (400×300 default, 300×200 minimum)
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        panel.minSize = NSSize(width: 300, height: 200)

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
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonRect = buttonWindow.frame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        let x = buttonRect.midX - panelWidth / 2
        let y = buttonRect.minY - panelHeight - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// Bootstrap
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let store = TodoStore()
    private var todoVC: TodoViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create floating panel
        let initialRows = min(store.items.count + 3, TodoStore.maxItems)
        let height = CGFloat(initialRows) * 36.0 + 16.5
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: height))

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

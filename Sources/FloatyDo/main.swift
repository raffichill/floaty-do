import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let store = TodoStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create floating panel
        // 10 rows * 32pt + 16pt vertical padding
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 336))
        let hostingView = NSHostingView(rootView: TodoListView(store: store))
        panel.contentView = hostingView

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
            // Show quit menu on right-click
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit FloatyDo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Toggle panel on left-click
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

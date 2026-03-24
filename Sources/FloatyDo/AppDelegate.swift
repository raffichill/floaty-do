import AppKit
import Combine
import Carbon.HIToolbox

private let globalHotkeySignature: OSType = 0x4644484B  // "FDHK"

private func handleGlobalHotkeyEvent(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    delegate.handleRegisteredGlobalHotkey()
    return noErr
}

struct PanelResetPlacement {
    static func nearestCornerOrigin(
        currentOrigin: NSPoint,
        windowSize: NSSize,
        visibleFrame: NSRect,
        padding: CGFloat
    ) -> NSPoint {
        let corners = [
            NSPoint(
                x: visibleFrame.minX + padding,
                y: visibleFrame.minY + padding
            ),
            NSPoint(
                x: visibleFrame.minX + padding,
                y: visibleFrame.maxY - windowSize.height - padding
            ),
            NSPoint(
                x: visibleFrame.maxX - windowSize.width - padding,
                y: visibleFrame.minY + padding
            ),
            NSPoint(
                x: visibleFrame.maxX - windowSize.width - padding,
                y: visibleFrame.maxY - windowSize.height - padding
            ),
        ]

        return corners.min {
            squaredDistance(from: currentOrigin, to: $0) < squaredDistance(from: currentOrigin, to: $1)
        } ?? currentOrigin
    }

    private static func squaredDistance(from lhs: NSPoint, to rhs: NSPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx) + (dy * dy)
    }
}

public class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private struct LiveResizeSession {
        let session: LiveResizeRubberBanding.Session
        var pendingSettleFrame: NSRect?
    }

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
    private var liveResizeSession: LiveResizeSession?
    private var liveResizeTrackingTimer: Timer?
    private var isApplyingRubberBandFrame = false
    private var preferencesObserver: AnyCancellable?
    private var globalHotKeyRef: EventHotKeyRef?
    private var globalHotKeyHandlerRef: EventHandlerRef?
    private var registeredGlobalHotkey: GlobalHotkey?

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
            if let image = NSImage(systemSymbolName: "checkmark.app.fill", accessibilityDescription: "FloatyDo") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "✓"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        installGlobalHotkeyHandlerIfNeeded()
        registerGlobalHotkey(store.preferences.globalHotkey)
        observePreferences()

        // App-level shortcuts: cmd+1/cmd+2 switch main tabs unless settings is
        // visible, in which case cmd+1/cmd+2/cmd+3 switch settings tabs.
        // cmd+3 opens settings on Theme unless settings is already visible,
        // cmd+, opens settings on Theme, cmd+Q quits, cmd+W hides panel,
        // cmd+0 resets the main window size and snaps it to the nearest
        // screen corner,
        // cmd+z/cmd+shift+z undo/redo, and ctrl+option+arrow snaps the panel
        // to screen edges/corners.
        appEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.todoVC.isSettingsHotkeyCaptureActive {
                return event
            }
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
                if self.todoVC.isSettingsWindowVisible {
                    self.todoVC.openSettingsWindow(initialTab: .about)
                } else {
                    self.todoVC.openSettingsWindow(initialTab: .appearance)
                }
                return nil
            }
            if characters == "0" {
                self.resetPanelWindowSizeAndSnap()
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
        unregisterGlobalHotkey()
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

    public func windowWillStartLiveResize(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        let edges = LiveResizeRubberBanding.dragEdges(for: mouseLocation, in: panel.frame)
        let session = LiveResizeRubberBanding.Session(
            initialFrame: panel.frame,
            initialMouseLocation: mouseLocation,
            edges: edges,
            minSize: panel.minSize
        )
        liveResizeSession = LiveResizeSession(session: session, pendingSettleFrame: nil)
        startLiveResizeTracking()
    }

    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === panel, let liveResizeSession else { return frameSize }
        let result = LiveResizeRubberBanding.result(
            for: liveResizeSession.session,
            currentMouseLocation: NSEvent.mouseLocation
        )
        self.liveResizeSession?.pendingSettleFrame = result.isRubberBanding ? result.settleFrame : nil
        return result.settleFrame.size
    }

    public func windowDidResize(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        guard panel.inLiveResize, let liveResizeSession, !isApplyingRubberBandFrame else { return }

        let result = LiveResizeRubberBanding.result(
            for: liveResizeSession.session,
            currentMouseLocation: NSEvent.mouseLocation
        )
        self.liveResizeSession?.pendingSettleFrame = result.isRubberBanding ? result.settleFrame : nil

        let targetFrame = result.isRubberBanding ? result.displayFrame : result.settleFrame
        guard !framesApproximatelyEqual(panel.frame, targetFrame) else { return }

        isApplyingRubberBandFrame = true
        panel.setFrame(targetFrame, display: true, animate: false)
        isApplyingRubberBandFrame = false
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        stopLiveResizeTracking()
        let pendingSettleFrame = liveResizeSession?.pendingSettleFrame
        liveResizeSession = nil

        guard let targetFrame = pendingSettleFrame, !framesApproximatelyEqual(panel.frame, targetFrame) else {
            todoVC.recordUserResizedWindowSize(panel.frame.size)
            return
        }

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = LiveResizeRubberBanding.releaseDuration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
                panel.animator().setFrame(targetFrame, display: true)
            },
            completionHandler: { [weak self] in
                self?.todoVC.recordUserResizedWindowSize(targetFrame.size)
            }
        )
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
            togglePanelVisibility()
        }
    }

    fileprivate func handleRegisteredGlobalHotkey() {
        if todoVC.isSettingsHotkeyCaptureActive {
            return
        }
        togglePanelVisibility()
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

    private func togglePanelVisibility() {
        if panel.isVisible {
            _ = todoVC.closeSettingsWindowIfVisible()
            panel.orderOut(nil)
        } else {
            showPanel(activate: true)
        }
    }

    private func observePreferences() {
        preferencesObserver = store.$preferences
            .removeDuplicates()
            .sink { [weak self] preferences in
                self?.registerGlobalHotkey(preferences.globalHotkey)
            }
    }

    private func installGlobalHotkeyHandlerIfNeeded() {
        guard globalHotKeyHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            handleGlobalHotkeyEvent,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &globalHotKeyHandlerRef
        )
    }

    private func registerGlobalHotkey(_ hotkey: GlobalHotkey) {
        let normalized = hotkey.normalized
        guard registeredGlobalHotkey != normalized else { return }
        var newRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: globalHotkeySignature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(normalized.keyCode),
            normalized.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef else { return }
        if let existing = globalHotKeyRef {
            UnregisterEventHotKey(existing)
        }
        globalHotKeyRef = newRef
        registeredGlobalHotkey = normalized
    }

    private func unregisterGlobalHotkey() {
        if let existing = globalHotKeyRef {
            UnregisterEventHotKey(existing)
            globalHotKeyRef = nil
        }
        registeredGlobalHotkey = nil
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

    private func framesApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
        abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance &&
        abs(lhs.height - rhs.height) <= tolerance
    }

    private func resetPanelWindowSizeAndSnap() {
        todoVC.resetWindowSize()

        guard !panel.styleMask.contains(.fullScreen) else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let visibleFrame = screen.visibleFrame
        let padding = CGFloat(store.preferences.snapPadding)
        let nearestCorner = PanelResetPlacement.nearestCornerOrigin(
            currentOrigin: panel.frame.origin,
            windowSize: panel.frame.size,
            visibleFrame: visibleFrame,
            padding: padding
        )

        guard panel.frame.origin != nearestCorner else { return }
        panel.setFrameOrigin(nearestCorner)
    }

    private func startLiveResizeTracking() {
        stopLiveResizeTracking()

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.updateLiveResizeDisplay(currentMouseLocation: NSEvent.mouseLocation)
        }
        liveResizeTrackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    private func stopLiveResizeTracking() {
        liveResizeTrackingTimer?.invalidate()
        liveResizeTrackingTimer = nil
    }

    private func updateLiveResizeDisplay(currentMouseLocation: NSPoint) {
        guard let liveResizeSession, !isApplyingRubberBandFrame else { return }

        let result = LiveResizeRubberBanding.result(
            for: liveResizeSession.session,
            currentMouseLocation: currentMouseLocation
        )
        self.liveResizeSession?.pendingSettleFrame = result.isRubberBanding ? result.settleFrame : nil

        // Only take over the frame while banding, or while settling back from a
        // previously banded state during the same drag. Standard above-minimum
        // resizing should remain AppKit-driven.
        let targetFrame = result.isRubberBanding ? result.displayFrame : result.settleFrame
        let shouldDriveFrame = result.isRubberBanding || !framesApproximatelyEqual(panel.frame, result.settleFrame)
        guard shouldDriveFrame, !framesApproximatelyEqual(panel.frame, targetFrame) else { return }

        isApplyingRubberBandFrame = true
        panel.setFrame(targetFrame, display: true, animate: false)
        isApplyingRubberBandFrame = false
    }
}

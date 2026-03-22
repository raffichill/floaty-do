import AppKit

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct SettingsWindowPlacement {
    enum HorizontalSide {
        case left
        case right
    }

    static let companionGap: CGFloat = 24
    static let screenEdgePadding: CGFloat = 24
    static let minimumViewportWidthForCompanionLayout: CGFloat = 1400
    static let minimumViewportHeightForCompanionLayout: CGFloat = 820

    static func origin(for windowSize: NSSize, parentFrame: NSRect?, visibleFrame: NSRect) -> NSPoint {
        guard let parentFrame, supportsCompanionLayout(windowSize: windowSize, parentFrame: parentFrame, visibleFrame: visibleFrame) else {
            return centeredOrigin(for: windowSize, in: visibleFrame)
        }

        let orderedSides = preferredHorizontalSides(parentFrame: parentFrame, visibleFrame: visibleFrame)
        let alignedToTop = parentFrame.midY >= visibleFrame.midY
        let expandedParentFrame = parentFrame.insetBy(dx: -(companionGap / 2.0), dy: -8)

        let candidates = orderedSides.map {
            candidateFrame(
                for: windowSize,
                side: $0,
                alignedToTop: alignedToTop,
                parentFrame: parentFrame,
                visibleFrame: visibleFrame
            )
        }

        if let nonIntersectingCandidate = candidates.first(where: { !$0.intersects(expandedParentFrame) }) {
            return nonIntersectingCandidate.origin
        }

        return candidates.first?.origin ?? centeredOrigin(for: windowSize, in: visibleFrame)
    }

    private static func supportsCompanionLayout(windowSize: NSSize, parentFrame: NSRect, visibleFrame: NSRect) -> Bool {
        let requiredWidth = parentFrame.width + windowSize.width + companionGap + (screenEdgePadding * 2.0)
        let requiredHeight = max(parentFrame.height, windowSize.height) + (screenEdgePadding * 2.0)
        return visibleFrame.width >= max(requiredWidth, minimumViewportWidthForCompanionLayout)
            && visibleFrame.height >= max(requiredHeight, minimumViewportHeightForCompanionLayout)
    }

    private static func preferredHorizontalSides(parentFrame: NSRect, visibleFrame: NSRect) -> [HorizontalSide] {
        let leftSpace = parentFrame.minX - visibleFrame.minX
        let rightSpace = visibleFrame.maxX - parentFrame.maxX
        return rightSpace >= leftSpace ? [.right, .left] : [.left, .right]
    }

    private static func candidateFrame(
        for windowSize: NSSize,
        side: HorizontalSide,
        alignedToTop: Bool,
        parentFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        let rawX: CGFloat
        switch side {
        case .left:
            rawX = parentFrame.minX - companionGap - windowSize.width
        case .right:
            rawX = parentFrame.maxX + companionGap
        }

        let rawY = alignedToTop
            ? parentFrame.maxY - windowSize.height
            : parentFrame.minY

        let clampedOrigin = clampedOrigin(
            rawOrigin: NSPoint(x: rawX, y: rawY),
            size: windowSize,
            visibleFrame: visibleFrame
        )
        return NSRect(origin: clampedOrigin, size: windowSize)
    }

    private static func clampedOrigin(rawOrigin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(
                max(rawOrigin.x, visibleFrame.minX + screenEdgePadding),
                visibleFrame.maxX - size.width - screenEdgePadding
            ),
            y: min(
                max(rawOrigin.y, visibleFrame.minY + screenEdgePadding),
                visibleFrame.maxY - size.height - screenEdgePadding
            )
        )
    }

    private static func centeredOrigin(for windowSize: NSSize, in visibleFrame: NSRect) -> NSPoint {
        clampedOrigin(
            rawOrigin: NSPoint(
                x: visibleFrame.midX - (windowSize.width / 2.0),
                y: visibleFrame.midY - (windowSize.height / 2.0)
            ),
            size: windowSize,
            visibleFrame: visibleFrame
        )
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum InitialTab {
        case appearance
        case shortcuts
        case about
    }

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

    func present(attachedTo parentWindow: NSWindow?, initialTab: InitialTab? = nil) {
        if let initialTab {
            switch initialTab {
            case .appearance:
                settingsViewController.showAppearanceTab(animated: false)
            case .shortcuts:
                settingsViewController.showShortcutsTab(animated: false)
            case .about:
                settingsViewController.showAboutTab(animated: false)
            }
        }

        resizeWindowToPreferredHeight(animated: false)
        if let window, !window.isVisible {
            let visibleFrame = parentWindow?.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? window.screen?.visibleFrame
                ?? window.frame
            let origin = SettingsWindowPlacement.origin(
                for: window.frame.size,
                parentFrame: parentWindow?.frame,
                visibleFrame: visibleFrame
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

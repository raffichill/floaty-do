import AppKit
import Combine
import QuartzCore

public enum Tab: Equatable { case tasks, archive }

private struct TaskDraftState: Equatable {
    var insertionIndex: Int
    var text: String

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedText.isEmpty
    }
}

private struct TodoUndoSnapshot: Equatable {
    let items: [TodoItem]
    let archivedItems: [TodoItem]
    let preferences: AppPreferences
    let currentTab: Tab
    let selectedRowID: TodoRowID?
    let selectionAnchorRowID: TodoRowID?
    let selectedRowIDs: Set<TodoRowID>
    let taskDraft: TaskDraftState
}

public final class TodoViewController: NSViewController, NSTextFieldDelegate {
    private enum DebugMetrics {
        static let showsHeaderButtonHitTargets = false
        static let showsHeaderAreaOutline = false
        static let headerButtonWidth: CGFloat = 34
        static let headerButtonOutlineColor = NSColor.systemPink.withAlphaComponent(0.9)
        static let headerAreaOutlineColor = NSColor.systemPink.withAlphaComponent(0.9)
    }

    private let store: TodoStore
    private let listScrollView = NSScrollView()
    private let listView = TodoListView()
    private let sharedEditor = KeyboardOnlyTextField()

    private var selectedRowID: TodoRowID?
    private var selectionAnchorRowID: TodoRowID?
    private var selectedRowIDs = Set<TodoRowID>()
    private var editorRowID: TodoRowID?
    private var rowModels: [TodoRowModel] = []
    private var taskDraft: TaskDraftState
    private var eventMonitor: Any?
    private var cursorEventMonitor: Any?
    private var editorSelectionObserver: Any?
    private var windowFocusObservers: [NSObjectProtocol] = []
    private var deferredEditorRowID: TodoRowID?
    private var deferredEditorActivationWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var currentTab: Tab = .tasks
    private var tasksTabButton: HeaderIconButton!
    private var archiveTabButton: HeaderIconButton!
    private var settingsButton: HeaderIconButton!
    private var settingsWindowController: SettingsWindowController?
    private var isAnimating = false
    private weak var surfaceView: PanelSurfaceView?
    private weak var containerView: NSView?
    private var headerDebugHeightConstraint: NSLayoutConstraint?
    private var listTopConstraint: NSLayoutConstraint?
    private var lastKnownHeaderHeight: CGFloat = 0
    private var lastReportedHeaderHeight: CGFloat = -1
    private let historyManager = UndoManager()
    private var isApplyingSettingsPreferenceChange = false
    private var nativeFullScreenState = false
    private var appliedPreferences: AppPreferences
    private var userPreferredWindowWidth: CGFloat?
    private var userPreferredWindowHeight: CGFloat?

    public init(store: TodoStore) {
        self.store = store
        self.taskDraft = TaskDraftState(insertionIndex: store.items.count, text: "")
        self.appliedPreferences = store.preferences
        super.init(nibName: nil, bundle: nil)
        historyManager.levelsOfUndo = 100
    }

    required init?(coder: NSCoder) { fatalError() }

    private var motion: MotionProfile { store.preferences.motion }
    private var rowHeight: CGFloat { CGFloat(store.preferences.rowHeight) }
    private var panelWidth: CGFloat { CGFloat(store.preferences.panelWidth) }
    private var visibleRowCount: Int { targetVisibleRowCount() }
    private var selectedRowIndex: Int? {
        guard let selectedRowID else { return nil }
        return rowModels.firstIndex(where: { $0.id == selectedRowID })
    }

    private var selectedModel: TodoRowModel? {
        guard let selectedRowIndex else { return nil }
        return rowModels[selectedRowIndex]
    }

    private var defaultDraftInsertionIndex: Int {
        store.items.count
    }

    private var canShowDraftRow: Bool {
        store.items.count < TodoStore.maxItems
    }

    private var draftIsAtDefaultPosition: Bool {
        taskDraft.insertionIndex == defaultDraftInsertionIndex
    }

    private var isRangeSelectionActive: Bool {
        !selectedRowIDs.isEmpty
    }

    private var currentEditingRowID: TodoRowID? {
        guard !isAnimating, !listView.isDragging, !isRangeSelectionActive else { return nil }
        guard let selectedModel else { return nil }
        guard deferredEditorRowID != selectedModel.id else { return nil }
        return selectedModel.isEditable ? selectedModel.id : nil
    }

    private var isInNativeFullScreen: Bool {
        nativeFullScreenState || view.window?.styleMask.contains(.fullScreen) == true
    }

    public override func loadView() {
        let panelSurface = PanelSurfaceView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 240))
        panelSurface.apply(preferences: store.preferences)
        let container = panelSurface.contentView
        self.surfaceView = panelSurface
        containerView = container

        tasksTabButton = makeHeaderButton(symbolName: "checklist.unchecked", action: #selector(switchToTasks))
        archiveTabButton = makeHeaderButton(symbolName: "archivebox", action: #selector(switchToArchive))
        archiveTabButton.onHoverChange = { [weak self] _ in
            self?.updateTabAppearance()
        }
        settingsButton = makeHeaderButton(symbolName: "paintpalette", action: #selector(toggleSettings(_:)))
        settingsButton.onHoverChange = { [weak self] _ in
            self?.updateTabAppearance()
        }

        let headerDebugView = NSView()
        headerDebugView.translatesAutoresizingMaskIntoConstraints = false
        applyHeaderDebugOutline(to: headerDebugView)

        let tabBar = NSView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerDebugView)
        container.addSubview(tabBar)
        tabBar.addSubview(tasksTabButton)
        tabBar.addSubview(archiveTabButton)
        tabBar.addSubview(settingsButton)

        var headerButtonDebugOverlay: HeaderButtonDebugOverlayView?
        if DebugMetrics.showsHeaderButtonHitTargets {
            let overlay = HeaderButtonDebugOverlayView(
                cellWidth: DebugMetrics.headerButtonWidth,
                strokeColor: DebugMetrics.headerButtonOutlineColor
            )
            overlay.translatesAutoresizingMaskIntoConstraints = false
            tabBar.addSubview(overlay)
            headerButtonDebugOverlay = overlay
        }

        listScrollView.translatesAutoresizingMaskIntoConstraints = false
        listScrollView.drawsBackground = false
        listScrollView.borderType = .noBorder
        listScrollView.hasVerticalScroller = false
        listScrollView.hasHorizontalScroller = false
        listScrollView.autohidesScrollers = true
        listScrollView.scrollerStyle = .overlay
        listScrollView.verticalScrollElasticity = .none

        listView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 240)
        listView.autoresizingMask = [.width]
        listView.delegate = self
        listScrollView.documentView = listView
        sharedEditor.frame = NSRect(x: -1000, y: -1000, width: 1, height: 1)
        sharedEditor.alphaValue = 0.001

        container.addSubview(listScrollView)
        container.addSubview(sharedEditor)

        let initialHeaderHeight = defaultHeaderHeight
        let listTopConstraint = listScrollView.topAnchor.constraint(
            equalTo: container.topAnchor,
            constant: initialHeaderHeight + CGFloat(LayoutMetrics.contentTopPadding)
        )
        let headerDebugHeightConstraint = headerDebugView.heightAnchor.constraint(equalToConstant: initialHeaderHeight)
        self.headerDebugHeightConstraint = headerDebugHeightConstraint
        self.listTopConstraint = listTopConstraint

        var constraints = [
            headerDebugView.topAnchor.constraint(equalTo: container.topAnchor),
            headerDebugView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerDebugView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerDebugHeightConstraint,

            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: headerDebugView.bottomAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            tabBar.widthAnchor.constraint(equalToConstant: DebugMetrics.headerButtonWidth * 3),

            tasksTabButton.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            tasksTabButton.topAnchor.constraint(equalTo: tabBar.topAnchor),
            tasksTabButton.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),

            archiveTabButton.leadingAnchor.constraint(
                equalTo: tasksTabButton.trailingAnchor
            ),
            archiveTabButton.topAnchor.constraint(equalTo: tabBar.topAnchor),
            archiveTabButton.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            archiveTabButton.widthAnchor.constraint(equalTo: tasksTabButton.widthAnchor),

            settingsButton.leadingAnchor.constraint(
                equalTo: archiveTabButton.trailingAnchor
            ),
            settingsButton.topAnchor.constraint(equalTo: tabBar.topAnchor),
            settingsButton.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            settingsButton.widthAnchor.constraint(equalTo: tasksTabButton.widthAnchor),

            listTopConstraint,
            listScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            listScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]

        if let headerButtonDebugOverlay {
            constraints.append(contentsOf: [
                headerButtonDebugOverlay.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
                headerButtonDebugOverlay.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
                headerButtonDebugOverlay.topAnchor.constraint(equalTo: tabBar.topAnchor),
                headerButtonDebugOverlay.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            ])
        }

        NSLayoutConstraint.activate(constraints)

        self.view = panelSurface
        updateListScrollBehavior()
        updateTabAppearance()
    }

    public override var undoManager: UndoManager? {
        historyManager
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureSharedEditor()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !self.isAnimating, !self.listView.isBusy else { return event }

            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let hasCommand = mods.contains(.command)
            let hasShift = mods.contains(.shift)
            let hasOption = mods.contains(.option)
            let hasControl = mods.contains(.control)

            if hasCommand && !hasShift && !hasOption && !hasControl {
                if event.charactersIgnoringModifiers?.lowercased() == "a" {
                    self.handleCommandSelectAll()
                    return nil
                }

                switch event.keyCode {
                case 125:
                    self.jumpToBoundary(.bottom)
                    return nil
                case 126:
                    self.jumpToBoundary(.top)
                    return nil
                case 36:
                    self.handleCommandReturn()
                    return nil
                case 51:
                    self.handleCommandDelete()
                    return nil
                default:
                    return event
                }
            }

            if hasShift && !hasCommand && !hasOption && !hasControl {
                switch event.keyCode {
                case 125:
                    self.extendSelection(step: 1)
                    return nil
                case 126:
                    self.extendSelection(step: -1)
                    return nil
                case 48:
                    self.moveUp()
                    return nil
                default:
                    break
                }
            }

            if hasCommand && hasShift && !hasOption && !hasControl {
                switch event.keyCode {
                case 125:
                    self.extendSelection(to: .bottom)
                    return nil
                case 126:
                    self.extendSelection(to: .top)
                    return nil
                default:
                    break
                }
            }

            let firstResponder = self.view.window?.firstResponder
            let listOwnsFocus = firstResponder === self.listView || firstResponder === self.view
            if self.isRangeSelectionActive, mods.isEmpty {
                switch event.keyCode {
                case 53:
                    self.clearRangeSelection(placeCaretAtEnd: false)
                    return nil
                case 36:
                    if self.currentTab == .tasks {
                        self.submitRow()
                        return nil
                    }
                case 48:
                    self.moveDown()
                    return nil
                case 125:
                    self.moveDown()
                    return nil
                case 126:
                    self.moveUp()
                    return nil
                default:
                    self.clearRangeSelection(placeCaretAtEnd: true)
                    return event
                }
            }

            guard listOwnsFocus else { return event }

            if mods == [] {
                switch event.keyCode {
                case 126:
                    self.moveUp()
                    return nil
                case 125:
                    self.moveDown()
                    return nil
                case 48:
                    self.moveDown()
                    return nil
                case 36:
                    if self.currentTab == .tasks {
                        self.submitRow()
                        return nil
                    }
                default:
                    break
                }
            }

            return event
        }

        cursorEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.cursorUpdate, .mouseMoved]) { [weak self] event in
            guard let self else { return event }
            guard self.shouldForceArrowCursor(for: event) else { return event }
            NSCursor.arrow.set()
            if event.type == .cursorUpdate {
                return nil
            }
            return event
        }

        store.$preferences
            .dropFirst()
            .sink { [weak self] preferences in
                guard let self else { return }
                if Thread.isMainThread {
                    self.preferencesDidChange(preferences)
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.preferencesDidChange(preferences)
                    }
                }
            }
            .store(in: &cancellables)

        refreshRows(animateResize: false)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.acceptsMouseMovedEvents = true
        installWindowFocusObserversIfNeeded()
        if let panel = view.window as? FloatingPanel {
            panel.applyTheme(preferences: store.preferences)
        }
        updateHeaderLayoutInsets()
        refreshRows(resize: false, animateResize: false, placeCaretAtEnd: false)
        resizeWindow(animate: false)
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        syncToWindowBounds()
        updateHeaderLayoutInsets()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = cursorEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = editorSelectionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        windowFocusObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func shouldForceArrowCursor(for event: NSEvent) -> Bool {
        guard let window = view.window, event.window === window else { return false }
        let locationInList = listView.convert(event.locationInWindow, from: nil)
        return listView.bounds.contains(locationInList)
    }

    private func configureSharedEditor() {
        sharedEditor.isBordered = false
        sharedEditor.drawsBackground = false
        sharedEditor.font = store.preferences.appFont()
        sharedEditor.focusRingType = .none
        sharedEditor.lineBreakMode = .byTruncatingTail
        sharedEditor.cell?.isScrollable = true
        sharedEditor.wantsLayer = true
        sharedEditor.delegate = self
        sharedEditor.autoresizingMask = [.width, .height]
    }

    private func preferencesDidChange(_ preferences: AppPreferences) {
        let previousPreferences = appliedPreferences
        appliedPreferences = preferences

        sharedEditor.font = preferences.appFont()
        if !isApplyingSettingsPreferenceChange {
            settingsWindowController?.updatePreferences(preferences)
        }
        if let panel = view.window as? FloatingPanel {
            panel.applyTheme(preferences: preferences)
        }
        surfaceView?.apply(preferences: preferences)
        updateHeaderLayoutInsets()
        updateTabAppearance()
        if preferencesRequireRowRefresh(old: previousPreferences, new: preferences) {
            refreshRows(preferences: preferences, animateResize: false)
        }
        view.window?.layoutIfNeeded()
        view.window?.displayIfNeeded()
        settingsWindowController?.window?.displayIfNeeded()
        NSApp.updateWindows()
    }

    private func installWindowFocusObserversIfNeeded() {
        guard windowFocusObservers.isEmpty, let window = view.window else { return }
        let center = NotificationCenter.default
        windowFocusObservers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.updateTabAppearance()
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.archiveTabButton.resetHoverState()
                self?.settingsButton.resetHoverState()
                self?.updateTabAppearance()
            },
        ]
    }

    private var defaultHeaderHeight: CGFloat {
        CGFloat(LayoutMetrics.trafficLightTopInset + 14)
    }

    private func effectiveHeaderHeight(for window: NSWindow?) -> CGFloat {
        if window?.styleMask.contains(.fullScreen) == true {
            return defaultHeaderHeight
        }

        let safeAreaTop = surfaceView?.safeAreaInsets.top ?? view.safeAreaInsets.top
        let layoutChromeHeight: CGFloat
        if let window {
            layoutChromeHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        } else {
            layoutChromeHeight = 0
        }

        let measuredHeight = max(safeAreaTop, layoutChromeHeight)
        if measuredHeight > 0.5 {
            lastKnownHeaderHeight = measuredHeight
        }

        return max(lastKnownHeaderHeight, defaultHeaderHeight)
    }

    private func updateHeaderLayoutInsets() {
        let headerHeight = effectiveHeaderHeight(for: view.window)
        headerDebugHeightConstraint?.constant = headerHeight
        listTopConstraint?.constant = headerHeight + CGFloat(LayoutMetrics.contentTopPadding)
        if abs(lastReportedHeaderHeight - headerHeight) > 0.5 {
            lastReportedHeaderHeight = headerHeight
            NSLog("Main panel header height: %.1f", headerHeight)
        }
    }

    private func preferencesRequireRowRefresh(old: AppPreferences, new: AppPreferences) -> Bool {
        old.rowHeight != new.rowHeight ||
        old.panelWidth != new.panelWidth ||
        old.theme != new.theme ||
        old.fontStyle != new.fontStyle ||
        old.fontSize != new.fontSize ||
        old.cornerRadius != new.cornerRadius
    }

    private func makeHeaderButton(symbolName: String, action: Selector) -> HeaderIconButton {
        let button = HeaderIconButton(symbolName: symbolName, target: self, action: action)
        button.suppressSystemHighlight = true
        button.pressedScale = 0.85
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: DebugMetrics.headerButtonWidth).isActive = true
        return button
    }

    private func applyHeaderDebugOutline(to view: NSView) {
        guard DebugMetrics.showsHeaderAreaOutline else { return }
        view.wantsLayer = true
        view.layer?.cornerRadius = 0
        view.layer?.borderWidth = 1
        view.layer?.borderColor = DebugMetrics.headerAreaOutlineColor.cgColor
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func updateTabAppearance() {
        let primary = store.preferences.primaryTextColor
        let settingsIsVisible = settingsWindowController?.window?.isVisible == true
        let tasksIsEmphasized = !settingsIsVisible && currentTab == .tasks
        tasksTabButton.applyTint(tasksIsEmphasized ? primary : primary.withAlphaComponent(0.35))

        let archiveIsEmphasized = !settingsIsVisible && (currentTab == .archive || archiveTabButton.isHovered)
        archiveTabButton.applyTint(archiveIsEmphasized ? primary : primary.withAlphaComponent(0.35))

        let settingsIsEmphasized = settingsIsVisible || settingsButton.isHovered
        settingsButton.applyTint(settingsIsEmphasized ? primary : primary.withAlphaComponent(0.42))
    }

    @objc private func switchToTasks() {
        let dismissedSettings = dismissSettingsWindowIfVisible()
        guard currentTab != .tasks else {
            if dismissedSettings {
                updateTabAppearance()
            }
            return
        }
        cancelDeferredEditorActivation()
        currentTab = .tasks
        selectedRowID = nil
        clearRangeSelectionState()
        updateTabAppearance()
        updateListScrollBehavior()
        refreshRows(resize: true, animateResize: true)
    }

    @objc private func switchToArchive() {
        let dismissedSettings = dismissSettingsWindowIfVisible()
        guard currentTab != .archive else {
            if dismissedSettings {
                updateTabAppearance()
            }
            return
        }
        cancelDeferredEditorActivation()
        currentTab = .archive
        selectedRowID = nil
        clearRangeSelectionState()
        updateTabAppearance()
        updateListScrollBehavior()
        refreshRows(resize: true, animateResize: true)
    }

    func showTasksTab() {
        switchToTasks()
    }

    func showArchiveTab() {
        switchToArchive()
    }

    private func updateListScrollBehavior() {
        let allowsOverflowScrolling = currentTab == .archive
        listScrollView.hasVerticalScroller = false
        listScrollView.verticalScrollElasticity = allowsOverflowScrolling ? .automatic : .none
    }

    @objc private func toggleSettings(_ sender: NSButton) {
        if let window = settingsWindowController?.window, window.isVisible {
            dismissSettingsWindowIfVisible()
            return
        }

        openSettingsWindow()
    }

    func closeSettingsWindowIfVisible() -> Bool {
        dismissSettingsWindowIfVisible()
    }

    @discardableResult
    private func dismissSettingsWindowIfVisible() -> Bool {
        guard let window = settingsWindowController?.window, window.isVisible else {
            return false
        }
        window.close()
        restoreFocusAfterSettingsDismissal()
        return true
    }

    func openSettingsWindow(initialTab: SettingsWindowController.InitialTab? = nil) {
        let controller = settingsWindowController ?? SettingsWindowController(preferences: store.preferences)
        controller.onPreferencesChange = { [weak self] preferences in
            guard let self else { return }
            self.isApplyingSettingsPreferenceChange = true
            self.performUndoableAction("Theme Change") {
                self.store.updatePreferences(preferences)
            }
            self.isApplyingSettingsPreferenceChange = false
        }
        controller.onWindowVisibilityChange = { [weak self] _ in
            self?.updateTabAppearance()
        }
        controller.onResignKeyWhileVisible = { [weak self] in
            _ = self?.dismissSettingsWindowIfVisible()
        }
        controller.updatePreferences(store.preferences)
        settingsWindowController = controller
        updateTabAppearance()
        controller.present(attachedTo: view.window, initialTab: initialTab)
    }

    private func restoreFocusAfterSettingsDismissal() {
        guard let window = view.window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if selectedRowID == nil {
            let firstSelectableRow = rowModels.first(where: \.isSelectable)?.id
            selectedRowID = firstSelectableRow
        }

        if let selectedRowID, currentTab == .tasks {
            activateRow(selectedRowID, placeCaretAtEnd: true)
        } else {
            syncSelectionUI(placeCaretAtEnd: false)
            makeListFirstResponder()
        }
    }

    func resetWindowSize() {
        userPreferredWindowWidth = nil
        userPreferredWindowHeight = nil
        refreshRows(resize: false, animateResize: false, placeCaretAtEnd: false)
        resizeWindow(animate: false)
    }

    func recordUserResizedWindowSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        userPreferredWindowWidth = size.width
        userPreferredWindowHeight = size.height
    }

    func setNativeFullScreenState(active: Bool) {
        nativeFullScreenState = active
        syncToWindowBounds()
        updateHeaderLayoutInsets()
        view.layoutSubtreeIfNeeded()
    }

    func syncToWindowBounds() {
        guard let superview = view.superview else { return }
        let targetBounds = superview.bounds
        if view.frame != targetBounds {
            view.frame = targetBounds
        }
    }

    private func clampedDraftInsertionIndex(_ index: Int) -> Int {
        max(0, min(index, defaultDraftInsertionIndex))
    }

    private func setDraftPosition(_ insertionIndex: Int, text: String? = nil) {
        taskDraft.insertionIndex = clampedDraftInsertionIndex(insertionIndex)
        if let text {
            taskDraft.text = text
        }
    }

    private func resetDraftToDefault() {
        taskDraft = TaskDraftState(insertionIndex: defaultDraftInsertionIndex, text: "")
    }

    private func rowID(afterRemovingDraftAt insertionIndex: Int) -> TodoRowID? {
        if store.items.isEmpty {
            return canShowDraftRow ? .taskDraft : nil
        }

        let targetIndex = max(0, min(insertionIndex, store.items.count - 1))
        return .taskItem(store.items[targetIndex].id)
    }

    private func rowID(beforeRemovingDraftAt insertionIndex: Int) -> TodoRowID? {
        guard !store.items.isEmpty else {
            return canShowDraftRow ? .taskDraft : nil
        }

        let targetIndex = max(0, min(insertionIndex - 1, store.items.count - 1))
        return .taskItem(store.items[targetIndex].id)
    }

    private func collapseSelectedDraftForNavigation(step: Int) -> Bool {
        guard currentTab == .tasks,
              selectedRowID == .taskDraft,
              taskDraft.isEmpty,
              !draftIsAtDefaultPosition else {
            return false
        }

        if step < 0, taskDraft.insertionIndex == 0 {
            return false
        }

        let destinationRowID = step < 0
            ? rowID(beforeRemovingDraftAt: taskDraft.insertionIndex)
            : rowID(afterRemovingDraftAt: taskDraft.insertionIndex)
        resetDraftToDefault()
        selectedRowID = destinationRowID
        clearRangeSelectionState()
        refreshRows(placeCaretAtEnd: true)
        return true
    }

    private func normalizeDraftBeforeStructuralAction() {
        guard currentTab == .tasks else { return }

        if !taskDraft.isEmpty {
            _ = promoteDraftToItem(selectInsertedItem: false)
            return
        }

        guard selectedRowID != .taskDraft, !draftIsAtDefaultPosition else { return }
        resetDraftToDefault()
        refreshRows(placeCaretAtEnd: false)
    }

    @discardableResult
    private func promoteDraftToItem(selectInsertedItem: Bool = true) -> TodoItem? {
        let draftText = taskDraft.trimmedText
        guard canShowDraftRow, !draftText.isEmpty else { return nil }
        let insertionIndex = taskDraft.insertionIndex
        guard let insertedItem = store.insert(draftText, at: insertionIndex) else { return nil }

        resetDraftToDefault()
        if selectInsertedItem {
            selectedRowID = .taskItem(insertedItem.id)
        }
        clearRangeSelectionState()
        refreshRows(placeCaretAtEnd: false)
        return insertedItem
    }

    private func activateDraft(at insertionIndex: Int, placeCaretAtEnd: Bool = true) {
        guard canShowDraftRow else { return }
        setDraftPosition(insertionIndex, text: "")
        selectedRowID = .taskDraft
        clearRangeSelectionState()
        refreshRows(placeCaretAtEnd: placeCaretAtEnd)
    }

    private func convertItemToDraft(_ item: TodoItem, newText: String) {
        guard let itemIndex = store.items.firstIndex(where: { $0.id == item.id }) else { return }
        store.deleteItem(id: item.id)
        setDraftPosition(itemIndex, text: newText)
        selectedRowID = .taskDraft
        clearRangeSelectionState()
        refreshRows(placeCaretAtEnd: false)
    }

    private func targetVisibleRowCount(for tab: Tab? = nil) -> Int {
        switch tab ?? currentTab {
        case .tasks:
            // Keep very small task lists on a stable panel height. The 0/1/2-item
            // transitions are where AppKit's full-size-content resize path was
            // producing the first-row/titlebar overlap bug.
            return max(5, min(store.items.count + 3, TodoStore.maxItems))
        case .archive:
            return max(5, min(store.archivedItems.count + 3, TodoStore.maxItems))
        }
    }

    private func buildRowModels(for tab: Tab? = nil) -> [TodoRowModel] {
        switch tab ?? currentTab {
        case .tasks:
            let showsDraft = canShowDraftRow
            let visibleRowCount = targetVisibleRowCount(for: .tasks)
            let baseRowCount = store.items.count + (showsDraft ? 1 : 0)
            let fillerCount = max(visibleRowCount - baseRowCount, 0)

            var models = store.items.map { item in
                TodoRowModel(
                    id: .taskItem(item.id),
                    kind: .taskItem(item),
                    text: item.text,
                    isDone: false,
                    isEditable: true,
                    isSelectable: true,
                    canComplete: true,
                    canDrag: true,
                    circleOpacity: 0.40,
                    textOpacity: 0.90,
                    showsStrikethrough: false
                )
            }

            if showsDraft {
                let draftModel = TodoRowModel(
                    id: .taskDraft,
                    kind: .taskDraft,
                    text: taskDraft.text,
                    isDone: false,
                    isEditable: true,
                    isSelectable: true,
                    canComplete: false,
                    canDrag: false,
                    circleOpacity: fillerCount > 0 ? fadeOpacity(emptyIndex: 0, emptyCount: fillerCount + 1) : 0.30,
                    textOpacity: 0.92,
                    showsStrikethrough: false
                )
                let insertionIndex = clampedDraftInsertionIndex(taskDraft.insertionIndex)
                models.insert(draftModel, at: min(insertionIndex, models.count))
            }

            if fillerCount > 0 {
                for fillerIndex in 0..<fillerCount {
                    models.append(
                        TodoRowModel(
                            id: .taskFiller(fillerIndex + 1),
                            kind: .filler,
                            text: "",
                            isDone: false,
                            isEditable: false,
                            isSelectable: false,
                            canComplete: false,
                            canDrag: false,
                            circleOpacity: fadeOpacity(emptyIndex: fillerIndex, emptyCount: fillerCount),
                            textOpacity: 0.0,
                            showsStrikethrough: false
                        )
                    )
                }
            }

            return models

        case .archive:
            let visibleRowCount = targetVisibleRowCount(for: .archive)
            var models = store.archivedItems.map { item in
                TodoRowModel(
                    id: .archiveItem(item.id),
                    kind: .archiveItem(item),
                    text: item.text,
                    isDone: true,
                    isEditable: false,
                    isSelectable: true,
                    canComplete: true,
                    canDrag: false,
                    circleOpacity: 0.38,
                    textOpacity: 0.38,
                    showsStrikethrough: true
                )
            }

            let fillerCount = visibleRowCount - store.archivedItems.count
            if fillerCount > 0 {
                for fillerIndex in 0..<fillerCount {
                    models.append(
                        TodoRowModel(
                            id: .archiveFiller(fillerIndex),
                            kind: .filler,
                            text: "",
                            isDone: false,
                            isEditable: false,
                            isSelectable: false,
                            canComplete: false,
                            canDrag: false,
                            circleOpacity: fadeOpacity(emptyIndex: fillerIndex, emptyCount: fillerCount),
                            textOpacity: 0.0,
                            showsStrikethrough: false
                        )
                    )
                }
            }

            return models
        }
    }

    private func refreshRows(
        preferences: AppPreferences? = nil,
        resize: Bool = true,
        animateResize: Bool = true,
        animatedLayout: Bool = false,
        animatedLayoutDuration: CFTimeInterval? = nil,
        selectionRevealRowID: TodoRowID? = nil,
        placeCaretAtEnd: Bool = true
    ) {
        let resolvedPreferences = preferences ?? store.preferences
        let previousRowCount = rowModels.count
        // Preserve explicit empty draft placement across ordinary redraws.
        // Keyboard navigation intentionally creates valid drafts above/between
        // tasks, and generic refresh must not snap those back to the default
        // bottom slot.
        rowModels = buildRowModels()
        ensureSelectedRowExists()
        listView.apply(
            models: rowModels,
            selectedRowID: selectedRowID,
            selectedRowIDs: selectedRowIDs,
            editingRowID: currentEditingRowID,
            preferences: resolvedPreferences,
            animatedLayout: animatedLayout,
            animatedLayoutDuration: animatedLayoutDuration,
            selectionRevealRowID: selectionRevealRowID
        )

        if resize {
            resizeWindow(animate: animateResize && shouldAnimateWindowResize(from: previousRowCount, to: rowModels.count))
        }

        updateHeaderLayoutInsets()
        view.layoutSubtreeIfNeeded()
        listView.layoutSubtreeIfNeeded()
        listView.scrollRowToVisible(selectedRowID)
        attachEditorIfNeeded(placeCaretAtEnd: placeCaretAtEnd)
    }

    private func shouldAnimateWindowResize(from previousRowCount: Int, to newRowCount: Int) -> Bool {
        guard currentTab == .tasks else { return true }
        return max(previousRowCount, newRowCount) > 5
    }

    private func fadeOpacity(emptyIndex: Int, emptyCount: Int) -> Double {
        let fromEnd = emptyCount - 1 - emptyIndex
        switch fromEnd {
        case 0: return 0.10
        case 1: return 0.20
        default: return 0.30
        }
    }

    private func ensureSelectedRowExists() {
        guard let selectedRowID else {
            self.selectedRowID = buildSelectionID(in: rowModels, selectableIndex: 0)
            clearRangeSelectionState()
            return
        }

        guard rowModels.contains(where: { $0.id == selectedRowID && $0.isSelectable }) else {
            self.selectedRowID = buildSelectionID(in: rowModels, selectableIndex: 0)
            clearRangeSelectionState()
            return
        }

        guard isRangeSelectionActive else { return }
        let validBatchIDs = Set(batchSelectableRowIDs(in: rowModels))
        selectedRowIDs = selectedRowIDs.intersection(validBatchIDs)
        if selectedRowIDs.isEmpty {
            selectionAnchorRowID = nil
            return
        }

        if let selectionAnchorRowID, !selectedRowIDs.contains(selectionAnchorRowID) {
            self.selectionAnchorRowID = selectedRowID
        }
    }

    private func buildSelectionID(in models: [TodoRowModel], selectableIndex: Int) -> TodoRowID? {
        let selectableRows = models.filter(\.isSelectable)
        guard !selectableRows.isEmpty else { return nil }
        let clampedIndex = max(0, min(selectableIndex, selectableRows.count - 1))
        return selectableRows[clampedIndex].id
    }

    private func clearRangeSelectionState() {
        selectedRowIDs.removeAll()
        selectionAnchorRowID = nil
    }

    private func clearRangeSelection(placeCaretAtEnd: Bool) {
        guard isRangeSelectionActive else { return }
        clearRangeSelectionState()
        syncSelectionUI(placeCaretAtEnd: placeCaretAtEnd)
    }

    private func batchSelectableRowIDs(in models: [TodoRowModel]? = nil) -> [TodoRowID] {
        let source = models ?? rowModels
        return source.compactMap { model in
            switch model.kind {
            case .taskItem where currentTab == .tasks:
                return model.id
            case .archiveItem where currentTab == .archive:
                return model.id
            default:
                return nil
            }
        }
    }

    private func navigationSelectableRowIDs(in models: [TodoRowModel]? = nil) -> [TodoRowID] {
        let source = models ?? rowModels
        return source.compactMap { model in
            switch model.kind {
            case .taskItem where currentTab == .tasks:
                return model.id
            case .taskDraft where currentTab == .tasks:
                let shouldIncludeDraft = !draftIsAtDefaultPosition || !taskDraft.isEmpty || store.items.isEmpty
                return shouldIncludeDraft ? model.id : nil
            case .archiveItem where currentTab == .archive:
                return model.id
            default:
                return nil
            }
        }
    }

    private func batchSelectionIndex(for rowID: TodoRowID?, in models: [TodoRowModel]? = nil) -> Int? {
        guard let rowID else { return nil }
        return batchSelectableRowIDs(in: models).firstIndex(of: rowID)
    }

    private func taskSelectionIDAfterMutation(in models: [TodoRowModel], taskIndex: Int) -> TodoRowID? {
        let taskRows = batchSelectableRowIDs(in: models)
        if !taskRows.isEmpty {
            let clampedIndex = max(0, min(taskIndex, taskRows.count - 1))
            return taskRows[clampedIndex]
        }

        return models.contains(where: { $0.id == .taskDraft && $0.isSelectable }) ? .taskDraft : nil
    }

    private func selectedBatchRowIDs() -> [TodoRowID] {
        let orderedBatchRows = batchSelectableRowIDs()
        if isRangeSelectionActive {
            return orderedBatchRows.filter { selectedRowIDs.contains($0) }
        }
        guard let selectedRowID, orderedBatchRows.contains(selectedRowID) else { return [] }
        return [selectedRowID]
    }

    private func extendSelection(step: Int) {
        guard !isAnimating, !listView.isBusy else { return }

        let orderedBatchRows = batchSelectableRowIDs()
        guard !orderedBatchRows.isEmpty else { return }
        guard let selectedRowID, let currentIndex = orderedBatchRows.firstIndex(of: selectedRowID) else { return }

        let nextIndex = max(0, min(currentIndex + step, orderedBatchRows.count - 1))
        guard nextIndex != currentIndex || !isRangeSelectionActive else { return }

        if !isRangeSelectionActive {
            selectionAnchorRowID = selectedRowID
            selectedRowIDs = [selectedRowID]
        }

        let anchorID = selectionAnchorRowID ?? selectedRowID
        guard let anchorIndex = orderedBatchRows.firstIndex(of: anchorID) else { return }

        self.selectedRowID = orderedBatchRows[nextIndex]
        let lowerBound = min(anchorIndex, nextIndex)
        let upperBound = max(anchorIndex, nextIndex)
        selectedRowIDs = Set(orderedBatchRows[lowerBound...upperBound])
        syncSelectionUI(placeCaretAtEnd: false)
    }

    private func extendSelection(to destination: BoundaryDestination) {
        guard !isAnimating, !listView.isBusy else { return }

        let orderedBatchRows = batchSelectableRowIDs()
        guard !orderedBatchRows.isEmpty else { return }
        guard let selectedRowID,
              orderedBatchRows.contains(selectedRowID) else { return }

        if !isRangeSelectionActive {
            selectionAnchorRowID = selectedRowID
            selectedRowIDs = [selectedRowID]
        }

        let anchorID = selectionAnchorRowID ?? selectedRowID
        guard let anchorIndex = orderedBatchRows.firstIndex(of: anchorID) else { return }

        let targetIndex = destination == .top ? 0 : (orderedBatchRows.count - 1)
        self.selectedRowID = orderedBatchRows[targetIndex]

        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        selectedRowIDs = Set(orderedBatchRows[lowerBound...upperBound])
        syncSelectionUI(placeCaretAtEnd: false)
    }

    private func extendSelection(to rowID: TodoRowID) {
        guard !isAnimating, !listView.isBusy else { return }

        let orderedBatchRows = batchSelectableRowIDs()
        guard !orderedBatchRows.isEmpty,
              let targetIndex = orderedBatchRows.firstIndex(of: rowID) else {
            activateRow(rowID, placeCaretAtEnd: false)
            return
        }

        guard let anchorID = selectedRowID,
              let anchorIndex = orderedBatchRows.firstIndex(of: anchorID) else {
            activateRow(rowID, placeCaretAtEnd: false)
            return
        }

        guard targetIndex != anchorIndex || isRangeSelectionActive else {
            syncSelectionUI(placeCaretAtEnd: false)
            return
        }

        selectionAnchorRowID = anchorID
        self.selectedRowID = rowID
        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        selectedRowIDs = Set(orderedBatchRows[lowerBound...upperBound])
        syncSelectionUI(placeCaretAtEnd: false)
    }

    private func toggleSelection(for rowID: TodoRowID) {
        guard !isAnimating, !listView.isBusy else { return }

        let orderedBatchRows = batchSelectableRowIDs()
        guard orderedBatchRows.contains(rowID) else {
            activateRow(rowID, placeCaretAtEnd: false)
            return
        }

        var nextSelectedRowIDs = Set(selectedBatchRowIDs())
        if nextSelectedRowIDs.contains(rowID) {
            if nextSelectedRowIDs.count == 1 {
                clearRangeSelectionState()
                selectedRowID = rowID
                syncSelectionUI(placeCaretAtEnd: false)
                return
            }
            nextSelectedRowIDs.remove(rowID)
        } else {
            if nextSelectedRowIDs.isEmpty, let selectedRowID, orderedBatchRows.contains(selectedRowID) {
                nextSelectedRowIDs.insert(selectedRowID)
            }
            nextSelectedRowIDs.insert(rowID)
        }

        if nextSelectedRowIDs.count == 1, let remainingRowID = nextSelectedRowIDs.first {
            clearRangeSelectionState()
            selectedRowID = remainingRowID
            syncSelectionUI(placeCaretAtEnd: false)
            return
        }

        selectedRowIDs = nextSelectedRowIDs
        selectionAnchorRowID = nil

        if nextSelectedRowIDs.contains(rowID) {
            selectedRowID = rowID
        } else if let selectedRowID, nextSelectedRowIDs.contains(selectedRowID) {
            self.selectedRowID = selectedRowID
        } else {
            selectedRowID = orderedBatchRows.first(where: { nextSelectedRowIDs.contains($0) })
        }

        syncSelectionUI(placeCaretAtEnd: false)
    }

    private enum BoundaryDestination {
        case top
        case bottom
    }

    private func jumpToBoundary(_ destination: BoundaryDestination) {
        guard !isAnimating, !listView.isBusy else { return }
        let navigableRows = navigationSelectableRowIDs()
        guard !navigableRows.isEmpty else { return }
        let targetRowID = destination == .top ? navigableRows.first : navigableRows.last
        if let targetRowID {
            activateRow(targetRowID, placeCaretAtEnd: true)
        }
    }

    private func activateRow(_ rowID: TodoRowID, placeCaretAtEnd: Bool = true) {
        guard rowModels.contains(where: { $0.id == rowID && $0.isSelectable }) else { return }
        cancelDeferredEditorActivation()
        clearRangeSelectionState()
        selectedRowID = rowID
        syncSelectionUI(placeCaretAtEnd: placeCaretAtEnd)
    }

    private func syncSelectionUI(placeCaretAtEnd: Bool) {
        listView.updateInteractionState(
            selectedRowID: selectedRowID,
            selectedRowIDs: selectedRowIDs,
            editingRowID: currentEditingRowID
        )
        listView.layoutSubtreeIfNeeded()
        listView.scrollRowToVisible(selectedRowID)
        attachEditorIfNeeded(placeCaretAtEnd: placeCaretAtEnd)
    }

    private func captureUndoSnapshot() -> TodoUndoSnapshot {
        TodoUndoSnapshot(
            items: store.items,
            archivedItems: store.archivedItems,
            preferences: store.preferences,
            currentTab: currentTab,
            selectedRowID: selectedRowID,
            selectionAnchorRowID: selectionAnchorRowID,
            selectedRowIDs: selectedRowIDs,
            taskDraft: taskDraft
        )
    }

    private func restoreUndoSnapshot(_ snapshot: TodoUndoSnapshot) {
        let previousTaskIDs = Set(store.items.map(\.id))
        let previousArchivedIDs = Set(store.archivedItems.map(\.id))
        let restoredTaskRowIDs = snapshot.items.compactMap { item -> TodoRowID? in
            guard !previousTaskIDs.contains(item.id), previousArchivedIDs.contains(item.id) else { return nil }
            return .taskItem(item.id)
        }

        cancelDeferredEditorActivation()
        isAnimating = false
        detachEditor(makeListFirstResponder: false)

        store.restoreState(
            items: snapshot.items,
            archivedItems: snapshot.archivedItems,
            preferences: snapshot.preferences
        )
        currentTab = snapshot.currentTab
        selectedRowID = snapshot.selectedRowID
        selectionAnchorRowID = snapshot.selectionAnchorRowID
        selectedRowIDs = snapshot.selectedRowIDs
        taskDraft = snapshot.taskDraft

        updateTabAppearance()
        if currentTab == .tasks, !restoredTaskRowIDs.isEmpty {
            isAnimating = true
            refreshRows(
                animateResize: false,
                animatedLayout: true,
                animatedLayoutDuration: motion.collapse,
                placeCaretAtEnd: false
            )
            animateRestoredTasks(restoredTaskRowIDs)
        } else {
            refreshRows(animateResize: false, placeCaretAtEnd: true)
        }
    }

    private func registerUndoSnapshot(_ snapshot: TodoUndoSnapshot, actionName: String) {
        historyManager.registerUndo(withTarget: self) { target in
            let redoSnapshot = target.captureUndoSnapshot()
            target.restoreUndoSnapshot(snapshot)
            target.registerUndoSnapshot(redoSnapshot, actionName: actionName)
        }
        historyManager.setActionName(actionName)
    }

    private func registerUndoSnapshotIfChanged(_ snapshot: TodoUndoSnapshot, actionName: String) {
        guard captureUndoSnapshot() != snapshot else { return }
        registerUndoSnapshot(snapshot, actionName: actionName)
    }

    private func performUndoableAction(_ actionName: String, _ action: () -> Void) {
        let snapshot = captureUndoSnapshot()
        action()
        registerUndoSnapshotIfChanged(snapshot, actionName: actionName)
    }

    func performUndo() -> Bool {
        guard !isAnimating, !listView.isBusy else { return false }
        if performTextEditingUndo(isRedo: false) {
            return true
        }
        guard historyManager.canUndo else { return false }
        historyManager.undo()
        return true
    }

    func performRedo() -> Bool {
        guard !isAnimating, !listView.isBusy else { return false }
        if performTextEditingUndo(isRedo: true) {
            return true
        }
        guard historyManager.canRedo else { return false }
        historyManager.redo()
        return true
    }

    private func performTextEditingUndo(isRedo: Bool) -> Bool {
        guard editorRowID != nil, let editor = activeTextEditor(), let undoManager = editor.undoManager else {
            return false
        }

        let canReplayChange = isRedo ? undoManager.canRedo : undoManager.canUndo
        guard canReplayChange else { return false }

        if isRedo {
            undoManager.redo()
        } else {
            undoManager.undo()
        }
        syncVisibleEditorState()
        return true
    }

    private func refreshVisibleModel(for rowID: TodoRowID) {
        guard let index = rowModels.firstIndex(where: { $0.id == rowID }),
              let updatedModel = latestVisibleModel(for: rowID) else { return }
        rowModels[index] = updatedModel
        listView.updateModel(updatedModel)
    }

    private func latestVisibleModel(for rowID: TodoRowID) -> TodoRowModel? {
        switch rowID {
        case .taskItem(let itemID):
            guard let item = store.items.first(where: { $0.id == itemID }) else { return nil }
            return TodoRowModel(
                id: .taskItem(item.id),
                kind: .taskItem(item),
                text: item.text,
                isDone: false,
                isEditable: true,
                isSelectable: true,
                canComplete: true,
                canDrag: true,
                circleOpacity: 0.40,
                textOpacity: 0.90,
                showsStrikethrough: false
            )

        case .archiveItem(let itemID):
            guard let item = store.archivedItems.first(where: { $0.id == itemID }) else { return nil }
            return TodoRowModel(
                id: .archiveItem(item.id),
                kind: .archiveItem(item),
                text: item.text,
                isDone: true,
                isEditable: false,
                isSelectable: true,
                canComplete: true,
                canDrag: false,
                circleOpacity: 0.38,
                textOpacity: 0.38,
                showsStrikethrough: true
            )

        case .taskDraft:
            guard let existingModel = rowModels.first(where: { $0.id == .taskDraft }) else { return nil }
            return TodoRowModel(
                id: .taskDraft,
                kind: .taskDraft,
                text: taskDraft.text,
                isDone: false,
                isEditable: true,
                isSelectable: true,
                canComplete: false,
                canDrag: false,
                circleOpacity: existingModel.circleOpacity,
                textOpacity: existingModel.textOpacity,
                showsStrikethrough: false
            )

        case .taskFiller, .archiveFiller:
            return rowModels.first(where: { $0.id == rowID })
        }
    }

    private func attachEditorIfNeeded(placeCaretAtEnd: Bool) {
        guard let rowID = currentEditingRowID else {
            detachEditor(makeListFirstResponder: true)
            return
        }

        let targetText = textForRow(rowID)
        let shouldResetEditorUndoHistory = editorRowID != rowID || sharedEditor.stringValue != targetText
        if editorRowID != rowID {
            sharedEditor.stringValue = targetText
            editorRowID = rowID
        } else if sharedEditor.stringValue != targetText {
            sharedEditor.stringValue = targetText
        }

        guard let window = view.window else { return }
        if window.firstResponder !== sharedEditor.currentEditor() {
            window.makeFirstResponder(sharedEditor)
        }

        bindHiddenEditor(placeCaretAtEnd: placeCaretAtEnd, resetUndoHistory: shouldResetEditorUndoHistory)
    }

    private func cancelDeferredEditorActivation() {
        deferredEditorActivationWorkItem?.cancel()
        deferredEditorActivationWorkItem = nil
        deferredEditorRowID = nil
    }

    private func scheduleDeferredEditorActivation(for rowID: TodoRowID?, delay: TimeInterval) {
        cancelDeferredEditorActivation()
        guard let rowID else { return }

        deferredEditorRowID = rowID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.selectedRowID == rowID, self.deferredEditorRowID == rowID else { return }

            self.deferredEditorRowID = nil
            self.deferredEditorActivationWorkItem = nil
            self.syncSelectionUI(placeCaretAtEnd: true)
        }

        deferredEditorActivationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func detachEditor(makeListFirstResponder shouldFocusList: Bool) {
        guard editorRowID != nil else {
            if shouldFocusList {
                makeListFirstResponder()
            }
            return
        }

        resetTextEditorUndoHistory()
        editorRowID = nil
        listView.updateEditingPresentation(rowID: nil, text: nil, selectionRange: nil)
        if let observer = editorSelectionObserver {
            NotificationCenter.default.removeObserver(observer)
            editorSelectionObserver = nil
        }
        if shouldFocusList {
            makeListFirstResponder()
        }
    }

    private func bindHiddenEditor(placeCaretAtEnd: Bool, resetUndoHistory: Bool = false) {
        if let observer = editorSelectionObserver {
            NotificationCenter.default.removeObserver(observer)
            editorSelectionObserver = nil
        }

        let applyBinding = { [weak self] in
            guard let self else { return }
            if let editor = self.activeTextEditor() {
                self.editorSelectionObserver = NotificationCenter.default.addObserver(
                    forName: NSTextView.didChangeSelectionNotification,
                    object: editor,
                    queue: .main
                ) { [weak self] _ in
                    self?.syncVisibleEditorState()
                }

                if resetUndoHistory {
                    editor.resetUndoHistory()
                }
                if placeCaretAtEnd {
                    editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
                }
            } else if placeCaretAtEnd {
                self.moveCaretToEnd()
            }

            self.syncVisibleEditorState()
        }

        if sharedEditor.currentEditor() == nil {
            DispatchQueue.main.async(execute: applyBinding)
        } else {
            applyBinding()
        }
    }

    private func syncVisibleEditorState() {
        guard let rowID = editorRowID else {
            listView.updateEditingPresentation(rowID: nil, text: nil, selectionRange: nil)
            return
        }

        let selectionRange: NSRange
        if let editor = sharedEditor.currentEditor() as? NSTextView {
            selectionRange = editor.selectedRange()
        } else {
            selectionRange = NSRange(location: sharedEditor.stringValue.count, length: 0)
        }

        listView.updateEditingPresentation(
            rowID: rowID,
            text: sharedEditor.stringValue,
            selectionRange: selectionRange
        )
    }

    private func makeListFirstResponder() {
        guard let window = view.window else { return }
        window.makeFirstResponder(listView)
    }

    private func activeTextEditor() -> CaretEndFieldEditor? {
        if let editor = sharedEditor.currentEditor() as? CaretEndFieldEditor {
            return editor
        }
        return view.window?.fieldEditor(false, for: sharedEditor) as? CaretEndFieldEditor
    }

    private func resetTextEditorUndoHistory() {
        activeTextEditor()?.resetUndoHistory()
    }

    private func moveCaretToEnd() {
        if let editor = sharedEditor.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.sharedEditor.currentEditor() as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
    }

    private func resetHiddenEditorText(to text: String) {
        sharedEditor.stringValue = text
        if let editor = sharedEditor.currentEditor() as? NSTextView {
            editor.string = text
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
        syncVisibleEditorState()
    }

    private func textForRow(_ rowID: TodoRowID) -> String {
        rowModels.first(where: { $0.id == rowID })?.text ?? ""
    }

    private func handleCommandSelectAll() {
        guard eventBelongsToPanelEditorContext() else { return }
        guard let rowID = currentEditingRowID else { return }

        if editorRowID != rowID {
            sharedEditor.stringValue = textForRow(rowID)
            editorRowID = rowID
        }

        guard let window = view.window else { return }
        if window.firstResponder !== sharedEditor.currentEditor() {
            window.makeFirstResponder(sharedEditor)
        }

        bindHiddenEditor(placeCaretAtEnd: false)

        if let editor = activeTextEditor() {
            editor.selectAll(nil)
            syncVisibleEditorState()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.editorRowID == rowID,
                  let editor = self.activeTextEditor() else { return }
            editor.selectAll(nil)
            self.syncVisibleEditorState()
        }
    }

    private func eventBelongsToPanelEditorContext() -> Bool {
        guard let window = view.window else { return false }
        guard window.isKeyWindow else { return false }
        return NSApp.keyWindow === window
    }

    private func handleCommandReturn() {
        cancelDeferredEditorActivation()
        let selectedBatchRows = selectedBatchRowIDs()
        if isRangeSelectionActive, !selectedBatchRows.isEmpty {
            switch currentTab {
            case .tasks:
                let taskRowIDs = batchSelectableRowIDs()
                let selectionIndex = selectedBatchRows.compactMap { taskRowIDs.firstIndex(of: $0) }.min() ?? 0
                animateBatchCompletion(
                    for: selectedBatchRows,
                    selectionIndex: selectionIndex,
                    undoSnapshot: captureUndoSnapshot()
                )

            case .archive:
                restoreArchiveSelection(rowIDs: selectedBatchRows)
            }
            return
        }

        guard let selectedModel else { return }

        switch currentTab {
        case .tasks:
            switch selectedModel.kind {
            case .taskItem(let item):
                animateCompletion(for: item.id, undoSnapshot: captureUndoSnapshot())

            case .taskDraft:
                let undoSnapshot = captureUndoSnapshot()
                guard let insertedItem = promoteDraftToItem(selectInsertedItem: true) else { return }
                animateCompletion(for: insertedItem.id, undoSnapshot: undoSnapshot)

            case .archiveItem, .filler:
                return
            }

        case .archive:
            restoreArchiveSelection()
        }
    }

    private func handleCommandDelete() {
        cancelDeferredEditorActivation()
        let selectedBatchRows = selectedBatchRowIDs()
        if isRangeSelectionActive, !selectedBatchRows.isEmpty {
            switch currentTab {
            case .tasks:
                performUndoableAction("Delete") {
                    let taskRowIDs = batchSelectableRowIDs()
                    let selectionIndex = selectedBatchRows.compactMap { taskRowIDs.firstIndex(of: $0) }.min() ?? 0
                    let itemIDs = selectedBatchRows.compactMap { rowID -> UUID? in
                        guard case .taskItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return nil }
                        return item.id
                    }
                    guard !itemIDs.isEmpty else { return }
                    detachEditor(makeListFirstResponder: false)
                    itemIDs.forEach { store.deleteItem(id: $0) }
                    clearRangeSelectionState()
                    let updatedModels = buildRowModels(for: .tasks)
                    selectedRowID = taskSelectionIDAfterMutation(in: updatedModels, taskIndex: selectionIndex)
                    refreshRows()
                }

            case .archive:
                permanentlyDeleteArchiveSelection(rowIDs: selectedBatchRows)
            }
            return
        }

        guard let selectedModel else { return }

        switch currentTab {
        case .tasks:
            performUndoableAction("Delete") {
                guard case .taskItem(let item) = selectedModel.kind else { return }
                let selectionIndex = batchSelectionIndex(for: selectedRowID) ?? 0
                store.deleteItem(id: item.id)
                let updatedModels = buildRowModels(for: .tasks)
                selectedRowID = taskSelectionIDAfterMutation(in: updatedModels, taskIndex: selectionIndex)
                refreshRows()
            }

        case .archive:
            permanentlyDeleteArchiveSelection()
        }
    }

    private func archiveItemIDs(for rowIDs: [TodoRowID]) -> [UUID] {
        rowIDs.compactMap { rowID -> UUID? in
            guard case .archiveItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return nil }
            return item.id
        }
    }

    private func archiveSelectionIndex(for rowIDs: [TodoRowID]) -> Int {
        let selectableRowIDs = rowModels.filter(\.isSelectable).map(\.id)
        return rowIDs.compactMap { selectableRowIDs.firstIndex(of: $0) }.min() ?? 0
    }

    private func applyArchivePermanentDelete(to rowIDs: [TodoRowID]) {
        let itemIDs = archiveItemIDs(for: rowIDs)
        guard !itemIDs.isEmpty else { return }

        let selectionIndex = archiveSelectionIndex(for: rowIDs)
        itemIDs.forEach { store.deleteArchived(id: $0) }
        clearRangeSelectionState()
        let updatedModels = buildRowModels(for: .archive)
        selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
        refreshRows()
    }

    private func restoreArchiveSelection(rowIDs: [TodoRowID]? = nil) {
        let targetRowIDs = rowIDs ?? selectedBatchRowIDs()
        guard !targetRowIDs.isEmpty else { return }
        animateArchiveRestore(for: targetRowIDs, undoSnapshot: captureUndoSnapshot())
    }

    private func permanentlyDeleteArchiveSelection(rowIDs: [TodoRowID]? = nil) {
        let targetRowIDs = rowIDs ?? selectedBatchRowIDs()
        guard !targetRowIDs.isEmpty else { return }
        performUndoableAction("Permanently Delete") {
            self.applyArchivePermanentDelete(to: targetRowIDs)
        }
    }

    @objc private func restoreArchiveSelectionFromContextMenu(_ sender: Any?) {
        restoreArchiveSelection()
    }

    @objc private func permanentlyDeleteArchiveSelectionFromContextMenu(_ sender: Any?) {
        permanentlyDeleteArchiveSelection()
    }

    private func animateCompletion(for itemID: UUID, undoSnapshot: TodoUndoSnapshot) {
        guard !isAnimating, !listView.isBusy else { return }
        let taskRowID = TodoRowID.taskItem(itemID)
        guard let selectionIndex = batchSelectionIndex(for: taskRowID),
              let row = listView.rowView(for: taskRowID) else { return }

        isAnimating = true
        detachEditor(makeListFirstResponder: false)
        row.setEditing(false)

        row.playCompletionAnimation(motion: motion) { [weak self] in
            guard let self else { return }
            self.store.archive(id: itemID)
            let updatedModels = self.buildRowModels(for: .tasks)
            self.selectedRowID = self.taskSelectionIDAfterMutation(in: updatedModels, taskIndex: selectionIndex)
            self.isAnimating = false
            self.scheduleDeferredEditorActivation(for: self.selectedRowID, delay: self.motion.collapse * 0.75)
            self.refreshRows(
                animatedLayout: true,
                animatedLayoutDuration: self.motion.collapse,
                selectionRevealRowID: self.selectedRowID,
                placeCaretAtEnd: false
            )
            self.registerUndoSnapshotIfChanged(undoSnapshot, actionName: "Complete")
        }
    }

    private func animateBatchCompletion(for rowIDs: [TodoRowID], selectionIndex: Int, undoSnapshot: TodoUndoSnapshot) {
        guard !isAnimating, !listView.isBusy else { return }

        let itemIDs = rowIDs.compactMap { rowID -> UUID? in
            guard case .taskItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return nil }
            return item.id
        }
        guard !itemIDs.isEmpty else { return }

        let rows = rowIDs.compactMap { listView.rowView(for: $0) }
        let completeArchiveAndRefresh = { [weak self] in
            guard let self else { return }
            itemIDs.forEach { self.store.archive(id: $0) }
            self.clearRangeSelectionState()
            let updatedModels = self.buildRowModels(for: .tasks)
            self.selectedRowID = self.taskSelectionIDAfterMutation(in: updatedModels, taskIndex: selectionIndex)
            self.isAnimating = false
            self.scheduleDeferredEditorActivation(for: self.selectedRowID, delay: self.motion.collapse * 0.75)
            self.refreshRows(
                animatedLayout: true,
                animatedLayoutDuration: self.motion.collapse,
                selectionRevealRowID: self.selectedRowID,
                placeCaretAtEnd: false
            )
            self.registerUndoSnapshotIfChanged(undoSnapshot, actionName: "Complete")
        }

        guard !rows.isEmpty else {
            detachEditor(makeListFirstResponder: false)
            isAnimating = true
            completeArchiveAndRefresh()
            return
        }

        isAnimating = true
        detachEditor(makeListFirstResponder: false)

        let animationGroup = DispatchGroup()
        rows.forEach { row in
            row.setEditing(false)
            animationGroup.enter()
            row.playCompletionAnimation(motion: motion) {
                animationGroup.leave()
            }
        }

        animationGroup.notify(queue: .main) {
            completeArchiveAndRefresh()
        }
    }

    private func animateArchiveRestore(for rowIDs: [TodoRowID], undoSnapshot: TodoUndoSnapshot) {
        guard !isAnimating, !listView.isBusy else { return }

        let itemIDs = archiveItemIDs(for: rowIDs)
        guard !itemIDs.isEmpty else { return }

        let archiveSelectionIndex = archiveSelectionIndex(for: rowIDs)
        let rows = rowIDs.compactMap { listView.rowView(for: $0) }
        let finishRestoreAndRefresh = { [weak self] in
            guard let self else { return }
            itemIDs.forEach { self.store.restore(id: $0) }
            self.clearRangeSelectionState()
            if self.taskDraft.isEmpty {
                self.taskDraft.insertionIndex = self.defaultDraftInsertionIndex
            }
            let updatedModels = self.buildRowModels(for: .archive)
            self.selectedRowID = self.buildSelectionID(in: updatedModels, selectableIndex: archiveSelectionIndex)
            self.isAnimating = false
            self.updateTabAppearance()
            self.updateListScrollBehavior()
            self.refreshRows(
                animateResize: true,
                animatedLayout: true,
                animatedLayoutDuration: self.motion.collapse,
                selectionRevealRowID: self.selectedRowID,
                placeCaretAtEnd: false
            )
            self.registerUndoSnapshotIfChanged(undoSnapshot, actionName: "Restore")
        }

        guard !rows.isEmpty else {
            isAnimating = true
            finishRestoreAndRefresh()
            return
        }

        isAnimating = true
        let animationGroup = DispatchGroup()
        rows.forEach { row in
            row.setEditing(false)
            animationGroup.enter()
            row.playRestoreAnimation(motion: motion, restoreModelAppearanceOnCompletion: false) {
                animationGroup.leave()
            }
        }

        animationGroup.notify(queue: .main) {
            let removalGroup = DispatchGroup()
            rowIDs.forEach { rowID in
                removalGroup.enter()
                self.listView.animateRemoval(of: rowID, duration: self.motion.collapse) {
                    removalGroup.leave()
                }
            }

            removalGroup.notify(queue: .main) {
                finishRestoreAndRefresh()
            }
        }
    }

    private func animateRestoredTasks(_ rowIDs: [TodoRowID]) {
        let rows = rowIDs.compactMap { listView.rowView(for: $0) }
        guard !rows.isEmpty else {
            isAnimating = false
            syncSelectionUI(placeCaretAtEnd: true)
            return
        }

        let animationGroup = DispatchGroup()
        rows.forEach { row in
            row.setEditing(false)
            animationGroup.enter()
            row.playRestoreAnimation(motion: motion) {
                animationGroup.leave()
            }
        }

        animationGroup.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isAnimating = false
            self.syncSelectionUI(placeCaretAtEnd: true)
        }
    }

    @discardableResult
    func moveUp() -> Bool {
        guard !isAnimating, !listView.isBusy else { return false }
        let collapsedRangeSelection = isRangeSelectionActive
        if collapsedRangeSelection {
            clearRangeSelectionState()
        }
        if currentTab == .tasks {
            if collapseSelectedDraftForNavigation(step: -1) {
                return true
            }

            if case .taskItem(let item)? = selectedModel?.kind,
               let itemIndex = store.items.firstIndex(where: { $0.id == item.id }),
               itemIndex == 0,
               canShowDraftRow {
                // Top-edge up-arrow enters an empty draft above the first task.
                // This is an explicit interaction contract and must never wrap
                // to the default bottom draft.
                activateDraft(at: 0)
                return true
            }
        }

        let navigationRows = navigationSelectableRowIDs()
        guard !navigationRows.isEmpty else {
            if collapsedRangeSelection {
                syncSelectionUI(placeCaretAtEnd: true)
            }
            return false
        }

        if currentTab == .tasks, selectedRowID == .taskDraft, draftIsAtDefaultPosition {
            if let targetRowID = navigationRows.last {
                activateRow(targetRowID, placeCaretAtEnd: true)
                return true
            }
            if collapsedRangeSelection {
                syncSelectionUI(placeCaretAtEnd: true)
            }
            return false
        }

        guard let selectedRowID,
              let currentIndex = navigationRows.firstIndex(of: selectedRowID),
              currentIndex > 0 else {
            if collapsedRangeSelection {
                syncSelectionUI(placeCaretAtEnd: true)
            }
            return false
        }
        activateRow(navigationRows[currentIndex - 1], placeCaretAtEnd: true)
        return true
    }

    @discardableResult
    func moveDown() -> Bool {
        guard !isAnimating, !listView.isBusy else { return false }
        let collapsedRangeSelection = isRangeSelectionActive
        if collapsedRangeSelection {
            clearRangeSelectionState()
        }
        if currentTab == .tasks, collapseSelectedDraftForNavigation(step: 1) {
            return true
        }

        if currentTab == .tasks,
           case .taskItem(let item)? = selectedModel?.kind,
           let itemIndex = store.items.firstIndex(where: { $0.id == item.id }),
           itemIndex == store.items.count - 1,
           canShowDraftRow {
            activateDraft(at: defaultDraftInsertionIndex)
            return true
        }

        let navigationRows = navigationSelectableRowIDs()
        guard !navigationRows.isEmpty else {
            if collapsedRangeSelection {
                syncSelectionUI(placeCaretAtEnd: true)
            }
            return false
        }
        guard let selectedRowID,
              let currentIndex = navigationRows.firstIndex(of: selectedRowID),
              currentIndex < navigationRows.count - 1 else {
            if collapsedRangeSelection {
                syncSelectionUI(placeCaretAtEnd: true)
            }
            return false
        }
        activateRow(navigationRows[currentIndex + 1], placeCaretAtEnd: true)
        return true
    }

    func submitRow() {
        guard !isAnimating, !listView.isBusy, currentTab == .tasks else { return }
        guard let selectedModel else { return }

        performUndoableAction("Insert Row") {
            switch selectedModel.kind {
            case .taskItem(let item):
                normalizeDraftBeforeStructuralAction()
                guard let itemIndex = store.items.firstIndex(where: { $0.id == item.id }),
                      canShowDraftRow else { return }
                // Return on a task inserts the draft directly below that task,
                // not at the default bottom position.
                activateDraft(at: itemIndex + 1)

            case .taskDraft:
                if let insertedItem = promoteDraftToItem(selectInsertedItem: true),
                   let insertedIndex = store.items.firstIndex(where: { $0.id == insertedItem.id }),
                   canShowDraftRow {
                    activateDraft(at: insertedIndex + 1)
                } else if !draftIsAtDefaultPosition {
                    _ = collapseSelectedDraftForNavigation(step: 1)
                }

            case .archiveItem, .filler:
                return
            }
        }
    }

    private func resizeWindow(animate: Bool = true) {
        guard let window = view.window else { return }
        guard !isInNativeFullScreen else { return }
        let rows = CGFloat(max(visibleRowCount, 1))
        let contentHeight = rows * rowHeight + LayoutMetrics.contentTopPadding + LayoutMetrics.contentBottomPadding
        let titlebarHeight = window.titlebarHeight
        let fullHeight = max(contentHeight + titlebarHeight, window.minSize.height)
        let fullWidth = max(panelWidth, window.minSize.width)
        let targetWidth = max(fullWidth, userPreferredWindowWidth ?? 0)
        let targetHeight = max(fullHeight, userPreferredWindowHeight ?? 0)
        let oldFrame = window.frame
        let padding = CGFloat(store.preferences.snapPadding)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? oldFrame

        let unclampedOrigin = NSPoint(
            x: oldFrame.origin.x,
            y: oldFrame.maxY - targetHeight
        )

        let clampedOrigin = NSPoint(
            x: min(max(unclampedOrigin.x, visibleFrame.minX + padding), visibleFrame.maxX - targetWidth - padding),
            y: min(max(unclampedOrigin.y, visibleFrame.minY + padding), visibleFrame.maxY - targetHeight - padding)
        )

        let newFrame = NSRect(origin: clampedOrigin, size: NSSize(width: targetWidth, height: targetHeight))
        guard abs(newFrame.height - oldFrame.height) > 0.5 || abs(newFrame.width - oldFrame.width) > 0.5 || newFrame.origin != oldFrame.origin else {
            return
        }

        guard animate else {
            window.setFrame(newFrame, display: true, animate: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.collapse
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let rowID = editorRowID else { return }
        switch rowModels.first(where: { $0.id == rowID })?.kind {
        case .taskItem(let item):
            let updatedText = sharedEditor.stringValue
            if updatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                convertItemToDraft(item, newText: "")
            } else {
                store.updateText(for: item.id, to: updatedText)
                refreshVisibleModel(for: rowID)
            }
        case .taskDraft:
            let updatedText = sharedEditor.stringValue
            let normalizedText = updatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : updatedText
            if normalizedText != updatedText {
                resetHiddenEditorText(to: normalizedText)
            }
            taskDraft.text = normalizedText
            if !taskDraft.trimmedText.isEmpty {
                _ = promoteDraftToItem(selectInsertedItem: true)
            } else {
                refreshVisibleModel(for: rowID)
            }
        case .archiveItem, .filler, .none:
            break
        }
        syncVisibleEditorState()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUpAndModifySelection(_:)):
            extendSelection(step: -1)
            return true
        case #selector(NSResponder.moveDownAndModifySelection(_:)):
            extendSelection(step: 1)
            return true
        case #selector(NSResponder.moveToBeginningOfDocumentAndModifySelection(_:)):
            extendSelection(to: .top)
            return true
        case #selector(NSResponder.moveToEndOfDocumentAndModifySelection(_:)):
            extendSelection(to: .bottom)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveUp()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveDown()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            submitRow()
            return true
        case #selector(NSResponder.insertTab(_:)):
            moveDown()
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            moveUp()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if currentTab == .tasks, selectedRowID == .taskDraft, taskDraft.isEmpty, !draftIsAtDefaultPosition {
                _ = collapseSelectedDraftForNavigation(step: -1)
                return true
            }
            return false
        case #selector(NSResponder.deleteBackward(_:)):
            if currentTab == .tasks, sharedEditor.stringValue.isEmpty, selectedRowID == .taskDraft, !draftIsAtDefaultPosition {
                _ = collapseSelectedDraftForNavigation(step: -1)
                return true
            }
            return false
        default:
            return false
        }
    }
}

extension TodoViewController: TodoListViewDelegate {
    func listView(_ listView: TodoListView, didActivateRow rowID: TodoRowID, selectionMode: TodoListSelectionMode) {
        switch selectionMode {
        case .replace:
            activateRow(rowID, placeCaretAtEnd: true)
        case .extendRange:
            extendSelection(to: rowID)
        case .toggleMembership:
            toggleSelection(for: rowID)
        }
        if currentTab == .tasks, rowID != .taskDraft {
            normalizeDraftBeforeStructuralAction()
        }
    }

    func listView(_ listView: TodoListView, didActivateCheckboxFor rowID: TodoRowID) {
        switch rowModels.first(where: { $0.id == rowID })?.kind {
        case .taskItem(let item):
            clearRangeSelectionState()
            selectedRowID = rowID
            animateCompletion(for: item.id, undoSnapshot: captureUndoSnapshot())
        case .archiveItem:
            clearRangeSelectionState()
            selectedRowID = rowID
            restoreArchiveSelection(rowIDs: [rowID])
        case .taskDraft, .filler, .none:
            return
        }
    }

    func listView(_ listView: TodoListView, contextMenuFor rowID: TodoRowID) -> NSMenu? {
        guard currentTab == .archive,
              case .archiveItem = rowModels.first(where: { $0.id == rowID })?.kind else {
            return nil
        }

        if isRangeSelectionActive, selectedRowIDs.contains(rowID) {
            selectedRowID = rowID
            syncSelectionUI(placeCaretAtEnd: false)
        } else if selectedRowID != rowID || isRangeSelectionActive {
            activateRow(rowID, placeCaretAtEnd: false)
        }

        let menu = NSMenu()
        let restoreItem = NSMenuItem(
            title: "Restore",
            action: #selector(restoreArchiveSelectionFromContextMenu(_:)),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        let deleteItem = NSMenuItem(
            title: "Permanently Delete",
            action: #selector(permanentlyDeleteArchiveSelectionFromContextMenu(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        menu.addItem(deleteItem)
        return menu
    }

    func listViewWillPressRowBody(_ listView: TodoListView, rowID: TodoRowID) {
        detachEditor(makeListFirstResponder: true)
    }

    func listViewWillBeginDragging(_ listView: TodoListView, rowID: TodoRowID) {
        detachEditor(makeListFirstResponder: false)
        view.window?.makeFirstResponder(nil)
    }

    func listView(_ listView: TodoListView, didFinishDraggingRow rowID: TodoRowID, orderedItemIDs: [UUID]) {
        performUndoableAction("Reorder") {
            store.reorderItems(by: orderedItemIDs)
            clearRangeSelectionState()
            selectedRowID = rowID
            refreshRows(resize: false, animateResize: false)
        }
    }
}

#if DEBUG
enum TodoInteractionTestingSelection: Equatable {
    case taskItem(String)
    case archiveItem(String)
    case taskDraft
    case filler
}

struct TodoInteractionTestingSnapshot: Equatable {
    let selected: TodoInteractionTestingSelection?
    let visibleTaskSequence: [String]
    let draftInsertionIndex: Int
    let draftText: String
}

extension TodoViewController {
    @MainActor
    func testingLoadView() {
        loadViewIfNeeded()
    }

    @MainActor
    func testingSelectTask(at index: Int) {
        precondition(store.items.indices.contains(index))
        selectedRowID = .taskItem(store.items[index].id)
        clearRangeSelectionState()
        refreshRows(resize: false, animateResize: false, placeCaretAtEnd: false)
    }

    @MainActor
    func testingRefresh() {
        refreshRows(resize: false, animateResize: false, placeCaretAtEnd: false)
    }

    @MainActor
    func testingSnapshot() -> TodoInteractionTestingSnapshot {
        TodoInteractionTestingSnapshot(
            selected: testingSelectionKind(for: selectedRowID),
            visibleTaskSequence: rowModels.compactMap { model in
                switch model.kind {
                case .taskItem(let item):
                    return item.text
                case .taskDraft:
                    return "<draft>"
                case .archiveItem, .filler:
                    return nil
                }
            },
            draftInsertionIndex: taskDraft.insertionIndex,
            draftText: taskDraft.text
        )
    }

    private func testingSelectionKind(for rowID: TodoRowID?) -> TodoInteractionTestingSelection? {
        guard let rowID,
              let model = rowModels.first(where: { $0.id == rowID }) else { return nil }

        switch model.kind {
        case .taskItem(let item):
            return .taskItem(item.text)
        case .archiveItem(let item):
            return .archiveItem(item.text)
        case .taskDraft:
            return .taskDraft
        case .filler:
            return .filler
        }
    }
}
#endif

private extension NSWindow {
    var titlebarHeight: CGFloat {
        let safeAreaHeight = contentView?.safeAreaInsets.top ?? 0
        let layoutChromeHeight = max(0, frame.height - contentLayoutRect.height)
        return max(safeAreaHeight, layoutChromeHeight)
    }
}

final class HeaderButtonDebugOverlayView: NSView {
    private let cellWidth: CGFloat
    private let strokeColor: NSColor

    init(cellWidth: CGFloat, strokeColor: NSColor) {
        self.cellWidth = cellWidth
        self.strokeColor = strokeColor
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath()
        let maxX = bounds.maxX
        let maxY = bounds.maxY

        path.move(to: NSPoint(x: 0.5, y: 0.5))
        path.line(to: NSPoint(x: maxX - 0.5, y: 0.5))
        path.line(to: NSPoint(x: maxX - 0.5, y: maxY - 0.5))
        path.line(to: NSPoint(x: 0.5, y: maxY - 0.5))
        path.close()

        let separatorXValues = [cellWidth, cellWidth * 2]
        for separatorX in separatorXValues where separatorX < maxX {
            path.move(to: NSPoint(x: separatorX + 0.5, y: 0.5))
            path.line(to: NSPoint(x: separatorX + 0.5, y: maxY - 0.5))
        }

        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

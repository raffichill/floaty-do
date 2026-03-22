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
    private var deferredEditorRowID: TodoRowID?
    private var deferredEditorActivationWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var currentTab: Tab = .tasks
    private var tasksTabButton: NSButton!
    private var archiveTabButton: HoverTrackingButton!
    private var settingsButton: HoverTrackingButton!
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

        tasksTabButton = makeTabButton(symbolName: "checklist.unchecked", action: #selector(switchToTasks))
        archiveTabButton = makeHoverTabButton(symbolName: "archivebox", action: #selector(switchToArchive))
        archiveTabButton.onHoverChange = { [weak self] _ in
            self?.updateTabAppearance()
        }
        settingsButton = makeHoverTabButton(symbolName: "paintpalette", action: #selector(toggleSettings(_:)))
        settingsButton.onHoverChange = { [weak self] _ in
            self?.updateTabAppearance()
        }

        let headerDebugView = NSView()
        headerDebugView.translatesAutoresizingMaskIntoConstraints = false
        applyHeaderDebugOutline(to: headerDebugView)

        let tabBar = NSView()
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        let headerButtonDebugOverlay = HeaderButtonDebugOverlayView(
            cellWidth: DebugMetrics.headerButtonWidth,
            strokeColor: DebugMetrics.headerButtonOutlineColor
        )
        headerButtonDebugOverlay.translatesAutoresizingMaskIntoConstraints = false
        headerButtonDebugOverlay.isHidden = !DebugMetrics.showsHeaderButtonHitTargets
        container.addSubview(headerDebugView)
        container.addSubview(tabBar)
        tabBar.addSubview(headerButtonDebugOverlay)
        tabBar.addSubview(tasksTabButton)
        tabBar.addSubview(archiveTabButton)
        tabBar.addSubview(settingsButton)

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

        NSLayoutConstraint.activate([
            headerDebugView.topAnchor.constraint(equalTo: container.topAnchor),
            headerDebugView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerDebugView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            headerDebugHeightConstraint,

            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: headerDebugView.bottomAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            tabBar.widthAnchor.constraint(equalToConstant: DebugMetrics.headerButtonWidth * 3),

            headerButtonDebugOverlay.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            headerButtonDebugOverlay.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            headerButtonDebugOverlay.topAnchor.constraint(equalTo: tabBar.topAnchor),
            headerButtonDebugOverlay.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),

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
        ])

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

    private func makeTabButton(symbolName: String, action: Selector) -> PressScaleButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let button = PressScaleButton(image: image.withSymbolConfiguration(config)!, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.suppressSystemHighlight = true
        button.pressedScale = 0.85
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        if let cell = button.cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
        button.widthAnchor.constraint(equalToConstant: DebugMetrics.headerButtonWidth).isActive = true
        return button
    }

    private func makeHoverTabButton(symbolName: String, action: Selector) -> HoverTrackingButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let button = HoverTrackingButton(image: image.withSymbolConfiguration(config)!, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.suppressSystemHighlight = true
        button.pressedScale = 0.85
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        if let cell = button.cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
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
        tasksTabButton.contentTintColor = tasksIsEmphasized ? primary : primary.withAlphaComponent(0.35)

        let archiveIsEmphasized = !settingsIsVisible && (currentTab == .archive || archiveTabButton.isHovered)
        archiveTabButton.contentTintColor = archiveIsEmphasized ? primary : primary.withAlphaComponent(0.35)

        let settingsIsEmphasized = settingsIsVisible || settingsButton.isHovered
        settingsButton.contentTintColor = settingsIsEmphasized ? primary : primary.withAlphaComponent(0.42)
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
        refreshRows(resize: false, animateResize: false, placeCaretAtEnd: false)
        resizeWindow(animate: false)
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
                    canComplete: false,
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
        refreshRows(animateResize: false, placeCaretAtEnd: true)
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
                canComplete: false,
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
                performUndoableAction("Restore") {
                    let selectableRowIDs = rowModels.filter(\.isSelectable).map(\.id)
                    let selectionIndex = selectedBatchRows.compactMap { selectableRowIDs.firstIndex(of: $0) }.min() ?? 0
                    let itemIDs = selectedBatchRows.compactMap { rowID -> UUID? in
                        guard case .archiveItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return nil }
                        return item.id
                    }
                    guard !itemIDs.isEmpty else { return }
                    itemIDs.forEach { store.restore(id: $0) }
                    clearRangeSelectionState()
                    let updatedModels = buildRowModels(for: .archive)
                    selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
                    refreshRows()
                }
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
            performUndoableAction("Restore") {
                guard case .archiveItem(let item) = selectedModel.kind else { return }
                let selectionIndex = selectedRowIndex ?? 0
                store.restore(id: item.id)
                let updatedModels = buildRowModels(for: .archive)
                selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
                refreshRows()
            }
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
                performUndoableAction("Delete") {
                    let selectableRowIDs = rowModels.filter(\.isSelectable).map(\.id)
                    let selectionIndex = selectedBatchRows.compactMap { selectableRowIDs.firstIndex(of: $0) }.min() ?? 0
                    let itemIDs = selectedBatchRows.compactMap { rowID -> UUID? in
                        guard case .archiveItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return nil }
                        return item.id
                    }
                    guard !itemIDs.isEmpty else { return }
                    itemIDs.forEach { store.deleteArchived(id: $0) }
                    clearRangeSelectionState()
                    let updatedModels = buildRowModels(for: .archive)
                    selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
                    refreshRows()
                }
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
            performUndoableAction("Delete") {
                guard case .archiveItem(let item) = selectedModel.kind else { return }
                let selectionIndex = selectedRowIndex ?? 0
                store.deleteArchived(id: item.id)
                let updatedModels = buildRowModels(for: .archive)
                selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
                refreshRows()
            }
        }
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
        let oldFrame = window.frame
        let padding = CGFloat(store.preferences.snapPadding)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? oldFrame

        let unclampedOrigin = NSPoint(
            x: oldFrame.origin.x,
            y: oldFrame.maxY - fullHeight
        )

        let clampedOrigin = NSPoint(
            x: min(max(unclampedOrigin.x, visibleFrame.minX + padding), visibleFrame.maxX - fullWidth - padding),
            y: min(max(unclampedOrigin.y, visibleFrame.minY + padding), visibleFrame.maxY - fullHeight - padding)
        )

        let newFrame = NSRect(origin: clampedOrigin, size: NSSize(width: fullWidth, height: fullHeight))
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
        guard case .taskItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return }
        clearRangeSelectionState()
        selectedRowID = rowID
        animateCompletion(for: item.id, undoSnapshot: captureUndoSnapshot())
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

#if false

fileprivate final class TodoListView: NSView {
    fileprivate enum HitZone {
        case checkbox
        case body
    }

    private struct PressState {
        let rowID: TodoRowID
        let initialPoint: CGPoint
        let zone: HitZone
        let rowWasActive: Bool
        let canDrag: Bool
        let previousEditingRowID: TodoRowID?
    }

    private struct DragSession {
        let rowID: TodoRowID
        let itemID: UUID
        let snapshotView: NSImageView
        let pointerOffset: CGFloat
        var currentTaskOrdinal: Int
    }

    private enum InteractionState {
        case idle
        case pressed(PressState)
        case dragging(DragSession)
        case settling
    }

    private enum InteractionMetrics {
        static let dragStartDistance: CGFloat = 3.5
        static let dragSwapCoverageFactor: CGFloat = 0.33
        static let dragReorderDuration: CFTimeInterval = 0.12
        static let pressedScale: CGFloat = 0.99
        static let dragScale: CGFloat = 0.99
        static let pressAnimationDuration: CFTimeInterval = 0.08
        static let dragScaleDuration: CFTimeInterval = 0.08
    }

    weak var delegate: TodoListViewDelegate?

    private var rowModelsByID: [TodoRowID: TodoRowModel] = [:]
    private var displayOrder: [TodoRowID] = []
    private var rowViews: [TodoRowID: TodoRowView] = [:]
    private var selectedRowID: TodoRowID?
    private var selectedRowIDs = Set<TodoRowID>()
    private var editingRowID: TodoRowID?
    private var preferences: AppPreferences = .default
    private var pressedRowID: TodoRowID?
    private var selectionRevealRowID: TodoRowID?
    private var interactionState: InteractionState = .idle

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    var isDragging: Bool {
        if case .dragging = interactionState { return true }
        return false
    }

    var isBusy: Bool {
        switch interactionState {
        case .idle, .pressed:
            return false
        case .dragging, .settling:
            return true
        }
    }

    func apply(
        models: [TodoRowModel],
        selectedRowID: TodoRowID?,
        selectedRowIDs: Set<TodoRowID>,
        editingRowID: TodoRowID?,
        preferences: AppPreferences,
        animatedLayout: Bool,
        animatedLayoutDuration: CFTimeInterval? = nil,
        selectionRevealRowID: TodoRowID? = nil
    ) {
        self.preferences = preferences
        self.selectedRowID = selectedRowID
        self.selectedRowIDs = selectedRowIDs
        self.editingRowID = editingRowID
        self.selectionRevealRowID = selectionRevealRowID
        rowModelsByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let incomingIDs = Set(models.map(\.id))
        for staleID in rowViews.keys where !incomingIDs.contains(staleID) {
            rowViews[staleID]?.removeFromSuperview()
            rowViews.removeValue(forKey: staleID)
        }

        for model in models {
            let rowView = rowViews[model.id] ?? TodoRowView(model: model, preferences: preferences)
            rowView.configure(model: model, preferences: preferences)
            rowView.setSelectionState(
                focused: model.id == selectedRowID,
                selected: selectedRowIDs.contains(model.id),
                animateFill: model.id == selectionRevealRowID && model.id == selectedRowID
            )
            rowView.setEditing(model.id == editingRowID)
            rowView.setPressed(model.id == pressedRowID)
            if rowViews[model.id] == nil {
                rowViews[model.id] = rowView
                addSubview(rowView)
            }
        }

        if !isDragging {
            displayOrder = models.map(\.id)
        }

        layoutRows(animated: animatedLayout, duration: animatedLayoutDuration)
        self.selectionRevealRowID = nil
    }

    func updateModel(_ model: TodoRowModel) {
        rowModelsByID[model.id] = model
        guard let rowView = rowViews[model.id] else { return }
        rowView.configure(model: model, preferences: preferences)
        rowView.setSelectionState(
            focused: model.id == selectedRowID,
            selected: selectedRowIDs.contains(model.id),
            animateFill: model.id == selectionRevealRowID && model.id == selectedRowID
        )
        rowView.setEditing(model.id == editingRowID)
        rowView.setPressed(model.id == pressedRowID)
    }

    func updateInteractionState(selectedRowID: TodoRowID?, selectedRowIDs: Set<TodoRowID>, editingRowID: TodoRowID?) {
        self.selectedRowID = selectedRowID
        self.selectedRowIDs = selectedRowIDs
        self.editingRowID = editingRowID
        refreshRowVisualState(excluding: currentDraggedRowID)
    }

    func updateEditingPresentation(rowID: TodoRowID?, text: String?, selectionRange: NSRange?) {
        for (candidateRowID, rowView) in rowViews {
            if candidateRowID == rowID, let text, let selectionRange {
                rowView.updateEditingPresentation(text: text, selectionRange: selectionRange)
            } else {
                rowView.clearEditingPresentation()
            }
        }
    }

    func rowView(for rowID: TodoRowID) -> TodoRowView? {
        rowViews[rowID]
    }

    func animateRemoval(of rowID: TodoRowID, duration: TimeInterval, completion: @escaping () -> Void) {
        guard let rowView = rowViews[rowID] else {
            completion()
            return
        }

        rowView.layer?.masksToBounds = false

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        rowView.layer?.add(fade, forKey: "rowFade")

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.94
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false
        rowView.layer?.add(scale, forKey: "rowScale")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            completion()
        }
    }

    override func layout() {
        super.layout()
        layoutRows(animated: false, duration: nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard case .idle = interactionState else { return }

        let location = convert(event.locationInWindow, from: nil)
        guard let rowID = rowID(at: location),
              let rowView = rowViews[rowID],
              let model = rowModelsByID[rowID],
              model.isSelectable else {
            super.mouseDown(with: event)
            return
        }

        let zone = rowView.hitZone(at: convert(location, to: rowView))
        let canDrag = zone == .body && model.canDrag
        if zone == .body {
            delegate?.listViewWillPressRowBody(self, rowID: rowID)
            window?.makeFirstResponder(self)
        }
        if zone == .body {
            selectedRowIDs.removeAll()
        }
        pressedRowID = zone == .body ? rowID : nil
        interactionState = .pressed(
            PressState(
                rowID: rowID,
                initialPoint: location,
                zone: zone,
                rowWasActive: rowID == selectedRowID,
                canDrag: canDrag,
                previousEditingRowID: editingRowID
            )
        )
        selectedRowID = rowID
        editingRowID = nil
        refreshRowVisualState()
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        switch interactionState {
        case .idle, .settling:
            return

        case .pressed(let press):
            guard press.canDrag,
                  let model = rowModelsByID[press.rowID],
                  case .taskItem(let item) = model.kind else {
                return
            }

            let deltaX = location.x - press.initialPoint.x
            let deltaY = location.y - press.initialPoint.y
            guard hypot(deltaX, deltaY) >= InteractionMetrics.dragStartDistance else { return }
            beginDrag(from: press, itemID: item.id, pointerLocation: location)

        case .dragging(var drag):
            updateDragSession(&drag, pointerLocation: location)
            interactionState = .dragging(drag)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        switch interactionState {
        case .idle:
            return

        case .pressed(let press):
            guard let model = rowModelsByID[press.rowID],
                  model.isSelectable else { return }

            if press.zone == .checkbox,
               model.canComplete,
               let rowView = rowViews[press.rowID] {
                let hitPoint = convert(location, to: rowView)
                if rowView.hitZone(at: hitPoint) == .checkbox {
                    interactionState = .idle
                    pressedRowID = nil
                    refreshRowVisualState()
                    delegate?.listView(self, didActivateCheckboxFor: press.rowID)
                    return
                }
            }

            interactionState = .idle
            pressedRowID = nil

            if press.zone == .body {
                refreshRowVisualState()
                delegate?.listView(self, didActivateRow: press.rowID)
            } else if press.rowWasActive {
                editingRowID = press.previousEditingRowID
                refreshRowVisualState()
            } else {
                refreshRowVisualState()
            }

        case .dragging(let drag):
            finishDragSession(drag)

        case .settling:
            return
        }
    }

    private func beginDrag(from press: PressState, itemID: UUID, pointerLocation: CGPoint) {
        guard let rowView = rowViews[press.rowID],
              let taskOrdinal = taskOrdinal(for: press.rowID) else {
            interactionState = .idle
            return
        }

        delegate?.listViewWillBeginDragging(self, rowID: press.rowID)
        pressedRowID = nil
        rowView.setPressed(false)

        guard let snapshotView = makeSnapshot(for: rowView) else {
            interactionState = .idle
            refreshRowVisualState()
            return
        }

        snapshotView.frame = rowView.frame
        addSubview(snapshotView, positioned: .above, relativeTo: nil)
        applyScale(
            to: snapshotView,
            scale: InteractionMetrics.dragScale,
            duration: InteractionMetrics.dragScaleDuration,
            animationKey: "dragSnapshotScale"
        )

        rowView.setDragging(true)

        let rowFrame = rowView.frame
        var drag = DragSession(
            rowID: press.rowID,
            itemID: itemID,
            snapshotView: snapshotView,
            pointerOffset: pointerLocation.y - rowFrame.origin.y,
            currentTaskOrdinal: taskOrdinal
        )
        interactionState = .dragging(drag)
        refreshRowVisualState(excluding: press.rowID)
        updateDragSession(&drag, pointerLocation: pointerLocation)
        interactionState = .dragging(drag)
    }

    private func updateDragSession(_ drag: inout DragSession, pointerLocation: CGPoint) {
        var snapshotFrame = drag.snapshotView.frame
        snapshotFrame.origin.y = pointerLocation.y - drag.pointerOffset
        drag.snapshotView.frame = snapshotFrame

        let overlapThreshold = CGFloat(preferences.rowHeight) * InteractionMetrics.dragSwapCoverageFactor
        var didReorder = false

        while drag.currentTaskOrdinal > 0 {
            let taskIDs = taskRowIDsInDisplayOrder()
            let previousTaskID = taskIDs[drag.currentTaskOrdinal - 1]
            guard let previousFrame = frameForRow(withID: previousTaskID) else { break }

            if drag.snapshotView.frame.minY < previousFrame.minY + overlapThreshold {
                swapTaskRows(at: drag.currentTaskOrdinal, and: drag.currentTaskOrdinal - 1)
                drag.currentTaskOrdinal -= 1
                didReorder = true
            } else {
                break
            }
        }

        while drag.currentTaskOrdinal < max(taskRowIDsInDisplayOrder().count - 1, 0) {
            let taskIDs = taskRowIDsInDisplayOrder()
            let nextTaskID = taskIDs[drag.currentTaskOrdinal + 1]
            guard let nextFrame = frameForRow(withID: nextTaskID) else { break }

            if drag.snapshotView.frame.maxY > nextFrame.maxY - overlapThreshold {
                swapTaskRows(at: drag.currentTaskOrdinal, and: drag.currentTaskOrdinal + 1)
                drag.currentTaskOrdinal += 1
                didReorder = true
            } else {
                break
            }
        }

        if didReorder {
            layoutRows(animated: true, duration: InteractionMetrics.dragReorderDuration)
        }
    }

    private func finishDragSession(_ drag: DragSession) {
        interactionState = .settling
        pressedRowID = nil
        refreshRowVisualState(excluding: drag.rowID)
        let targetFrame = frameForRow(withID: drag.rowID) ?? drag.snapshotView.frame
        animateDropSettle(
            drag.snapshotView,
            to: targetFrame,
            duration: InteractionMetrics.dragReorderDuration,
            scale: InteractionMetrics.dragScale,
            animationKey: "dropSettle"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + InteractionMetrics.dragReorderDuration) { [weak self] in
            guard let self else { return }
            drag.snapshotView.removeFromSuperview()
            self.rowViews[drag.rowID]?.alphaValue = 1.0
            self.rowViews[drag.rowID]?.setDragging(false)
            self.interactionState = .idle
            self.refreshRowVisualState()
            self.delegate?.listView(self, didFinishDraggingRow: drag.rowID, orderedItemIDs: self.currentOrderedTaskItemIDs())
        }
    }

    private func refreshRowVisualState(excluding draggedRowID: TodoRowID? = nil) {
        for rowID in displayOrder {
            guard let rowView = rowViews[rowID] else { continue }
            rowView.setSelectionState(
                focused: rowID == selectedRowID,
                selected: selectedRowIDs.contains(rowID),
                animateFill: rowID == selectionRevealRowID && rowID == selectedRowID
            )
            rowView.setEditing(rowID == editingRowID)
            rowView.setPressed(rowID == pressedRowID)
            if rowID != draggedRowID {
                rowView.alphaValue = 1.0
                rowView.setDragging(false)
            }
        }
    }

    private func layoutRows(animated: Bool, duration: CFTimeInterval?) {
        let draggedRowID = currentDraggedRowID
        let animationDuration = duration ?? InteractionMetrics.dragReorderDuration

        let updates = {
            for (index, rowID) in self.displayOrder.enumerated() {
                guard let rowView = self.rowViews[rowID] else { continue }
                rowView.setSelectionState(
                    focused: rowID == self.selectedRowID,
                    selected: self.selectedRowIDs.contains(rowID),
                    animateFill: rowID == self.selectionRevealRowID && rowID == self.selectedRowID
                )
                rowView.setEditing(rowID == self.editingRowID)
                rowView.setPressed(rowID == self.pressedRowID)
                let targetFrame = self.frameForRow(at: index)
                rowView.frame = targetFrame
                if rowID != draggedRowID {
                    rowView.alphaValue = 1.0
                    rowView.setDragging(false)
                }
            }
        }

        guard animated else {
            updates()
            return
        }

        for (index, rowID) in displayOrder.enumerated() {
            guard let rowView = rowViews[rowID] else { continue }
            rowView.setSelectionState(
                focused: rowID == selectedRowID,
                selected: selectedRowIDs.contains(rowID),
                animateFill: rowID == selectionRevealRowID && rowID == selectedRowID
            )
            rowView.setEditing(rowID == editingRowID)
            rowView.setPressed(rowID == pressedRowID)
            let targetFrame = frameForRow(at: index)
            if rowID == draggedRowID {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                rowView.frame = targetFrame
                rowView.layer?.transform = CATransform3DIdentity
                CATransaction.commit()
                continue
            }

            if rowView.frame != targetFrame {
                animateRowReorder(
                    rowView,
                    to: targetFrame,
                    duration: animationDuration,
                    animationKey: "dragReorder.\(rowID)"
                )
            }
        }
    }

    private func animateRowReorder(
        _ rowView: NSView,
        to targetFrame: CGRect,
        duration: CFTimeInterval,
        animationKey: String
    ) {
        guard let layer = rowView.layer else {
            rowView.frame = targetFrame
            return
        }

        let currentVisualFrame = layer.presentation()?.frame ?? rowView.frame
        let deltaY = currentVisualFrame.minY - targetFrame.minY

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rowView.frame = targetFrame
        CATransaction.commit()

        layer.removeAnimation(forKey: animationKey)

        guard abs(deltaY) > 0.5 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
            return
        }

        let startTransform = CATransform3DMakeTranslation(0, deltaY, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = startTransform
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = startTransform
        animation.toValue = CATransform3DIdentity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: animationKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func animateDropSettle(
        _ view: NSView,
        to targetFrame: CGRect,
        duration: CFTimeInterval,
        scale: CGFloat,
        animationKey: String
    ) {
        guard let layer = view.layer else {
            view.frame = targetFrame
            return
        }

        let currentVisualFrame = layer.presentation()?.frame ?? view.frame
        let deltaX = currentVisualFrame.minX - targetFrame.minX
        let deltaY = currentVisualFrame.minY - targetFrame.minY

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.frame = targetFrame
        CATransaction.commit()

        layer.removeAnimation(forKey: animationKey)

        guard abs(deltaX) > 0.5 || abs(deltaY) > 0.5 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
            return
        }

        var startTransform = CATransform3DMakeTranslation(deltaX, deltaY, 0)
        startTransform = CATransform3DScale(startTransform, scale, scale, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = startTransform
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = startTransform
        animation.toValue = CATransform3DIdentity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: animationKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func applyScale(
        to view: NSView,
        scale: CGFloat,
        duration: CFTimeInterval,
        animationKey: String
    ) {
        guard let layer = view.layer else { return }
        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let targetTransform = CATransform3DMakeScale(scale, scale, 1)

        layer.removeAnimation(forKey: animationKey)

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = currentTransform
        animation.toValue = targetTransform
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: animationKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        CATransaction.commit()
    }

    private func makeSnapshot(for rowView: TodoRowView) -> NSImageView? {
        let bounds = rowView.bounds
        guard let bitmap = rowView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        rowView.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = CGFloat(preferences.cornerRadius)
        imageView.layer?.shadowColor = NSColor.black.cgColor
        imageView.layer?.shadowOpacity = 0.22
        imageView.layer?.shadowRadius = 12
        imageView.layer?.shadowOffset = CGSize(width: 0, height: 3)
        imageView.layer?.zPosition = 10
        return imageView
    }

    private func rowID(at location: CGPoint) -> TodoRowID? {
        for rowID in displayOrder {
            guard let rowView = rowViews[rowID] else { continue }
            if rowView.frame.contains(location) {
                return rowID
            }
        }
        return nil
    }

    private func taskRowIDsInDisplayOrder() -> [TodoRowID] {
        displayOrder.filter { rowID in
            if case .taskItem = rowModelsByID[rowID]?.kind {
                return true
            }
            return false
        }
    }

    private func taskOrdinal(for rowID: TodoRowID) -> Int? {
        guard case .taskItem = rowModelsByID[rowID]?.kind else { return nil }
        return taskRowIDsInDisplayOrder().firstIndex(of: rowID)
    }

    private func swapTaskRows(at lhsOrdinal: Int, and rhsOrdinal: Int) {
        let taskIDs = taskRowIDsInDisplayOrder()
        guard taskIDs.indices.contains(lhsOrdinal),
              taskIDs.indices.contains(rhsOrdinal),
              let lhsDisplayIndex = displayOrder.firstIndex(of: taskIDs[lhsOrdinal]),
              let rhsDisplayIndex = displayOrder.firstIndex(of: taskIDs[rhsOrdinal]) else {
            return
        }
        displayOrder.swapAt(lhsDisplayIndex, rhsDisplayIndex)
    }

    private func currentOrderedTaskItemIDs() -> [UUID] {
        displayOrder.compactMap { rowID in
            guard case .taskItem(let item) = rowModelsByID[rowID]?.kind else { return nil }
            return item.id
        }
    }

    private var currentDraggedRowID: TodoRowID? {
        if case .dragging(let drag) = interactionState {
            return drag.rowID
        }
        return nil
    }

    private func frameForRow(at index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(index) * CGFloat(preferences.rowHeight),
            width: bounds.width,
            height: CGFloat(preferences.rowHeight)
        )
    }

    private func frameForRow(withID rowID: TodoRowID) -> CGRect? {
        guard let index = displayOrder.firstIndex(of: rowID) else { return nil }
        return frameForRow(at: index)
    }
}

fileprivate final class TodoRowView: NSView {
    private enum AppearanceMetrics {
        static let pressedScale: CGFloat = 0.99
        static let pressAnimationDuration: CFTimeInterval = 0.08
        static let showsDebugGeometry = false
    }

    private let backgroundView = NSView()
    private let circleView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    private let editingTextView = EditingTextDisplayView()
    let editorHostView = PassiveEditorHostView()
    private let cursorShieldView = CursorShieldView()
    private let debugOverlayView = DebugGeometryOverlayView()

    private var preferences: AppPreferences
    private(set) var model: TodoRowModel

    private var isFocusedRow = false {
        didSet { updateAppearance() }
    }

    private var isRangeSelected = false {
        didSet { updateAppearance() }
    }

    private var isEditingRow = false {
        didSet { updateAppearance() }
    }

    private var isPressedRow = false {
        didSet { updateAppearance() }
    }

    private var isDraggingRow = false {
        didSet { updateAppearance() }
    }

    private var shouldAnimateNextSelectionFill = false

    init(model: TodoRowModel, preferences: AppPreferences) {
        self.model = model
        self.preferences = preferences
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = CGFloat(preferences.cornerRadius)
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)

        circleView.wantsLayer = true
        addSubview(circleView)

        textLabel.font = preferences.appFont()
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.wantsLayer = true
        if let cell = textLabel.cell as? NSTextFieldCell {
            cell.isScrollable = false
            cell.usesSingleLineMode = true
            cell.wraps = false
        }
        addSubview(textLabel)

        editingTextView.wantsLayer = true
        addSubview(editingTextView)
        addSubview(editorHostView)
        addSubview(cursorShieldView)
        if AppearanceMetrics.showsDebugGeometry {
            addSubview(debugOverlayView)
        }
        configure(model: model, preferences: preferences)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()

        backgroundView.frame = bounds.insetBy(dx: LayoutMetrics.rowBackgroundInset, dy: LayoutMetrics.rowVerticalInset)

        let checkboxRect = self.checkboxRect
        let circleX = checkboxRect.minX + ((checkboxRect.width - LayoutMetrics.circleSize) / 2)
        let circleY = checkboxRect.minY + ((checkboxRect.height - LayoutMetrics.circleSize) / 2)
        circleView.frame = NSRect(x: circleX, y: circleY, width: LayoutMetrics.circleSize, height: LayoutMetrics.circleSize)

        let textFrame = contentTextRect(for: checkboxRect)
        textLabel.frame = textFrame
        editingTextView.frame = textFrame
        editorHostView.frame = textFrame
        cursorShieldView.frame = textFrame
        if AppearanceMetrics.showsDebugGeometry {
            debugOverlayView.frame = bounds
            debugOverlayView.rowFrame = bounds
            debugOverlayView.backgroundFrame = backgroundView.frame
            debugOverlayView.checkboxFrame = checkboxRect
            debugOverlayView.textFrame = textFrame
            debugOverlayView.labelContentFrame = convertedLabelContentFrame()
            debugOverlayView.editorContentFrame = editingTextView.convert(editingTextView.debugContentRect, to: self)
            debugOverlayView.centerlineY = checkboxRect.midY
            debugOverlayView.needsDisplay = true
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    func configure(model: TodoRowModel, preferences: AppPreferences) {
        self.model = model
        self.preferences = preferences

        let symbolName = model.isDone ? "checkmark.circle.fill" : "circle"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        circleView.image = image.withSymbolConfiguration(config)
        textLabel.font = preferences.appFont()
        editingTextView.font = preferences.appFont()
        backgroundView.layer?.cornerRadius = CGFloat(preferences.cornerRadius)

        updateAppearance()
        needsLayout = true
    }

    func setSelectionState(focused: Bool, selected: Bool, animateFill: Bool = false) {
        shouldAnimateNextSelectionFill = animateFill && focused
        isFocusedRow = focused
        isRangeSelected = selected && !focused
    }

    func setEditing(_ editing: Bool) {
        isEditingRow = editing && model.isEditable
        if !isEditingRow {
            editingTextView.restoreDisplayState(text: model.text, showsStrikethrough: model.showsStrikethrough)
        }
    }

    func setPressed(_ pressed: Bool) {
        isPressedRow = pressed && model.isSelectable
    }

    func setDragging(_ dragging: Bool) {
        isDraggingRow = dragging
    }

    func refreshMountedEditorState() {
        updateAppearance()
    }

    func updateEditingPresentation(text: String, selectionRange: NSRange) {
        editingTextView.text = text
        editingTextView.selectionRange = selectionRange
        editingTextView.showsCaret = selectionRange.length == 0
        editingTextView.needsDisplay = true
    }

    func clearEditingPresentation() {
        editingTextView.restoreDisplayState(text: model.text, showsStrikethrough: model.showsStrikethrough)
    }

    func hitZone(at point: NSPoint) -> TodoListView.HitZone {
        if model.canComplete && checkboxRect.contains(point) {
            return .checkbox
        }
        return .body
    }

    func playCompletionAnimation(motion: MotionProfile, completion: @escaping () -> Void) {
        guard let circleLayer = circleView.layer else {
            completion()
            return
        }

        setEditing(false)
        layoutSubtreeIfNeeded()

        let textContentFrame = editingTextView.convert(editingTextView.debugContentRect, to: self)
        if !model.text.isEmpty {
            let textWidth = min((model.text as NSString).size(withAttributes: [.font: preferences.appFont()]).width, textContentFrame.width)
            let strikeLayer = CAShapeLayer()
            let midY = textContentFrame.midY
            let path = CGMutablePath()
            path.move(to: CGPoint(x: textContentFrame.minX, y: midY))
            path.addLine(to: CGPoint(x: textContentFrame.minX + textWidth, y: midY))
            strikeLayer.path = path
            strikeLayer.strokeColor = preferences.strikethroughColor.cgColor
            strikeLayer.lineWidth = 1.0
            strikeLayer.strokeEnd = 0.0
            layer?.addSublayer(strikeLayer)

            let strokeAnim = CABasicAnimation(keyPath: "strokeEnd")
            strokeAnim.fromValue = 0.0
            strokeAnim.toValue = 1.0
            strokeAnim.duration = motion.completionSweep
            strokeAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            strokeAnim.fillMode = .forwards
            strokeAnim.isRemovedOnCompletion = false
            strikeLayer.add(strokeAnim, forKey: "strikethrough")

            let fadeText = CABasicAnimation(keyPath: "opacity")
            fadeText.fromValue = 1.0
            fadeText.toValue = 0.3
            fadeText.duration = motion.completionSweep
            fadeText.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fadeText.fillMode = .forwards
            fadeText.isRemovedOnCompletion = false
            editingTextView.layer?.add(fadeText, forKey: "fadeText")
        }

        func centerAnchor() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let position = circleLayer.position
            let anchor = circleLayer.anchorPoint
            let bounds = circleLayer.bounds
            circleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            circleLayer.position = CGPoint(
                x: position.x + bounds.width * (0.5 - anchor.x),
                y: position.y + bounds.height * (0.5 - anchor.y)
            )
            CATransaction.commit()
        }

        centerAnchor()

        let shrink = CASpringAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = 0.0
        shrink.stiffness = 200
        shrink.damping = 15
        shrink.duration = motion.completionSettle
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        circleLayer.add(shrink, forKey: "shrinkOut")

        DispatchQueue.main.asyncAfter(deadline: .now() + motion.checkSwapDelay) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)!
            self.circleView.image = checkImage.withSymbolConfiguration(config)
            self.circleView.contentTintColor = self.preferences.resolvedContentColor()

            circleLayer.removeAnimation(forKey: "shrinkOut")
            centerAnchor()

            let growIn = CASpringAnimation(keyPath: "transform.scale")
            growIn.fromValue = 0.0
            growIn.toValue = 1.0
            growIn.stiffness = 200
            growIn.damping = 15
            growIn.duration = motion.completionSettle
            growIn.fillMode = .forwards
            growIn.isRemovedOnCompletion = false
            circleLayer.add(growIn, forKey: "growIn")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + motion.completionSettle) {
            completion()
        }
    }

    private var checkboxRect: NSRect {
        NSRect(
            x: LayoutMetrics.rowHorizontalInset,
            y: (bounds.height - LayoutMetrics.circleHitSize) / 2,
            width: LayoutMetrics.circleHitSize,
            height: LayoutMetrics.circleHitSize
        )
    }

    private func contentTextRect(for checkboxRect: NSRect) -> NSRect {
        let textX = checkboxRect.maxX + LayoutMetrics.textInset
        let textWidth = max(0, bounds.width - textX - LayoutMetrics.rowHorizontalInset)
        let font = textLabel.font ?? preferences.appFont()
        let textHeight = fontLineHeight(for: font)
        let centeredY = checkboxRect.midY - (textHeight / 2) + CGFloat(preferences.manualTextVerticalOffset)
        let textY = alignToHalfBackingPixel(centeredY)
        return NSRect(x: textX, y: textY, width: textWidth, height: textHeight)
    }

    private func updateAppearance() {
        let activeFillColor = preferences.activeFillColor
        let isAnySelected = (isFocusedRow || isRangeSelected) && model.isSelectable
        let circleAlpha = isAnySelected
            ? max(CGFloat(model.circleOpacity), model.isDone ? CGFloat(model.textOpacity) : 0.86)
            : CGFloat(model.circleOpacity)
        let textAlpha = isAnySelected
            ? max(CGFloat(model.textOpacity), 0.98)
            : CGFloat(model.textOpacity)

        let backgroundColor: CGColor
        let borderColor: CGColor
        let borderWidth: CGFloat
        let animateSelectionFill = shouldAnimateNextSelectionFill && model.isSelectable && isFocusedRow
        shouldAnimateNextSelectionFill = false
        if isDraggingRow {
            backgroundColor = NSColor.clear.cgColor
            borderColor = preferences.subtleStrokeColor.cgColor
            borderWidth = 1.0
        } else if model.isSelectable && (isFocusedRow || isRangeSelected) {
            backgroundColor = activeFillColor.cgColor
            borderColor = NSColor.clear.cgColor
            borderWidth = 0.0
        } else {
            backgroundColor = NSColor.clear.cgColor
            borderColor = NSColor.clear.cgColor
            borderWidth = 0.0
        }

        updateBackgroundAppearance(
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            borderWidth: borderWidth,
            animate: animateSelectionFill
        )
        circleView.contentTintColor = preferences.resolvedContentColor(multiplier: circleAlpha)
        textLabel.attributedStringValue = attributedText(alphaMultiplier: textAlpha)
        editingTextView.text = model.text
        editingTextView.textColor = preferences.resolvedContentColor(multiplier: textAlpha)
        editingTextView.showsStrikethrough = model.showsStrikethrough
        editingTextView.selectionColor = preferences.selectionOverlayColor
        editingTextView.caretColor = preferences.caretColor
        editingTextView.visualVerticalOffset = CGFloat(preferences.displayTextVerticalOffset)
        let showsEditorHost = isEditingRow && model.isEditable
        if !showsEditorHost {
            editingTextView.selectionRange = NSRange(location: 0, length: 0)
            editingTextView.showsCaret = false
        }
        textLabel.isHidden = true
        editingTextView.isHidden = false
        editorHostView.isHidden = true
        cursorShieldView.isHidden = true

        if isDraggingRow {
            backgroundView.alphaValue = 1.0
            textLabel.alphaValue = 0.0
            editingTextView.alphaValue = 0.0
            circleView.alphaValue = 0.0
        } else {
            backgroundView.alphaValue = 1.0
            textLabel.alphaValue = 0.0
            editingTextView.alphaValue = 1.0
            circleView.alphaValue = 1.0
        }

        updateScaleTransform()
    }

    private func updateBackgroundAppearance(
        backgroundColor: CGColor,
        borderColor: CGColor,
        borderWidth: CGFloat,
        animate: Bool
    ) {
        guard let layer = backgroundView.layer else { return }

        let currentBackground = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        let currentBorderColor = layer.presentation()?.borderColor ?? layer.borderColor
        let currentBorderWidth = layer.presentation()?.borderWidth ?? layer.borderWidth

        let shouldAnimate = animate && window != nil && !isDraggingRow

        if shouldAnimate, let currentBackground {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = currentBackground
            animation.toValue = backgroundColor
            animation.duration = preferences.motion.collapse
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "rowBackgroundColor")
        }

        if shouldAnimate, let currentBorderColor {
            let animation = CABasicAnimation(keyPath: "borderColor")
            animation.fromValue = currentBorderColor
            animation.toValue = borderColor
            animation.duration = preferences.motion.collapse
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "rowBorderColor")
        }

        if shouldAnimate {
            let animation = CABasicAnimation(keyPath: "borderWidth")
            animation.fromValue = currentBorderWidth
            animation.toValue = borderWidth
            animation.duration = preferences.motion.collapse
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "rowBorderWidth")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = backgroundColor
        layer.borderColor = borderColor
        layer.borderWidth = borderWidth
        CATransaction.commit()
    }

    private func attributedText(alphaMultiplier: CGFloat) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: preferences.resolvedContentColor(multiplier: alphaMultiplier),
            .font: preferences.appFont(),
            .strikethroughStyle: model.showsStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
        ]
        return NSAttributedString(string: model.text, attributes: attributes)
    }

    private func fontLineHeight(for font: NSFont?) -> CGFloat {
        guard let font else { return 16 }
        return alignToHalfBackingPixel(font.ascender - font.descender + font.leading)
    }

    private func alignToHalfBackingPixel(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        guard scale > 0 else { return value }
        return round(value * scale * 2.0) / (scale * 2.0)
    }

    private func convertedLabelContentFrame() -> NSRect {
        guard let cell = textLabel.cell as? NSTextFieldCell else { return textLabel.frame }
        return textLabel.convert(cell.drawingRect(forBounds: textLabel.bounds), to: self)
    }

    private func updateScaleTransform() {
        guard let layer else { return }

        let targetScale: CGFloat
        if isDraggingRow {
            targetScale = 1.0
        } else if isPressedRow {
            targetScale = AppearanceMetrics.pressedScale
        } else {
            targetScale = 1.0
        }

        let currentTransform = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        let targetTransform = centeredSublayerScaleTransform(scale: targetScale)

        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = currentTransform
        animation.toValue = targetTransform
        animation.duration = AppearanceMetrics.pressAnimationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "rowPressScale")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = targetTransform
        CATransaction.commit()
    }

    private func centeredSublayerScaleTransform(scale: CGFloat) -> CATransform3D {
        let centerX = bounds.midX
        let centerY = bounds.midY

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, centerX, centerY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -centerX, -centerY, 0)
        return transform
    }
}

private final class PassiveEditorHostView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class EditingTextDisplayView: NSView {
    var text: String = "" {
        didSet {
            updateHorizontalOffset()
            needsDisplay = true
        }
    }

    var selectionRange: NSRange = NSRange(location: 0, length: 0) {
        didSet {
            updateHorizontalOffset()
            needsDisplay = true
        }
    }

    var showsCaret = false {
        didSet { needsDisplay = true }
    }

    var font: NSFont = .systemFont(ofSize: 13) {
        didSet {
            updateHorizontalOffset()
            needsDisplay = true
        }
    }

    var textColor: NSColor = .white {
        didSet {
            needsDisplay = true
        }
    }

    var showsStrikethrough = false {
        didSet { needsDisplay = true }
    }

    var selectionColor: NSColor = NSColor.white.withAlphaComponent(0.18) {
        didSet { needsDisplay = true }
    }

    var caretColor: NSColor = NSColor.white.withAlphaComponent(0.95) {
        didSet { needsDisplay = true }
    }

    var visualVerticalOffset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    private var horizontalOffset: CGFloat = 0

    func restoreDisplayState(text: String, showsStrikethrough: Bool) {
        self.text = text
        self.showsStrikethrough = showsStrikethrough
        horizontalOffset = 0
        selectionRange = NSRange(location: 0, length: 0)
        showsCaret = false
        needsDisplay = true
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func addCursorRect(_ rect: NSRect, cursor: NSCursor) {
        super.addCursorRect(rect, cursor: .arrow)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        updateHorizontalOffset()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let nsText = text as NSString
        let clampedLocation = max(0, min(selectionRange.location, nsText.length))
        let clampedLength = max(0, min(selectionRange.length, nsText.length - clampedLocation))
        let selectionEnd = clampedLocation + clampedLength
        let contentRect = visualContentRect
        let startX = contentRect.minX + width(toUTF16Index: clampedLocation) - horizontalOffset
        let endX = contentRect.minX + width(toUTF16Index: selectionEnd) - horizontalOffset

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()

        if clampedLength > 0 {
            let highlightX = max(contentRect.minX, startX)
            let highlightWidth = min(contentRect.maxX, endX) - highlightX
            if highlightWidth > 0 {
                let highlightRect = NSRect(x: highlightX, y: contentRect.minY, width: highlightWidth, height: contentRect.height)
                selectionColor.setFill()
                NSBezierPath(roundedRect: highlightRect, xRadius: 4, yRadius: 4).fill()
            }
        }

        let drawRect = NSRect(
            x: contentRect.minX - horizontalOffset,
            y: contentRect.minY,
            width: max(contentRect.width + horizontalOffset, 1),
            height: contentRect.height
        )
        NSAttributedString(string: text, attributes: textAttributes())
            .draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])

        if showsCaret {
            let caretX = contentRect.minX + width(toUTF16Index: clampedLocation) - horizontalOffset
            if caretX >= contentRect.minX - 1 && caretX <= contentRect.maxX + 1 {
                let caretRect = NSRect(x: floor(caretX), y: contentRect.minY, width: 1.5, height: contentRect.height)
                caretColor.setFill()
                NSBezierPath(rect: caretRect).fill()
            }
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func updateHorizontalOffset() {
        let caretIndex = min((text as NSString).length, selectionRange.location + selectionRange.length)
        let caretX = width(toUTF16Index: caretIndex)
        let padding: CGFloat = 8
        let contentRect = alignedContentRect()
        let availableWidth = max(1, contentRect.width - padding)

        var newOffset = horizontalOffset
        if caretX - newOffset > availableWidth {
            newOffset = caretX - availableWidth
        }
        if caretX - newOffset < 0 {
            newOffset = max(0, caretX - padding)
        }

        let maxOffset = max(0, width(toUTF16Index: (text as NSString).length) - contentRect.width + padding)
        horizontalOffset = min(max(newOffset, 0), maxOffset)
    }

    private func width(toUTF16Index index: Int) -> CGFloat {
        let nsText = text as NSString
        let safeIndex = max(0, min(index, nsText.length))
        let prefix = nsText.substring(to: safeIndex) as NSString
        let width = prefix.size(withAttributes: [.font: font]).width
        return ceil(width)
    }

    var debugContentRect: NSRect {
        alignedContentRect()
    }

    var visualContentRect: NSRect {
        alignedContentRect().offsetBy(dx: 0, dy: visualVerticalOffset)
    }

    private func textAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
            .strikethroughStyle: showsStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
        ]
    }

    private func alignedContentRect() -> NSRect {
        let lineHeight = alignToHalfBackingPixel(font.ascender - font.descender + font.leading)
        let y = alignToHalfBackingPixel((bounds.height - lineHeight) / 2)
        return NSRect(x: 0, y: y, width: bounds.width, height: lineHeight)
    }

    private func alignToHalfBackingPixel(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        guard scale > 0 else { return value }
        return round(value * scale * 2.0) / (scale * 2.0)
    }
}

private final class CursorShieldView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func addCursorRect(_ rect: NSRect, cursor: NSCursor) {
        super.addCursorRect(rect, cursor: .arrow)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

private final class KeyboardOnlyTextField: NSTextField {
    override var mouseDownCanMoveWindow: Bool { false }

    override func addCursorRect(_ rect: NSRect, cursor: NSCursor) {
        super.addCursorRect(rect, cursor: .arrow)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}

class PressScaleButton: NSButton {
    var pressedScale: CGFloat = 0.97
    var suppressSystemHighlight = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func highlight(_ flag: Bool) {
        guard !suppressSystemHighlight else { return }
        super.highlight(flag)
    }

    override func mouseDown(with event: NSEvent) {
        setPressedAppearance(true, duration: 0.08)
        super.mouseDown(with: event)
        setPressedAppearance(false, duration: 0.12)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCellHighlightBehavior()
    }

    private func setPressedAppearance(_ pressed: Bool, duration: CFTimeInterval) {
        wantsLayer = true
        guard let layer else { return }

        let scale = pressed ? pressedScale : 1
        let targetTransform = centeredPressTransform(scale: scale)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = layer.presentation()?.transform ?? layer.transform
        animation.toValue = targetTransform
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.removeAnimation(forKey: "pressScale")
        layer.add(animation, forKey: "pressScale")
        layer.transform = targetTransform
    }

    private func centeredPressTransform(scale: CGFloat) -> CATransform3D {
        let centerX = bounds.midX
        let centerY = bounds.midY

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, centerX, centerY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -centerX, -centerY, 0)
        return transform
    }

    private func updateCellHighlightBehavior() {
        guard suppressSystemHighlight, let cell = cell as? NSButtonCell else { return }
        cell.highlightsBy = []
        cell.showsStateBy = []
    }
}

final class HoverTrackingButton: PressScaleButton {
    var onHoverChange: ((Bool) -> Void)?

    private(set) var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            onHoverChange?(isHovered)
        }
    }

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
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

public final class CaretEndFieldEditor: NSTextView {
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func addCursorRect(_ rect: NSRect, cursor: NSCursor) {
        super.addCursorRect(rect, cursor: .arrow)
    }

    public override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .arrow)
    }

    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    public override func mouseDown(with event: NSEvent) {}
    public override func mouseDragged(with event: NSEvent) {}
    public override func mouseUp(with event: NSEvent) {}

    public override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        if charRange.length == string.count && charRange.length > 0 && !flag {
            super.setSelectedRange(NSRange(location: string.count, length: 0), affinity: affinity, stillSelecting: flag)
        } else {
            super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        }
    }
}
#endif

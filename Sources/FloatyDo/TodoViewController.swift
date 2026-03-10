import AppKit
import Combine
import os.log
import QuartzCore

private let logger = Logger(subsystem: "com.floatydo", category: "TodoVC")

public enum Tab { case tasks, archive }

private struct TaskDraftState {
    var insertionIndex: Int
    var text: String

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedText.isEmpty
    }
}

fileprivate protocol TodoListViewDelegate: AnyObject {
    func listView(_ listView: TodoListView, didActivateRow rowID: TodoRowID)
    func listView(_ listView: TodoListView, didActivateCheckboxFor rowID: TodoRowID)
    func listViewWillPressRowBody(_ listView: TodoListView, rowID: TodoRowID)
    func listViewWillBeginDragging(_ listView: TodoListView, rowID: TodoRowID)
    func listView(_ listView: TodoListView, didFinishDraggingRow rowID: TodoRowID, orderedItemIDs: [UUID])
}

public final class TodoViewController: NSViewController, NSTextFieldDelegate {
    private let store: TodoStore
    private let listView = TodoListView()
    private let sharedEditor = KeyboardOnlyTextField()

    private var selectedRowID: TodoRowID?
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
    private var archiveTabButton: NSButton!
    private var settingsButton: HoverTrackingButton!
    private var settingsWindowController: SettingsWindowController?
    private var isAnimating = false

    public init(store: TodoStore) {
        self.store = store
        self.taskDraft = TaskDraftState(insertionIndex: store.items.count, text: "")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var motion: MotionProfile { store.preferences.motion }
    private var rowHeight: CGFloat { CGFloat(store.preferences.rowHeight) }
    private var panelWidth: CGFloat { CGFloat(store.preferences.panelWidth) }
    private var rowCount: Int { rowModels.count }
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

    private var currentEditingRowID: TodoRowID? {
        guard !isAnimating, !listView.isDragging else { return nil }
        guard let selectedModel else { return nil }
        guard deferredEditorRowID != selectedModel.id else { return nil }
        return selectedModel.isEditable ? selectedModel.id : nil
    }

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 240))
        container.wantsLayer = true

        tasksTabButton = makeTabButton(symbolName: "checklist.unchecked", action: #selector(switchToTasks))
        archiveTabButton = makeTabButton(symbolName: "archivebox", action: #selector(switchToArchive))
        settingsButton = makeHoverTabButton(symbolName: "paintpalette", action: #selector(toggleSettings(_:)))
        settingsButton.onHoverChange = { [weak self] _ in
            self?.updateTabAppearance()
        }

        let tabBar = NSStackView(views: [tasksTabButton, archiveTabButton, settingsButton])
        tabBar.orientation = .horizontal
        tabBar.spacing = 0
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabBar)

        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.delegate = self
        sharedEditor.frame = NSRect(x: -1000, y: -1000, width: 1, height: 1)
        sharedEditor.alphaValue = 0.001

        container.addSubview(listView)
        container.addSubview(sharedEditor)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LayoutMetrics.titlebarTrailingInset),

            listView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: LayoutMetrics.contentTopPadding),
            listView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
        updateTabAppearance()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureSharedEditor()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !self.isAnimating, !self.listView.isBusy else { return event }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command {
                switch event.keyCode {
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

            let firstResponder = self.view.window?.firstResponder
            let listOwnsFocus = firstResponder === self.listView || firstResponder === self.view
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
            } else if mods == .shift, event.keyCode == 48 {
                self.moveUp()
                return nil
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
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.preferencesDidChange()
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
        refreshRows(resize: false, animateResize: false, placeCaretAtEnd: false)
        resizeWindow(animate: false)
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

    private func preferencesDidChange() {
        sharedEditor.font = store.preferences.appFont()
        settingsWindowController?.updatePreferences(store.preferences)
        if let panel = view.window as? FloatingPanel {
            panel.applyTheme(preferences: store.preferences)
        }
        updateTabAppearance()
        refreshRows(animateResize: false)
    }

    private func makeTabButton(symbolName: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let button = NSButton(image: image.withSymbolConfiguration(config)!, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func makeHoverTabButton(symbolName: String, action: Selector) -> HoverTrackingButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let button = HoverTrackingButton(image: image.withSymbolConfiguration(config)!, target: self, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func updateTabAppearance() {
        let primary = store.preferences.primaryTextColor
        tasksTabButton.contentTintColor = currentTab == .tasks ? primary : primary.withAlphaComponent(0.35)
        archiveTabButton.contentTintColor = currentTab == .archive ? primary : primary.withAlphaComponent(0.35)
        let settingsIsEmphasized = settingsWindowController?.window?.isVisible == true || settingsButton.isHovered
        settingsButton.contentTintColor = settingsIsEmphasized ? primary : primary.withAlphaComponent(0.42)
    }

    @objc private func switchToTasks() {
        guard currentTab != .tasks else { return }
        cancelDeferredEditorActivation()
        currentTab = .tasks
        selectedRowID = nil
        updateTabAppearance()
        refreshRows(resize: false, animateResize: false)
    }

    @objc private func switchToArchive() {
        guard currentTab != .archive else { return }
        cancelDeferredEditorActivation()
        currentTab = .archive
        selectedRowID = nil
        updateTabAppearance()
        refreshRows(resize: false, animateResize: false)
    }

    @objc private func toggleSettings(_ sender: NSButton) {
        if let window = settingsWindowController?.window, window.isVisible {
            window.close()
            return
        }

        openSettingsWindow()
    }

    func closeSettingsWindowIfVisible() -> Bool {
        guard let window = settingsWindowController?.window, window.isVisible else {
            return false
        }
        window.close()
        return true
    }

    func openSettingsWindow() {
        let controller = settingsWindowController ?? SettingsWindowController(preferences: store.preferences)
        controller.onPreferencesChange = { [weak self] preferences in
            self?.store.updatePreferences(preferences)
        }
        controller.onWindowVisibilityChange = { [weak self] _ in
            self?.updateTabAppearance()
        }
        controller.updatePreferences(store.preferences)
        settingsWindowController = controller
        updateTabAppearance()
        controller.present()
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
        refreshRows(placeCaretAtEnd: false)
        return insertedItem
    }

    private func activateDraft(at insertionIndex: Int, placeCaretAtEnd: Bool = true) {
        guard canShowDraftRow else { return }
        setDraftPosition(insertionIndex, text: "")
        selectedRowID = .taskDraft
        refreshRows(placeCaretAtEnd: placeCaretAtEnd)
    }

    private func convertItemToDraft(_ item: TodoItem, newText: String) {
        guard let itemIndex = store.items.firstIndex(where: { $0.id == item.id }) else { return }
        store.deleteItem(id: item.id)
        setDraftPosition(itemIndex, text: newText)
        selectedRowID = .taskDraft
        refreshRows(placeCaretAtEnd: false)
    }

    private func buildRowModels(for tab: Tab? = nil) -> [TodoRowModel] {
        switch tab ?? currentTab {
        case .tasks:
            let showsDraft = canShowDraftRow
            let visibleRowCount = min(store.items.count + 3, TodoStore.maxItems)
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
            let visibleRowCount = max(store.archivedItems.count, 3)
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
        resize: Bool = true,
        animateResize: Bool = true,
        animatedLayout: Bool = false,
        animatedLayoutDuration: CFTimeInterval? = nil,
        selectionRevealRowID: TodoRowID? = nil,
        placeCaretAtEnd: Bool = true
    ) {
        rowModels = buildRowModels()
        ensureSelectedRowExists()
        listView.apply(
            models: rowModels,
            selectedRowID: selectedRowID,
            editingRowID: currentEditingRowID,
            preferences: store.preferences,
            animatedLayout: animatedLayout,
            animatedLayoutDuration: animatedLayoutDuration,
            selectionRevealRowID: selectionRevealRowID
        )

        if resize {
            resizeWindow(animate: animateResize)
        }

        listView.layoutSubtreeIfNeeded()
        attachEditorIfNeeded(placeCaretAtEnd: placeCaretAtEnd)
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
            return
        }

        guard rowModels.contains(where: { $0.id == selectedRowID && $0.isSelectable }) else {
            self.selectedRowID = buildSelectionID(in: rowModels, selectableIndex: 0)
            return
        }
    }

    private func buildSelectionID(in models: [TodoRowModel], selectableIndex: Int) -> TodoRowID? {
        let selectableRows = models.filter(\.isSelectable)
        guard !selectableRows.isEmpty else { return nil }
        let clampedIndex = max(0, min(selectableIndex, selectableRows.count - 1))
        return selectableRows[clampedIndex].id
    }

    private func nextSelectableIndex(from start: Int, step: Int) -> Int? {
        var index = start + step
        while rowModels.indices.contains(index) {
            if rowModels[index].isSelectable {
                return index
            }
            index += step
        }
        return nil
    }

    private func activateRow(_ rowID: TodoRowID, placeCaretAtEnd: Bool = true) {
        guard rowModels.contains(where: { $0.id == rowID && $0.isSelectable }) else { return }
        cancelDeferredEditorActivation()
        let previousSelectedRowID = selectedRowID
        selectedRowID = rowID
        syncSelectionUI(previousSelectedRowID: previousSelectedRowID, placeCaretAtEnd: placeCaretAtEnd)
    }

    private func syncSelectionUI(previousSelectedRowID: TodoRowID? = nil, placeCaretAtEnd: Bool) {
        listView.updateInteractionState(
            selectedRowID: selectedRowID,
            editingRowID: currentEditingRowID
        )

        if let previousSelectedRowID {
            refreshVisibleModel(for: previousSelectedRowID)
        }
        if let selectedRowID, selectedRowID != previousSelectedRowID {
            refreshVisibleModel(for: selectedRowID)
        }
        listView.layoutSubtreeIfNeeded()
        attachEditorIfNeeded(placeCaretAtEnd: placeCaretAtEnd)
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
        if editorRowID != rowID {
            sharedEditor.stringValue = targetText
            editorRowID = rowID
        } else if sharedEditor.stringValue != targetText {
            logger.debug("attachEditorIfNeeded resetting hidden editor for rowID=\(String(describing: rowID), privacy: .public) from=\"\(self.sharedEditor.stringValue, privacy: .public)\" to=\"\(targetText, privacy: .public)\"")
            sharedEditor.stringValue = targetText
        }

        guard let window = view.window else { return }
        if window.firstResponder !== sharedEditor.currentEditor() {
            window.makeFirstResponder(sharedEditor)
        }

        bindHiddenEditor(placeCaretAtEnd: placeCaretAtEnd)
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

    private func bindHiddenEditor(placeCaretAtEnd: Bool) {
        if let observer = editorSelectionObserver {
            NotificationCenter.default.removeObserver(observer)
            editorSelectionObserver = nil
        }

        let applyBinding = { [weak self] in
            guard let self else { return }
            if let editor = self.sharedEditor.currentEditor() as? NSTextView {
                self.editorSelectionObserver = NotificationCenter.default.addObserver(
                    forName: NSTextView.didChangeSelectionNotification,
                    object: editor,
                    queue: .main
                ) { [weak self] _ in
                    self?.syncVisibleEditorState()
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

    private func handleCommandReturn() {
        cancelDeferredEditorActivation()
        guard let selectedModel else { return }

        switch currentTab {
        case .tasks:
            switch selectedModel.kind {
            case .taskItem(let item):
                animateCompletion(for: item.id)

            case .taskDraft:
                guard let insertedItem = promoteDraftToItem(selectInsertedItem: true) else { return }
                animateCompletion(for: insertedItem.id)

            case .archiveItem, .filler:
                return
            }

        case .archive:
            guard case .archiveItem(let item) = selectedModel.kind else { return }
            let selectionIndex = selectedRowIndex ?? 0
            store.restore(id: item.id)
            let updatedModels = buildRowModels(for: .archive)
            selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
            refreshRows()
        }
    }

    private func handleCommandDelete() {
        cancelDeferredEditorActivation()
        guard let selectedModel else { return }
        let selectionIndex = selectedRowIndex ?? 0

        switch currentTab {
        case .tasks:
            guard case .taskItem(let item) = selectedModel.kind else { return }
            store.deleteItem(id: item.id)
            let updatedModels = buildRowModels(for: .tasks)
            selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
            refreshRows()

        case .archive:
            guard case .archiveItem(let item) = selectedModel.kind else { return }
            store.deleteArchived(id: item.id)
            let updatedModels = buildRowModels(for: .archive)
            selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
            refreshRows()
        }
    }

    private func animateCompletion(for itemID: UUID) {
        guard !isAnimating, !listView.isBusy else { return }
        guard let index = rowModels.firstIndex(where: { $0.itemID == itemID }),
              let row = listView.rowView(for: .taskItem(itemID)) else {
            logger.warning("animateCompletion SKIPPED for itemID=\(itemID)")
            return
        }

        isAnimating = true
        detachEditor(makeListFirstResponder: false)
        row.setEditing(false)

        row.playCompletionAnimation(motion: motion) { [weak self] in
            guard let self else { return }
            self.store.archive(id: itemID)
            let updatedModels = self.buildRowModels(for: .tasks)
            self.selectedRowID = self.buildSelectionID(in: updatedModels, selectableIndex: index)
            self.isAnimating = false
            self.scheduleDeferredEditorActivation(for: self.selectedRowID, delay: self.motion.collapse * 0.75)
            self.refreshRows(
                animatedLayout: true,
                animatedLayoutDuration: self.motion.collapse,
                selectionRevealRowID: self.selectedRowID,
                placeCaretAtEnd: false
            )
        }
    }

    func moveUp() {
        guard !isAnimating, !listView.isBusy else { return }
        if currentTab == .tasks {
            if collapseSelectedDraftForNavigation(step: -1) {
                return
            }

            if case .taskItem(let item)? = selectedModel?.kind,
               let itemIndex = store.items.firstIndex(where: { $0.id == item.id }),
               itemIndex == 0,
               canShowDraftRow {
                activateDraft(at: 0)
                return
            }
        }

        guard let currentIndex = selectedRowIndex,
              let nextIndex = nextSelectableIndex(from: currentIndex, step: -1) else { return }
        activateRow(rowModels[nextIndex].id, placeCaretAtEnd: true)
    }

    func moveDown() {
        guard !isAnimating, !listView.isBusy else { return }
        if currentTab == .tasks, collapseSelectedDraftForNavigation(step: 1) {
            return
        }
        guard let currentIndex = selectedRowIndex,
              let nextIndex = nextSelectableIndex(from: currentIndex, step: 1) else { return }
        activateRow(rowModels[nextIndex].id, placeCaretAtEnd: true)
    }

    func submitRow() {
        guard !isAnimating, !listView.isBusy, currentTab == .tasks else { return }
        guard let selectedModel else { return }

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

    private func resizeWindow(animate: Bool = true) {
        guard let window = view.window else { return }
        let rows = CGFloat(max(rowCount, 1))
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
    fileprivate func listView(_ listView: TodoListView, didActivateRow rowID: TodoRowID) {
        activateRow(rowID, placeCaretAtEnd: true)
        if currentTab == .tasks, rowID != .taskDraft {
            normalizeDraftBeforeStructuralAction()
        }
    }

    fileprivate func listView(_ listView: TodoListView, didActivateCheckboxFor rowID: TodoRowID) {
        guard case .taskItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return }
        animateCompletion(for: item.id)
    }

    fileprivate func listViewWillPressRowBody(_ listView: TodoListView, rowID: TodoRowID) {
        detachEditor(makeListFirstResponder: true)
    }

    fileprivate func listViewWillBeginDragging(_ listView: TodoListView, rowID: TodoRowID) {
        detachEditor(makeListFirstResponder: false)
        view.window?.makeFirstResponder(nil)
    }

    fileprivate func listView(_ listView: TodoListView, didFinishDraggingRow rowID: TodoRowID, orderedItemIDs: [UUID]) {
        store.reorderItems(by: orderedItemIDs)
        selectedRowID = rowID
        refreshRows(resize: false, animateResize: false)
    }
}

private extension NSWindow {
    var titlebarHeight: CGFloat {
        contentView?.safeAreaInsets.top ?? 0
    }
}

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
    private var editingRowID: TodoRowID?
    private var preferences: AppPreferences = .default
    private var pressedRowID: TodoRowID?
    private var selectionRevealRowID: TodoRowID?
    private var interactionState: InteractionState = .idle

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

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
        editingRowID: TodoRowID?,
        preferences: AppPreferences,
        animatedLayout: Bool,
        animatedLayoutDuration: CFTimeInterval? = nil,
        selectionRevealRowID: TodoRowID? = nil
    ) {
        self.preferences = preferences
        self.selectedRowID = selectedRowID
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
            rowView.setSelected(
                model.id == selectedRowID,
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
        rowView.setSelected(
            model.id == selectedRowID,
            animateFill: model.id == selectionRevealRowID && model.id == selectedRowID
        )
        rowView.setEditing(model.id == editingRowID)
        rowView.setPressed(model.id == pressedRowID)
    }

    func updateInteractionState(selectedRowID: TodoRowID?, editingRowID: TodoRowID?) {
        self.selectedRowID = selectedRowID
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
            rowView.setSelected(
                rowID == selectedRowID,
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
                rowView.setSelected(
                    rowID == self.selectedRowID,
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
            rowView.setSelected(
                rowID == selectedRowID,
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
    }

    private let backgroundView = NSView()
    private let circleView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    private let editingTextView = EditingTextDisplayView()
    let editorHostView = PassiveEditorHostView()
    private let cursorShieldView = CursorShieldView()

    private var preferences: AppPreferences
    private(set) var model: TodoRowModel

    private var isRowSelected = false {
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

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = CGFloat(preferences.cornerRadius)
        addSubview(backgroundView)

        circleView.wantsLayer = true
        addSubview(circleView)

        textLabel.font = preferences.appFont()
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.wantsLayer = true
        addSubview(textLabel)

        addSubview(editingTextView)
        addSubview(editorHostView)
        addSubview(cursorShieldView)
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

        let textX = checkboxRect.maxX + LayoutMetrics.textInset
        let textWidth = max(0, bounds.width - textX - LayoutMetrics.rowHorizontalInset)
        let textHeight = max(textLabel.intrinsicContentSize.height, (fontLineHeight(for: textLabel.font) + 2))
        let textY = floor((bounds.height - textHeight) / 2)
        let textFrame = NSRect(x: textX, y: textY, width: textWidth, height: textHeight)
        let activeTextFrame = textFrame.offsetBy(dx: 0, dy: 2)
        textLabel.frame = textFrame
        editingTextView.frame = activeTextFrame
        editorHostView.frame = textFrame
        cursorShieldView.frame = textFrame
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

    func setSelected(_ selected: Bool, animateFill: Bool = false) {
        shouldAnimateNextSelectionFill = animateFill && selected
        isRowSelected = selected
    }

    func setEditing(_ editing: Bool) {
        isEditingRow = editing && model.isEditable
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
        editingTextView.selectionRange = NSRange(location: 0, length: 0)
        editingTextView.showsCaret = false
        editingTextView.needsDisplay = true
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

        if !textLabel.stringValue.isEmpty {
            let textWidth = (textLabel.stringValue as NSString).size(withAttributes: [.font: textLabel.font!]).width
            let strikeLayer = CAShapeLayer()
            let midY = textLabel.frame.midY
            let path = CGMutablePath()
            path.move(to: CGPoint(x: textLabel.frame.minX, y: midY))
            path.addLine(to: CGPoint(x: textLabel.frame.minX + textWidth, y: midY))
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
            textLabel.layer?.add(fadeText, forKey: "fadeText")
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
            self.circleView.contentTintColor = self.preferences.primaryTextColor

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

    private func updateAppearance() {
        let activeFillColor = preferences.activeFillColor
        let baseTextColor = preferences.primaryTextColor
        let circleAlpha = isRowSelected && model.isSelectable
            ? max(CGFloat(model.circleOpacity), model.isDone ? CGFloat(model.textOpacity) : 0.86)
            : CGFloat(model.circleOpacity)
        let textAlpha = isRowSelected && model.isSelectable
            ? max(CGFloat(model.textOpacity), 0.98)
            : CGFloat(model.textOpacity)

        let backgroundColor: CGColor
        let borderColor: CGColor
        let borderWidth: CGFloat
        let animateSelectionFill = shouldAnimateNextSelectionFill && model.isSelectable && isRowSelected
        shouldAnimateNextSelectionFill = false
        if isDraggingRow {
            backgroundColor = NSColor.clear.cgColor
            borderColor = preferences.subtleStrokeColor.cgColor
            borderWidth = 1.0
        } else if model.isSelectable && isRowSelected {
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
        circleView.contentTintColor = baseTextColor.withAlphaComponent(circleAlpha)
        textLabel.attributedStringValue = attributedText(alpha: textAlpha)
        editingTextView.textColor = baseTextColor.withAlphaComponent(textAlpha)
        editingTextView.selectionColor = preferences.selectionOverlayColor
        editingTextView.caretColor = preferences.caretColor
        let showsEditorHost = isEditingRow && model.isEditable
        if showsEditorHost {
            editingTextView.text = model.text
        }
        textLabel.isHidden = showsEditorHost
        editingTextView.isHidden = !showsEditorHost
        editorHostView.isHidden = true
        cursorShieldView.isHidden = true

        if isDraggingRow {
            backgroundView.alphaValue = 1.0
            textLabel.alphaValue = 0.0
            editingTextView.alphaValue = 0.0
            circleView.alphaValue = 0.0
        } else {
            backgroundView.alphaValue = 1.0
            textLabel.alphaValue = 1.0
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

    private func attributedText(alpha: CGFloat) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: preferences.primaryTextColor.withAlphaComponent(alpha),
            .font: preferences.appFont(),
            .strikethroughStyle: model.showsStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
        ]
        return NSAttributedString(string: model.text, attributes: attributes)
    }

    private func fontLineHeight(for font: NSFont?) -> CGFloat {
        guard let font else { return 16 }
        return ceil(font.ascender - font.descender + font.leading)
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
    private let alignmentCell = NSTextFieldCell(textCell: "")

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
            alignmentCell.font = font
            updateHorizontalOffset()
            needsDisplay = true
        }
    }

    var textColor: NSColor = .white {
        didSet {
            alignmentCell.textColor = textColor
            needsDisplay = true
        }
    }

    var selectionColor: NSColor = NSColor.white.withAlphaComponent(0.18) {
        didSet { needsDisplay = true }
    }

    var caretColor: NSColor = NSColor.white.withAlphaComponent(0.95) {
        didSet { needsDisplay = true }
    }

    private var horizontalOffset: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alignmentCell.font = font
        alignmentCell.textColor = textColor
        alignmentCell.lineBreakMode = .byTruncatingTail
        alignmentCell.isScrollable = true
        alignmentCell.usesSingleLineMode = true
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
        let contentRect = alignedContentRect()
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
            x: floor(contentRect.minX - horizontalOffset),
            y: floor(contentRect.minY),
            width: max(contentRect.width + horizontalOffset, 1),
            height: contentRect.height
        )
        alignmentCell.title = text
        alignmentCell.drawInterior(withFrame: drawRect, in: self)

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

    private func fontLineHeight() -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private func alignedContentRect() -> NSRect {
        alignmentCell.title = text
        return alignmentCell.drawingRect(forBounds: bounds)
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

final class HoverTrackingButton: NSButton {
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

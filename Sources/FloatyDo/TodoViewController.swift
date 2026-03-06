import AppKit
import Combine
import os.log
import QuartzCore

private let logger = Logger(subsystem: "com.floatydo", category: "TodoVC")

public enum Tab { case tasks, archive }

fileprivate protocol TodoListViewDelegate: AnyObject {
    func listView(_ listView: TodoListView, didActivateRow rowID: TodoRowID)
    func listView(_ listView: TodoListView, didActivateCheckboxFor rowID: TodoRowID)
    func listViewWillBeginDragging(_ listView: TodoListView, rowID: TodoRowID)
    func listView(_ listView: TodoListView, didFinishDraggingRow rowID: TodoRowID, orderedItemIDs: [UUID])
}

public final class TodoViewController: NSViewController, NSPopoverDelegate, NSTextFieldDelegate {
    private let store: TodoStore
    private let listView = TodoListView()
    private let sharedEditor = KeyboardOnlyTextField()

    private var selectedRowID: TodoRowID?
    private var editorRowID: TodoRowID?
    private var rowModels: [TodoRowModel] = []
    private var taskInputDraft = ""
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var currentTab: Tab = .tasks
    private var tasksTabButton: NSButton!
    private var archiveTabButton: NSButton!
    private var settingsButton: NSButton!
    private var settingsPopover: NSPopover?
    private var isAnimating = false

    public init(store: TodoStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var motion: MotionProfile { store.preferences.motion }
    private var rowHeight: CGFloat { CGFloat(store.preferences.rowHeight) }
    private var panelWidth: CGFloat { CGFloat(store.preferences.panelWidth) }
    private var rowCount: Int { rowModels.count }
    private var inputIndex: Int { store.items.count }
    private var selectedRowIndex: Int? {
        guard let selectedRowID else { return nil }
        return rowModels.firstIndex(where: { $0.id == selectedRowID })
    }

    private var selectedModel: TodoRowModel? {
        guard let selectedRowIndex else { return nil }
        return rowModels[selectedRowIndex]
    }

    private var currentEditingRowID: TodoRowID? {
        guard !isAnimating, !listView.isDragging else { return nil }
        guard let selectedModel else { return nil }
        return selectedModel.isEditable ? selectedModel.id : nil
    }

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 240))
        container.wantsLayer = true

        tasksTabButton = makeTabButton(symbolName: "checklist.unchecked", action: #selector(switchToTasks))
        archiveTabButton = makeTabButton(symbolName: "archivebox", action: #selector(switchToArchive))
        settingsButton = makeTabButton(symbolName: "slider.horizontal.3", action: #selector(toggleSettings(_:)))

        let tabBar = NSStackView(views: [tasksTabButton, archiveTabButton, settingsButton])
        tabBar.orientation = .horizontal
        tabBar.spacing = 0
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabBar)

        listView.translatesAutoresizingMaskIntoConstraints = false
        listView.delegate = self

        container.addSubview(listView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LayoutMetrics.titlebarTrailingInset),

            listView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
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
        refreshRows(resize: false, animateResize: false, placeCaretAtEnd: false)
        resizeWindow(animate: false)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func configureSharedEditor() {
        sharedEditor.isBordered = false
        sharedEditor.drawsBackground = false
        sharedEditor.font = .systemFont(ofSize: 13)
        sharedEditor.focusRingType = .none
        sharedEditor.lineBreakMode = .byTruncatingTail
        sharedEditor.cell?.isScrollable = true
        sharedEditor.wantsLayer = true
        sharedEditor.delegate = self
        sharedEditor.autoresizingMask = [.width, .height]
    }

    private func preferencesDidChange() {
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

    private func updateTabAppearance() {
        tasksTabButton.contentTintColor = currentTab == .tasks ? .white : .white.withAlphaComponent(0.35)
        archiveTabButton.contentTintColor = currentTab == .archive ? .white : .white.withAlphaComponent(0.35)
        settingsButton.contentTintColor = settingsPopover?.isShown == true ? .white : .white.withAlphaComponent(0.55)
    }

    @objc private func switchToTasks() {
        guard currentTab != .tasks else { return }
        currentTab = .tasks
        selectedRowID = nil
        updateTabAppearance()
        refreshRows(resize: false, animateResize: false)
    }

    @objc private func switchToArchive() {
        guard currentTab != .archive else { return }
        currentTab = .archive
        selectedRowID = nil
        updateTabAppearance()
        refreshRows(resize: false, animateResize: false)
    }

    @objc private func toggleSettings(_ sender: NSButton) {
        if let popover = settingsPopover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let settingsController = SettingsViewController(preferences: store.preferences)
        settingsController.onPreferencesChange = { [weak self] preferences in
            self?.store.updatePreferences(preferences)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = settingsController
        settingsPopover = popover
        updateTabAppearance()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    public func popoverDidClose(_ notification: Notification) {
        updateTabAppearance()
    }

    private func buildRowModels(for tab: Tab? = nil) -> [TodoRowModel] {
        switch tab ?? currentTab {
        case .tasks:
            let visibleRowCount = min(store.items.count + 3, TodoStore.maxItems)
            let emptyCount = max(visibleRowCount - store.items.count, 1)

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

            models.append(
                TodoRowModel(
                    id: .taskInput,
                    kind: .taskInput,
                    text: taskInputDraft,
                    isDone: false,
                    isEditable: true,
                    isSelectable: true,
                    canComplete: false,
                    canDrag: false,
                    circleOpacity: fadeOpacity(emptyIndex: 0, emptyCount: emptyCount),
                    textOpacity: 0.92,
                    showsStrikethrough: false
                )
            )

            if emptyCount > 1 {
                for fillerIndex in 1..<emptyCount {
                    models.append(
                        TodoRowModel(
                            id: .taskFiller(fillerIndex),
                            kind: .filler,
                            text: "",
                            isDone: false,
                            isEditable: false,
                            isSelectable: false,
                            canComplete: false,
                            canDrag: false,
                            circleOpacity: fadeOpacity(emptyIndex: fillerIndex, emptyCount: emptyCount),
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
        placeCaretAtEnd: Bool = true
    ) {
        rowModels = buildRowModels()
        ensureSelectedRowExists()
        listView.apply(
            models: rowModels,
            selectedRowID: selectedRowID,
            editingRowID: currentEditingRowID,
            preferences: store.preferences,
            animatedLayout: animatedLayout
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

        case .taskInput:
            guard let existingModel = rowModels.first(where: { $0.id == .taskInput }) else { return nil }
            return TodoRowModel(
                id: .taskInput,
                kind: .taskInput,
                text: taskInputDraft,
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
        guard let rowID = currentEditingRowID,
              let rowView = listView.rowView(for: rowID)
        else {
            detachEditor(makeListFirstResponder: true)
            return
        }

        if editorRowID != rowID {
            let previousEditorRowID = editorRowID
            sharedEditor.removeFromSuperview()
            if let previousEditorRowID, let previousRowView = listView.rowView(for: previousEditorRowID) {
                previousRowView.refreshMountedEditorState()
            }
            sharedEditor.frame = rowView.editorHostView.bounds
            rowView.editorHostView.addSubview(sharedEditor)
            sharedEditor.stringValue = textForRow(rowID)
            editorRowID = rowID
        } else if sharedEditor.superview !== rowView.editorHostView {
            let previousEditorRowID = editorRowID
            sharedEditor.removeFromSuperview()
            if let previousEditorRowID, let previousRowView = listView.rowView(for: previousEditorRowID) {
                previousRowView.refreshMountedEditorState()
            }
            sharedEditor.frame = rowView.editorHostView.bounds
            rowView.editorHostView.addSubview(sharedEditor)
        }

        sharedEditor.frame = rowView.editorHostView.bounds
        rowView.refreshMountedEditorState()

        guard let window = view.window else { return }
        if window.firstResponder !== sharedEditor.currentEditor() {
            window.makeFirstResponder(sharedEditor)
        }
        if placeCaretAtEnd {
            moveCaretToEnd()
        }
    }

    private func detachEditor(makeListFirstResponder shouldFocusList: Bool) {
        guard editorRowID != nil || sharedEditor.superview != nil else {
            if shouldFocusList {
                makeListFirstResponder()
            }
            return
        }

        let previousEditorRowID = editorRowID
        sharedEditor.removeFromSuperview()
        editorRowID = nil
        if let previousEditorRowID, let previousRowView = listView.rowView(for: previousEditorRowID) {
            previousRowView.refreshMountedEditorState()
        }
        if shouldFocusList {
            makeListFirstResponder()
        }
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

    private func textForRow(_ rowID: TodoRowID) -> String {
        rowModels.first(where: { $0.id == rowID })?.text ?? ""
    }

    private func handleCommandReturn() {
        guard let selectedModel else { return }

        switch currentTab {
        case .tasks:
            switch selectedModel.kind {
            case .taskItem(let item):
                animateCompletion(for: item.id)

            case .taskInput:
                let text = taskInputDraft.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                store.add(text)
                taskInputDraft = ""
                guard let newItemID = store.items.last?.id else {
                    refreshRows()
                    return
                }
                refreshRows()
                animateCompletion(for: newItemID)

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
            self.listView.animateRemoval(of: .taskItem(itemID), duration: self.motion.collapse) {
                self.store.archive(id: itemID)
                let updatedModels = self.buildRowModels(for: .tasks)
                self.selectedRowID = self.buildSelectionID(in: updatedModels, selectableIndex: index)
                self.isAnimating = false
                self.refreshRows()
            }
        }
    }

    func moveUp() {
        guard !isAnimating, !listView.isBusy else { return }
        guard let currentIndex = selectedRowIndex,
              let nextIndex = nextSelectableIndex(from: currentIndex, step: -1) else { return }
        activateRow(rowModels[nextIndex].id, placeCaretAtEnd: true)
    }

    func moveDown() {
        guard !isAnimating, !listView.isBusy else { return }
        guard let currentIndex = selectedRowIndex,
              let nextIndex = nextSelectableIndex(from: currentIndex, step: 1) else { return }
        activateRow(rowModels[nextIndex].id, placeCaretAtEnd: true)
    }

    func submitRow() {
        guard !isAnimating, !listView.isBusy, currentTab == .tasks else { return }
        guard let selectedModel, let currentIndex = selectedRowIndex else { return }

        switch selectedModel.kind {
        case .taskItem:
            if let nextIndex = nextSelectableIndex(from: currentIndex, step: 1) {
                activateRow(rowModels[nextIndex].id, placeCaretAtEnd: true)
            }

        case .taskInput:
            let text = taskInputDraft.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            store.add(text)
            taskInputDraft = ""
            selectedRowID = .taskInput
            refreshRows()

        case .archiveItem, .filler:
            return
        }
    }

    private func resizeWindow(animate: Bool = true) {
        guard let window = view.window else { return }
        let rows = CGFloat(max(rowCount, 1))
        let contentHeight = rows * rowHeight + LayoutMetrics.contentBottomPadding
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

        window.setFrame(newFrame, display: true, animate: animate)
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let rowID = editorRowID else { return }
        switch rowModels.first(where: { $0.id == rowID })?.kind {
        case .taskItem(let item):
            store.updateText(for: item.id, to: sharedEditor.stringValue)
        case .taskInput:
            taskInputDraft = sharedEditor.stringValue
        case .archiveItem, .filler, .none:
            break
        }
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
        default:
            return false
        }
    }
}

extension TodoViewController: TodoListViewDelegate {
    fileprivate func listView(_ listView: TodoListView, didActivateRow rowID: TodoRowID) {
        guard rowID != selectedRowID else { return }
        activateRow(rowID, placeCaretAtEnd: true)
    }

    fileprivate func listView(_ listView: TodoListView, didActivateCheckboxFor rowID: TodoRowID) {
        guard case .taskItem(let item) = rowModels.first(where: { $0.id == rowID })?.kind else { return }
        animateCompletion(for: item.id)
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
        var currentTaskIndex: Int
    }

    private enum InteractionState {
        case idle
        case pressed(PressState)
        case dragging(DragSession)
        case settling
    }

    private enum InteractionMetrics {
        static let dragStartDistance: CGFloat = 3.5
        static let dragSwapHysteresisFactor: CGFloat = 0.18
    }

    weak var delegate: TodoListViewDelegate?

    private var rowModelsByID: [TodoRowID: TodoRowModel] = [:]
    private var displayOrder: [TodoRowID] = []
    private var rowViews: [TodoRowID: TodoRowView] = [:]
    private var selectedRowID: TodoRowID?
    private var editingRowID: TodoRowID?
    private var preferences: AppPreferences = .default
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
        animatedLayout: Bool
    ) {
        self.preferences = preferences
        self.selectedRowID = selectedRowID
        self.editingRowID = editingRowID
        rowModelsByID = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })

        let incomingIDs = Set(models.map(\.id))
        for staleID in rowViews.keys where !incomingIDs.contains(staleID) {
            rowViews[staleID]?.removeFromSuperview()
            rowViews.removeValue(forKey: staleID)
        }

        for model in models {
            let rowView = rowViews[model.id] ?? TodoRowView(model: model, preferences: preferences)
            rowView.configure(model: model, preferences: preferences)
            rowView.setSelected(model.id == selectedRowID)
            rowView.setEditing(model.id == editingRowID)
            if rowViews[model.id] == nil {
                rowViews[model.id] = rowView
                addSubview(rowView)
            }
        }

        if !isDragging {
            displayOrder = models.map(\.id)
        }

        layoutRows(animated: animatedLayout)
    }

    func updateModel(_ model: TodoRowModel) {
        rowModelsByID[model.id] = model
        guard let rowView = rowViews[model.id] else { return }
        rowView.configure(model: model, preferences: preferences)
        rowView.setSelected(model.id == selectedRowID)
        rowView.setEditing(model.id == editingRowID)
    }

    func updateInteractionState(selectedRowID: TodoRowID?, editingRowID: TodoRowID?) {
        self.selectedRowID = selectedRowID
        self.editingRowID = editingRowID
        refreshRowVisualState(excluding: currentDraggedRowID)
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
        layoutRows(animated: false)
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
                    refreshRowVisualState()
                    delegate?.listView(self, didActivateCheckboxFor: press.rowID)
                    return
                }
            }

            interactionState = .idle

            if press.rowWasActive {
                editingRowID = press.previousEditingRowID
                refreshRowVisualState()
            } else {
                refreshRowVisualState()
                delegate?.listView(self, didActivateRow: press.rowID)
            }

        case .dragging(let drag):
            finishDragSession(drag)

        case .settling:
            return
        }
    }

    private func beginDrag(from press: PressState, itemID: UUID, pointerLocation: CGPoint) {
        guard let rowView = rowViews[press.rowID],
              let snapshotView = makeSnapshot(for: rowView),
              let taskIndex = taskIndex(for: press.rowID) else {
            interactionState = .idle
            return
        }

        delegate?.listViewWillBeginDragging(self, rowID: press.rowID)

        snapshotView.frame = rowView.frame
        addSubview(snapshotView, positioned: .above, relativeTo: nil)

        rowView.setDragging(true)

        let rowFrame = rowView.frame
        var drag = DragSession(
            rowID: press.rowID,
            itemID: itemID,
            snapshotView: snapshotView,
            pointerOffset: pointerLocation.y - rowFrame.origin.y,
            currentTaskIndex: taskIndex
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

        let hysteresis = max(4, CGFloat(preferences.rowHeight) * InteractionMetrics.dragSwapHysteresisFactor)
        let dragMidY = drag.snapshotView.frame.midY

        while drag.currentTaskIndex > 0 {
            let previousFrame = frameForRow(at: drag.currentTaskIndex - 1)
            if dragMidY < previousFrame.midY - hysteresis {
                displayOrder.swapAt(drag.currentTaskIndex, drag.currentTaskIndex - 1)
                drag.currentTaskIndex -= 1
                layoutRows(animated: true)
            } else {
                break
            }
        }

        while drag.currentTaskIndex < max(draggableTaskCount - 1, 0) {
            let nextFrame = frameForRow(at: drag.currentTaskIndex + 1)
            if dragMidY > nextFrame.midY + hysteresis {
                displayOrder.swapAt(drag.currentTaskIndex, drag.currentTaskIndex + 1)
                drag.currentTaskIndex += 1
                layoutRows(animated: true)
            } else {
                break
            }
        }
    }

    private func finishDragSession(_ drag: DragSession) {
        interactionState = .settling
        refreshRowVisualState(excluding: drag.rowID)
        let targetFrame = frameForRow(at: drag.currentTaskIndex)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = preferences.motion.dragReorder
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            drag.snapshotView.animator().frame = targetFrame
        }, completionHandler: { [weak self] in
            guard let self else { return }
            drag.snapshotView.removeFromSuperview()
            self.rowViews[drag.rowID]?.alphaValue = 1.0
            self.rowViews[drag.rowID]?.setDragging(false)
            self.interactionState = .idle
            self.refreshRowVisualState()
            self.delegate?.listView(self, didFinishDraggingRow: drag.rowID, orderedItemIDs: self.currentOrderedTaskItemIDs())
        })
    }

    private func refreshRowVisualState(excluding draggedRowID: TodoRowID? = nil) {
        for rowID in displayOrder {
            guard let rowView = rowViews[rowID] else { continue }
            rowView.setSelected(rowID == selectedRowID)
            rowView.setEditing(rowID == editingRowID)
            if rowID != draggedRowID {
                rowView.alphaValue = 1.0
                rowView.setDragging(false)
            }
        }
    }

    private func layoutRows(animated: Bool) {
        let draggedRowID = currentDraggedRowID

        let updates = {
            for (index, rowID) in self.displayOrder.enumerated() {
                guard let rowView = self.rowViews[rowID] else { continue }
                rowView.setSelected(rowID == self.selectedRowID)
                rowView.setEditing(rowID == self.editingRowID)
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.motion.dragReorder
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (index, rowID) in displayOrder.enumerated() {
                guard let rowView = rowViews[rowID] else { continue }
                rowView.setSelected(rowID == selectedRowID)
                rowView.setEditing(rowID == editingRowID)
                let targetFrame = frameForRow(at: index)
                rowView.animator().frame = targetFrame
            }
        }
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
        imageView.layer?.cornerRadius = CGFloat(LayoutMetrics.rowCornerRadius)
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

    private var draggableTaskCount: Int {
        displayOrder.reduce(into: 0) { count, rowID in
            if case .taskItem = rowModelsByID[rowID]?.kind {
                count += 1
            }
        }
    }

    private func taskIndex(for rowID: TodoRowID) -> Int? {
        guard case .taskItem = rowModelsByID[rowID]?.kind else { return nil }
        guard let index = displayOrder.firstIndex(of: rowID), index < draggableTaskCount else { return nil }
        return index
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
}

fileprivate final class TodoRowView: NSView {
    private let backgroundView = NSView()
    private let circleView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")
    let editorHostView = PassiveEditorHostView()

    private var preferences: AppPreferences
    private(set) var model: TodoRowModel

    private var isRowSelected = false {
        didSet { updateAppearance() }
    }

    private var isEditingRow = false {
        didSet { updateAppearance() }
    }

    private var isDraggingRow = false {
        didSet { updateAppearance() }
    }

    init(model: TodoRowModel, preferences: AppPreferences) {
        self.model = model
        self.preferences = preferences
        super.init(frame: .zero)

        wantsLayer = true

        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = CGFloat(LayoutMetrics.rowCornerRadius)
        addSubview(backgroundView)

        circleView.wantsLayer = true
        addSubview(circleView)

        textLabel.font = .systemFont(ofSize: 13)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.wantsLayer = true
        addSubview(textLabel)

        addSubview(editorHostView)
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
        textLabel.frame = textFrame
        editorHostView.frame = textFrame
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

        updateAppearance()
        needsLayout = true
    }

    func setSelected(_ selected: Bool) {
        isRowSelected = selected
    }

    func setEditing(_ editing: Bool) {
        isEditingRow = editing && model.isEditable
    }

    func setDragging(_ dragging: Bool) {
        isDraggingRow = dragging
    }

    func refreshMountedEditorState() {
        updateAppearance()
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
            strikeLayer.strokeColor = NSColor.white.withAlphaComponent(0.5).cgColor
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
            self.circleView.contentTintColor = .white

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
        let activeFillColor = NSColor(
            srgbRed: 0.22745098,
            green: 0.22745098,
            blue: 0.2627451,
            alpha: 1.0
        )
        let circleAlpha = isRowSelected && model.isSelectable
            ? max(CGFloat(model.circleOpacity), model.isDone ? CGFloat(model.textOpacity) : 0.86)
            : CGFloat(model.circleOpacity)
        let textAlpha = isRowSelected && model.isSelectable
            ? max(CGFloat(model.textOpacity), 0.98)
            : CGFloat(model.textOpacity)

        let backgroundColor: CGColor
        let borderColor: CGColor
        let borderWidth: CGFloat
        if isDraggingRow {
            backgroundColor = NSColor.clear.cgColor
            borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
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

        backgroundView.layer?.backgroundColor = backgroundColor
        backgroundView.layer?.borderColor = borderColor
        backgroundView.layer?.borderWidth = borderWidth
        circleView.contentTintColor = NSColor.white.withAlphaComponent(circleAlpha)
        textLabel.attributedStringValue = attributedText(alpha: textAlpha)
        let showsEditorHost = isEditingRow && model.isEditable
        let hasMountedEditor = !editorHostView.subviews.isEmpty
        textLabel.isHidden = showsEditorHost && hasMountedEditor
        editorHostView.isHidden = !showsEditorHost

        if isDraggingRow {
            backgroundView.alphaValue = 1.0
            textLabel.alphaValue = 0.0
            circleView.alphaValue = 0.0
        } else {
            backgroundView.alphaValue = 1.0
            textLabel.alphaValue = 1.0
            circleView.alphaValue = 1.0
        }
    }

    private func attributedText(alpha: CGFloat) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .font: NSFont.systemFont(ofSize: 13),
            .strikethroughStyle: model.showsStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
        ]
        return NSAttributedString(string: model.text, attributes: attributes)
    }

    private func fontLineHeight(for font: NSFont?) -> CGFloat {
        guard let font else { return 16 }
        return ceil(font.ascender - font.descender + font.leading)
    }
}

private final class PassiveEditorHostView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class KeyboardOnlyTextField: NSTextField {
    override var mouseDownCanMoveWindow: Bool { false }

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

public final class CaretEndFieldEditor: NSTextView {
    public override var mouseDownCanMoveWindow: Bool { false }

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

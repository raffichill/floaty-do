import AppKit
import Combine
import os.log
import QuartzCore

private let logger = Logger(subsystem: "com.floatydo", category: "TodoVC")

public enum Tab { case tasks, archive }

fileprivate protocol TodoRowViewDelegate: AnyObject {
    func rowViewDidRequestSelection(_ row: TodoRowView)
    func rowViewDidBeginEditing(_ row: TodoRowView)
    func rowView(_ row: TodoRowView, didChangeText text: String)
    func rowViewDidActivateCheckbox(_ row: TodoRowView)
    func rowViewDidRequestMoveUp(_ row: TodoRowView)
    func rowViewDidRequestMoveDown(_ row: TodoRowView)
    func rowViewDidRequestSubmit(_ row: TodoRowView)
    func rowViewDidStartDrag(_ row: TodoRowView, event: NSEvent)
    func rowViewDidContinueDrag(_ row: TodoRowView, event: NSEvent)
    func rowViewDidEndDrag(_ row: TodoRowView, event: NSEvent)
}

public final class TodoViewController: NSViewController, NSPopoverDelegate {
    private struct DragState {
        let rowID: TodoRowID
        let itemID: UUID
        let ghostView: NSImageView
        let pointerOffset: CGFloat
        var currentIndex: Int
    }

    private let store: TodoStore
    private let stackView = NSStackView()
    private var selectedRowID: TodoRowID?
    private var rowViews: [TodoRowView] = []
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
    private var dragState: DragState?

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

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.30).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(divider)
        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -LayoutMetrics.titlebarTrailingInset),

            divider.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: LayoutMetrics.dividerHeight),

            stackView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.view = container
        updateTabAppearance()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !self.isAnimating, self.dragState == nil else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command else { return event }

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

        store.$preferences
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.preferencesDidChange()
            }
            .store(in: &cancellables)

        rebuildRows(animateResize: false)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        resizeWindow(animate: false)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func preferencesDidChange() {
        if dragState != nil {
            finishDrag(commit: true)
        }
        rebuildRows(animateResize: false)
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
        rebuildRows(resize: false, animateResize: false)
    }

    @objc private func switchToArchive() {
        guard currentTab != .archive else { return }
        currentTab = .archive
        selectedRowID = nil
        updateTabAppearance()
        rebuildRows(resize: false, animateResize: false)
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

    private func rebuildRows(resize: Bool = true, animateResize: Bool = true) {
        logger.debug("rebuildRows START: resize=\(resize), animateResize=\(animateResize)")

        for row in rowViews {
            stackView.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowViews.removeAll()

        rowModels = buildRowModels()
        ensureSelectedRowExists()

        for model in rowModels {
            let row = TodoRowView(model: model, preferences: store.preferences)
            row.delegate = self
            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            rowViews.append(row)
        }

        updateRowSelectionStates()

        if resize {
            resizeWindow(animate: animateResize)
        }

        DispatchQueue.main.async { [weak self] in
            self?.focusSelectedRowIfNeeded()
        }
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
            selectedRowID = buildSelectionID(in: rowModels, selectableIndex: 0)
            return
        }
        guard rowModels.contains(where: { $0.id == selectedRowID }) else {
            self.selectedRowID = buildSelectionID(in: rowModels, selectableIndex: 0)
            return
        }
        guard rowModels.first(where: { $0.id == selectedRowID })?.isSelectable == true else {
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

    private func updateRowSelectionStates() {
        for row in rowViews {
            row.setSelected(row.model.id == selectedRowID)
        }
    }

    private func syncSelectedRow() {
        for row in rowViews where row.isEditing {
            selectedRowID = row.model.id
            return
        }
    }

    private var selectedRowIndex: Int? {
        guard let selectedRowID else { return nil }
        return rowModels.firstIndex(where: { $0.id == selectedRowID })
    }

    private var selectedModel: TodoRowModel? {
        guard let selectedRowIndex else { return nil }
        return rowModels[selectedRowIndex]
    }

    private func rowView(for rowID: TodoRowID?) -> TodoRowView? {
        guard let rowID else { return nil }
        return rowViews.first(where: { $0.model.id == rowID })
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

    private func focusSelectedRowIfNeeded() {
        guard dragState == nil else { return }
        guard let row = rowView(for: selectedRowID) else { return }
        if row.model.isEditable, let field = row.textField {
            field.window?.makeFirstResponder(field)
        } else {
            view.window?.makeFirstResponder(view)
        }
        updateRowSelectionStates()
    }

    private func handleCommandReturn() {
        syncSelectedRow()
        guard !isAnimating, dragState == nil, let selectedModel else { return }

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
                    rebuildRows()
                    return
                }
                rebuildRows()
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
            rebuildRows()
        }
    }

    private func handleCommandDelete() {
        syncSelectedRow()
        guard !isAnimating, dragState == nil, let selectedModel else { return }
        let selectionIndex = selectedRowIndex ?? 0

        switch currentTab {
        case .tasks:
            guard case .taskItem(let item) = selectedModel.kind else { return }
            store.deleteItem(id: item.id)
            let updatedModels = buildRowModels(for: .tasks)
            selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
            rebuildRows()

        case .archive:
            guard case .archiveItem(let item) = selectedModel.kind else { return }
            store.deleteArchived(id: item.id)
            let updatedModels = buildRowModels(for: .archive)
            selectedRowID = buildSelectionID(in: updatedModels, selectableIndex: selectionIndex)
            rebuildRows()
        }
    }

    private func animateCompletion(for itemID: UUID) {
        guard !isAnimating, dragState == nil else { return }
        guard let index = rowModels.firstIndex(where: { $0.itemID == itemID }),
              index < store.items.count,
              let row = rowView(for: .taskItem(itemID)),
              let item = store.items.first(where: { $0.id == itemID }) else {
            logger.warning("animateCompletion SKIPPED for itemID=\(itemID)")
            return
        }

        isAnimating = true
        selectedRowID = .taskItem(itemID)
        view.window?.makeFirstResponder(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + motion.completionSettle + motion.collapse + 0.4) { [weak self] in
            self?.isAnimating = false
        }

        row.playCompletionAnimation(motion: motion) { [weak self] in
            guard let self else { return }
            self.animateRowCollapse(row: row, duration: self.motion.collapse) {
                self.store.archive(id: item.id)
                let updatedModels = self.buildRowModels(for: .tasks)
                self.selectedRowID = self.buildSelectionID(in: updatedModels, selectableIndex: index)
                self.rebuildRows()
                self.isAnimating = false
            }
        }
    }

    private func animateRowCollapse(row: TodoRowView, duration: TimeInterval, completion: @escaping () -> Void) {
        guard let rowLayer = row.layer else {
            completion()
            return
        }

        rowLayer.masksToBounds = true

        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.name = "blur"
            blur.setValue(0, forKey: "inputRadius")
            rowLayer.filters = [blur]

            let blurAnim = CABasicAnimation(keyPath: "filters.blur.inputRadius")
            blurAnim.fromValue = 0
            blurAnim.toValue = 8
            blurAnim.duration = duration
            blurAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            blurAnim.fillMode = .forwards
            blurAnim.isRemovedOnCompletion = false
            rowLayer.add(blurAnim, forKey: "blurOut")
        }

        if let circleLayer = row.circleView.layer {
            let bounds = circleLayer.bounds
            let cx = bounds.width / 2
            let cy = bounds.height / 2
            let toOrigin = CATransform3DMakeTranslation(-cx, -cy, 0)
            let scale = CATransform3DMakeScale(0.4, 0.4, 1)
            let back = CATransform3DMakeTranslation(cx, cy, 0)
            let target = CATransform3DConcat(CATransform3DConcat(toOrigin, scale), back)

            let shrinkOut = CABasicAnimation(keyPath: "transform")
            shrinkOut.fromValue = CATransform3DIdentity
            shrinkOut.toValue = target
            shrinkOut.duration = duration
            shrinkOut.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shrinkOut.fillMode = .forwards
            shrinkOut.isRemovedOnCompletion = false
            circleLayer.add(shrinkOut, forKey: "shrinkOut")
        }

        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0
        fadeAnim.duration = duration
        fadeAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fadeAnim.fillMode = .forwards
        fadeAnim.isRemovedOnCompletion = false
        rowLayer.add(fadeAnim, forKey: "fadeOut")

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true

            row.heightConstraint.animator().constant = 0
            self.stackView.layoutSubtreeIfNeeded()
        }, completionHandler: completion)
    }

    func moveUp() {
        guard !isAnimating, dragState == nil else { return }
        syncSelectedRow()
        guard let currentIndex = selectedRowIndex,
              let nextIndex = nextSelectableIndex(from: currentIndex, step: -1) else { return }
        selectedRowID = rowModels[nextIndex].id
        focusSelectedRowIfNeeded()
    }

    func moveDown() {
        guard !isAnimating, dragState == nil else { return }
        syncSelectedRow()
        guard let currentIndex = selectedRowIndex,
              let nextIndex = nextSelectableIndex(from: currentIndex, step: 1) else { return }
        selectedRowID = rowModels[nextIndex].id
        focusSelectedRowIfNeeded()
    }

    func submitRow() {
        guard !isAnimating, dragState == nil, currentTab == .tasks else { return }
        syncSelectedRow()
        guard let selectedModel, let currentIndex = selectedRowIndex else { return }

        switch selectedModel.kind {
        case .taskItem:
            if let nextIndex = nextSelectableIndex(from: currentIndex, step: 1) {
                selectedRowID = rowModels[nextIndex].id
                focusSelectedRowIfNeeded()
            }
        case .taskInput:
            let text = taskInputDraft.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            store.add(text)
            taskInputDraft = ""
            selectedRowID = .taskInput
            rebuildRows()
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
}

extension TodoViewController: TodoRowViewDelegate {
    fileprivate func rowViewDidRequestSelection(_ row: TodoRowView) {
        guard row.model.isSelectable else { return }
        selectedRowID = row.model.id
        if !row.model.isEditable {
            view.window?.makeFirstResponder(view)
        }
        updateRowSelectionStates()
    }

    fileprivate func rowViewDidBeginEditing(_ row: TodoRowView) {
        guard row.model.isSelectable else { return }
        selectedRowID = row.model.id
        updateRowSelectionStates()
    }

    fileprivate func rowView(_ row: TodoRowView, didChangeText text: String) {
        switch row.model.kind {
        case .taskItem(let item):
            store.updateText(for: item.id, to: text)
        case .taskInput:
            taskInputDraft = text
        case .archiveItem, .filler:
            break
        }
    }

    fileprivate func rowViewDidActivateCheckbox(_ row: TodoRowView) {
        guard case .taskItem(let item) = row.model.kind else { return }
        animateCompletion(for: item.id)
    }

    fileprivate func rowViewDidRequestMoveUp(_ row: TodoRowView) {
        rowViewDidRequestSelection(row)
        moveUp()
    }

    fileprivate func rowViewDidRequestMoveDown(_ row: TodoRowView) {
        rowViewDidRequestSelection(row)
        moveDown()
    }

    fileprivate func rowViewDidRequestSubmit(_ row: TodoRowView) {
        rowViewDidRequestSelection(row)
        submitRow()
    }

    fileprivate func rowViewDidStartDrag(_ row: TodoRowView, event: NSEvent) {
        guard currentTab == .tasks, dragState == nil, !isAnimating else { return }
        guard case .taskItem(let item) = row.model.kind,
              let rowIndex = rowViews.firstIndex(where: { $0 === row }),
              rowIndex < store.items.count,
              let ghostView = snapshotView(for: row) else { return }

        rowViewDidRequestSelection(row)
        view.window?.makeFirstResponder(view)

        let rowFrameInView = view.convert(row.bounds, from: row)
        ghostView.frame = rowFrameInView
        view.addSubview(ghostView)
        row.setDragging(true)

        let pointerLocation = view.convert(event.locationInWindow, from: nil)
        dragState = DragState(
            rowID: row.model.id,
            itemID: item.id,
            ghostView: ghostView,
            pointerOffset: pointerLocation.y - rowFrameInView.minY,
            currentIndex: rowIndex
        )
        updateGhostPosition(with: pointerLocation)
    }

    fileprivate func rowViewDidContinueDrag(_ row: TodoRowView, event: NSEvent) {
        guard var dragState else { return }
        let pointerLocation = view.convert(event.locationInWindow, from: nil)
        updateGhostPosition(with: pointerLocation)
        let targetIndex = proposedDragIndex(for: dragState, ghostMidY: dragState.ghostView.frame.midY)
        guard targetIndex != dragState.currentIndex else { return }

        moveTaskRow(from: dragState.currentIndex, to: targetIndex)
        dragState.currentIndex = targetIndex
        self.dragState = dragState
        rowView(for: dragState.rowID)?.setDragging(true)
    }

    fileprivate func rowViewDidEndDrag(_ row: TodoRowView, event: NSEvent) {
        guard dragState != nil else { return }
        finishDrag(commit: true)
    }

    private func snapshotView(for row: TodoRowView) -> NSImageView? {
        let bounds = row.bounds
        guard let bitmap = row.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        row.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = CGFloat(LayoutMetrics.rowCornerRadius)
        imageView.layer?.shadowColor = NSColor.black.cgColor
        imageView.layer?.shadowOpacity = 0.22
        imageView.layer?.shadowRadius = 12
        imageView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        return imageView
    }

    private func updateGhostPosition(with pointerLocation: CGPoint) {
        guard let dragState else { return }
        var frame = dragState.ghostView.frame
        frame.origin.y = pointerLocation.y - dragState.pointerOffset
        dragState.ghostView.frame = frame
    }

    private func proposedDragIndex(for dragState: DragState, ghostMidY: CGFloat) -> Int {
        let taskRows = Array(rowViews.prefix(store.items.count))
        var targetIndex = 0

        for (index, row) in taskRows.enumerated() where index != dragState.currentIndex {
            let rowFrameInView = view.convert(row.bounds, from: row)
            if ghostMidY < rowFrameInView.midY {
                targetIndex += 1
            } else {
                break
            }
        }

        return max(0, min(targetIndex, max(store.items.count - 1, 0)))
    }

    private func moveTaskRow(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex else { return }
        guard sourceIndex < store.items.count, destinationIndex < store.items.count else { return }

        let movedRow = rowViews.remove(at: sourceIndex)
        rowViews.insert(movedRow, at: destinationIndex)

        let movedModel = rowModels.remove(at: sourceIndex)
        rowModels.insert(movedModel, at: destinationIndex)

        stackView.removeArrangedSubview(movedRow)
        movedRow.removeFromSuperview()
        stackView.insertArrangedSubview(movedRow, at: destinationIndex)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.dragReorder
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            stackView.layoutSubtreeIfNeeded()
        }

        updateRowSelectionStates()
    }

    private func finishDrag(commit: Bool) {
        guard let dragState else { return }
        self.dragState = nil

        dragState.ghostView.removeFromSuperview()
        rowView(for: dragState.rowID)?.setDragging(false)

        guard commit else {
            rebuildRows(resize: false, animateResize: false)
            return
        }

        let orderedIDs = rowModels.prefix(store.items.count).compactMap(\.itemID)
        store.reorderItems(by: orderedIDs)
        selectedRowID = dragState.rowID
        rebuildRows(resize: false, animateResize: false)
    }
}

private extension NSWindow {
    var titlebarHeight: CGFloat {
        contentView?.safeAreaInsets.top ?? 0
    }
}

final class TodoRowView: NSView {
    private let backgroundView = NSView()
    private let circleHitView = InteractiveRegionView()
    private let dragHandleView = DragHandleView()
    private let dragHandleImageView: NSImageView
    private var displayLabel: NSTextField?
    private var trackingAreaRef: NSTrackingArea?
    private var pendingDragLocation: NSPoint?
    private let preferences: AppPreferences

    private(set) var model: TodoRowModel
    private(set) var circleView: NSImageView
    private(set) var textField: NSTextField?
    private(set) var heightConstraint: NSLayoutConstraint!

    fileprivate weak var delegate: TodoRowViewDelegate?

    private var isHovered = false {
        didSet { updateAppearance(animated: true) }
    }

    private var isSelected = false {
        didSet { updateAppearance(animated: true) }
    }

    private var isDragging = false {
        didSet { updateAppearance(animated: false) }
    }

    var currentText: String {
        textField?.stringValue ?? displayLabel?.stringValue ?? ""
    }

    var isEditing: Bool {
        textField?.currentEditor() != nil
    }

    init(model: TodoRowModel, preferences: AppPreferences) {
        self.model = model
        self.preferences = preferences

        let circleImage = NSImage(systemSymbolName: model.isDone ? "checkmark.circle.fill" : "circle", accessibilityDescription: nil)!
        let circleConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        circleView = NSImageView(image: circleImage.withSymbolConfiguration(circleConfig)!)
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.wantsLayer = true

        let handleImage = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)!
        let handleConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        dragHandleImageView = NSImageView(image: handleImage.withSymbolConfiguration(handleConfig)!)
        dragHandleImageView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        backgroundView.wantsLayer = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.layer?.cornerRadius = CGFloat(LayoutMetrics.rowCornerRadius)
        addSubview(backgroundView)

        circleHitView.translatesAutoresizingMaskIntoConstraints = false
        circleHitView.onMouseUp = { [weak self] in
            guard let self, self.model.canComplete else { return }
            self.delegate?.rowViewDidActivateCheckbox(self)
        }
        addSubview(circleHitView)
        circleHitView.addSubview(circleView)

        dragHandleView.translatesAutoresizingMaskIntoConstraints = false
        dragHandleView.onMouseDown = { [weak self] event in
            guard let self else { return }
            self.pendingDragLocation = event.locationInWindow
            self.delegate?.rowViewDidRequestSelection(self)
        }
        dragHandleView.onMouseDragged = { [weak self] event in
            guard let self else { return }
            if let start = self.pendingDragLocation {
                let deltaX = event.locationInWindow.x - start.x
                let deltaY = event.locationInWindow.y - start.y
                if hypot(deltaX, deltaY) >= 3 {
                    self.pendingDragLocation = nil
                    self.delegate?.rowViewDidStartDrag(self, event: event)
                    self.delegate?.rowViewDidContinueDrag(self, event: event)
                }
            } else {
                self.delegate?.rowViewDidContinueDrag(self, event: event)
            }
        }
        dragHandleView.onMouseUp = { [weak self] event in
            guard let self else { return }
            if self.pendingDragLocation != nil {
                self.pendingDragLocation = nil
                return
            }
            self.delegate?.rowViewDidEndDrag(self, event: event)
        }
        addSubview(dragHandleView)
        dragHandleView.addSubview(dragHandleImageView)

        heightConstraint = heightAnchor.constraint(equalToConstant: CGFloat(preferences.rowHeight))

        NSLayoutConstraint.activate([
            heightConstraint,

            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutMetrics.rowBackgroundInset),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LayoutMetrics.rowBackgroundInset),
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: LayoutMetrics.rowVerticalInset),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -LayoutMetrics.rowVerticalInset),

            circleHitView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutMetrics.rowHorizontalInset),
            circleHitView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleHitView.widthAnchor.constraint(equalToConstant: LayoutMetrics.circleHitSize),
            circleHitView.heightAnchor.constraint(equalToConstant: LayoutMetrics.circleHitSize),

            circleView.centerXAnchor.constraint(equalTo: circleHitView.centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: circleHitView.centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: LayoutMetrics.circleSize),
            circleView.heightAnchor.constraint(equalToConstant: LayoutMetrics.circleSize),

            dragHandleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LayoutMetrics.rowHorizontalInset),
            dragHandleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dragHandleView.widthAnchor.constraint(equalToConstant: LayoutMetrics.dragHandleSize),
            dragHandleView.heightAnchor.constraint(equalToConstant: LayoutMetrics.dragHandleSize),

            dragHandleImageView.centerXAnchor.constraint(equalTo: dragHandleView.centerXAnchor),
            dragHandleImageView.centerYAnchor.constraint(equalTo: dragHandleView.centerYAnchor),
        ])

        if model.isEditable {
            let field = CaretEndTextField()
            field.stringValue = model.text
            field.isBordered = false
            field.drawsBackground = false
            field.font = .systemFont(ofSize: 13)
            field.focusRingType = .none
            field.lineBreakMode = .byTruncatingTail
            field.cell?.isScrollable = true
            field.wantsLayer = true
            field.translatesAutoresizingMaskIntoConstraints = false

            let delegate = RowFieldDelegate(row: self)
            field.delegate = delegate
            objc_setAssociatedObject(field, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            addSubview(field)
            textField = field

            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: circleHitView.trailingAnchor, constant: LayoutMetrics.textInset),
                field.trailingAnchor.constraint(equalTo: dragHandleView.leadingAnchor, constant: -LayoutMetrics.textInset),
                field.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            let label = NSTextField(labelWithString: model.text)
            label.lineBreakMode = .byTruncatingTail
            label.font = .systemFont(ofSize: 13)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            displayLabel = label

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: circleHitView.trailingAnchor, constant: LayoutMetrics.textInset),
                label.trailingAnchor.constraint(equalTo: dragHandleView.leadingAnchor, constant: -LayoutMetrics.textInset),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard model.isSelectable else {
            super.mouseDown(with: event)
            return
        }

        delegate?.rowViewDidRequestSelection(self)
        if model.isEditable, let textField {
            window?.makeFirstResponder(textField)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if model.canComplete {
            addCursorRect(circleHitView.frame, cursor: .pointingHand)
        }
        if model.canDrag {
            addCursorRect(dragHandleView.frame, cursor: .openHand)
        }
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
    }

    func setDragging(_ dragging: Bool) {
        isDragging = dragging
    }

    private func updateAppearance(animated: Bool) {
        let backgroundAlpha: CGFloat
        if isDragging {
            backgroundAlpha = 0.08
        } else if isSelected && model.isSelectable {
            backgroundAlpha = 0.16
        } else if preferences.hoverHighlightsEnabled && isHovered && model.isSelectable {
            backgroundAlpha = 0.10
        } else {
            backgroundAlpha = 0.0
        }

        var circleAlpha = CGFloat(model.circleOpacity)
        if model.canComplete && isHovered {
            circleAlpha = max(circleAlpha, 0.72)
        }
        if isSelected && model.isSelectable {
            circleAlpha = max(circleAlpha, model.isDone ? CGFloat(model.textOpacity) : 0.86)
        }
        if isDragging {
            circleAlpha *= 0.45
        }

        var textAlpha = CGFloat(model.textOpacity)
        if !model.showsStrikethrough {
            if preferences.hoverHighlightsEnabled && isHovered && model.isSelectable {
                textAlpha = max(textAlpha, 0.96)
            }
            if isSelected && model.isSelectable {
                textAlpha = max(textAlpha, 0.98)
            }
        }
        if isDragging {
            textAlpha *= 0.45
        }

        let applyUpdates = {
            self.backgroundView.layer?.backgroundColor = NSColor.white.withAlphaComponent(backgroundAlpha).cgColor
            self.circleView.contentTintColor = NSColor.white.withAlphaComponent(circleAlpha)
            self.dragHandleImageView.contentTintColor = NSColor.white.withAlphaComponent(self.model.canDrag ? 0.55 : 0.0)
            self.dragHandleView.alphaValue = self.model.canDrag && (self.isSelected || self.isHovered || self.isDragging) ? 1.0 : 0.0

            if let textField = self.textField {
                textField.textColor = NSColor.white.withAlphaComponent(textAlpha)
                textField.layer?.opacity = Float(textAlpha)
            }

            if let displayLabel = self.displayLabel {
                displayLabel.attributedStringValue = self.makeLabelString(alpha: textAlpha)
                displayLabel.alphaValue = 1.0
            }
        }

        guard animated else {
            applyUpdates()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.motion.hoverFade
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            applyUpdates()
        }
    }

    private func makeLabelString(alpha: CGFloat) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .font: NSFont.systemFont(ofSize: 13),
            .strikethroughStyle: model.showsStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
        ]
        return NSAttributedString(string: model.text, attributes: attributes)
    }

    func playCompletionAnimation(motion: MotionProfile, completion: @escaping () -> Void) {
        guard let circleLayer = circleView.layer else {
            completion()
            return
        }

        layoutSubtreeIfNeeded()

        if let textField, !textField.stringValue.isEmpty {
            let textWidth = (textField.stringValue as NSString).size(withAttributes: [.font: textField.font!]).width
            let strikeLayer = CAShapeLayer()
            let textFrame = textField.frame
            let midY = textFrame.midY
            let path = CGMutablePath()
            path.move(to: CGPoint(x: textFrame.minX, y: midY))
            path.addLine(to: CGPoint(x: textFrame.minX + textWidth, y: midY))
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
            textField.layer?.add(fadeText, forKey: "fadeText")
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
}

private final class RowFieldDelegate: NSObject, NSTextFieldDelegate {
    weak var row: TodoRowView?

    init(row: TodoRowView) {
        self.row = row
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let row else { return }
        row.delegate?.rowViewDidBeginEditing(row)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let row, let field = obj.object as? NSTextField else { return }
        row.delegate?.rowView(row, didChangeText: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let row, let delegate = row.delegate else { return false }

        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            delegate.rowViewDidRequestMoveUp(row)
            return true
        case #selector(NSResponder.moveDown(_:)):
            delegate.rowViewDidRequestMoveDown(row)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            delegate.rowViewDidRequestSubmit(row)
            return true
        case #selector(NSResponder.insertTab(_:)):
            delegate.rowViewDidRequestMoveDown(row)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            delegate.rowViewDidRequestMoveUp(row)
            return true
        default:
            return false
        }
    }
}

private final class InteractiveRegionView: NSView {
    var onMouseUp: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }
}

private final class DragHandleView: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }
}

private final class CaretEndTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
        if result, let row = superview as? TodoRowView {
            row.delegate?.rowViewDidBeginEditing(row)
        }
        return result
    }

    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        if let editor = currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
    }
}

public final class CaretEndFieldEditor: NSTextView {
    public override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        if charRange.length == string.count && charRange.length > 0 && !flag {
            super.setSelectedRange(NSRange(location: string.count, length: 0), affinity: affinity, stillSelecting: flag)
        } else {
            super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        }
    }
}

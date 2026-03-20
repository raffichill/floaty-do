import AppKit
import QuartzCore

protocol TodoListViewDelegate: AnyObject {
    func listView(_ listView: TodoListView, didActivateRow rowID: TodoRowID)
    func listView(_ listView: TodoListView, didActivateCheckboxFor rowID: TodoRowID)
    func listViewWillPressRowBody(_ listView: TodoListView, rowID: TodoRowID)
    func listViewWillBeginDragging(_ listView: TodoListView, rowID: TodoRowID)
    func listView(_ listView: TodoListView, didFinishDraggingRow rowID: TodoRowID, orderedItemIDs: [UUID])
}

final class TodoListView: NSView {
    enum HitZone {
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

final class TodoRowView: NSView {
    private enum AppearanceMetrics {
        static let pressedScale: CGFloat = 0.99
        static let pressAnimationDuration: CFTimeInterval = 0.08
        static let showsDebugGeometry = false
        static let textVerticalBreathingRoom: CGFloat = 4
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
        editingTextView.frame = textFrame.insetBy(dx: 0, dy: -AppearanceMetrics.textVerticalBreathingRoom / 2)
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

    private func alignToBackingScale(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        guard scale > 0 else { return value }
        return round(value * scale) / scale
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

final class DebugGeometryOverlayView: NSView {
    var rowFrame: NSRect = .zero
    var backgroundFrame: NSRect = .zero
    var checkboxFrame: NSRect = .zero
    var textFrame: NSRect = .zero
    var labelContentFrame: NSRect = .zero
    var editorContentFrame: NSRect = .zero
    var centerlineY: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.zPosition = 999
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        draw(rect: rowFrame, color: NSColor.systemRed.withAlphaComponent(0.8))
        draw(rect: backgroundFrame, color: NSColor.systemGreen.withAlphaComponent(0.8))
        draw(rect: checkboxFrame, color: NSColor.systemYellow.withAlphaComponent(0.8))
        draw(rect: textFrame, color: NSColor.systemCyan.withAlphaComponent(0.9))
        draw(rect: labelContentFrame, color: NSColor.systemBlue.withAlphaComponent(0.95))
        draw(rect: editorContentFrame, color: NSColor.systemPurple.withAlphaComponent(0.95))

        let centerlinePath = NSBezierPath()
        centerlinePath.move(to: NSPoint(x: rowFrame.minX, y: centerlineY))
        centerlinePath.line(to: NSPoint(x: rowFrame.maxX, y: centerlineY))
        centerlinePath.lineWidth = debugStrokeWidth
        NSColor.systemPink.withAlphaComponent(0.8).setStroke()
        centerlinePath.stroke()
    }

    private func draw(rect: NSRect, color: NSColor) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = debugStrokeWidth
        color.setStroke()
        path.stroke()
    }

    private var debugStrokeWidth: CGFloat {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        guard scale > 0 else { return 1.0 }
        return 1.0 / scale
    }
}

final class PassiveEditorHostView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

final class EditingTextDisplayView: NSView {
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

        let drawRect = textDrawingRect(for: contentRect)
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

    private func textDrawingRect(for contentRect: NSRect) -> NSRect {
        let descenderPadding = max(0, bounds.maxY - contentRect.maxY)
        return NSRect(
            x: contentRect.minX - horizontalOffset,
            y: contentRect.minY,
            width: max(contentRect.width + horizontalOffset, 1),
            height: contentRect.height + descenderPadding
        )
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

final class CursorShieldView: NSView {
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

final class KeyboardOnlyTextField: NSTextField {
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
    private var allowsFullSelection = false

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

    public override func selectAll(_ sender: Any?) {
        allowsFullSelection = true
        super.selectAll(sender)
        allowsFullSelection = false
    }

    public override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        if charRange.length == string.count && charRange.length > 0 && !flag && !allowsFullSelection {
            super.setSelectedRange(NSRange(location: string.count, length: 0), affinity: affinity, stillSelecting: flag)
        } else {
            super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        }
    }
}

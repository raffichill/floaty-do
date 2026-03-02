import AppKit
import QuartzCore

// MARK: - Controller

enum Tab { case tasks, archive }

final class TodoViewController: NSViewController {
    private let store: TodoStore
    private let stackView = NSStackView()
    private var selectedIndex: Int = 0
    private var rowViews: [TodoRowView] = []
    private var eventMonitor: Any?
    private var currentTab: Tab = .tasks
    private var tasksTabButton: NSButton!
    private var archiveTabButton: NSButton!
    private var isAnimating = false

    init(store: TodoStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var rowCount: Int {
        switch currentTab {
        case .tasks:
            return min(store.items.count + 3, TodoStore.maxItems)
        case .archive:
            return max(store.archivedItems.count, 3)
        }
    }

    private var inputIndex: Int { store.items.count }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 200))
        container.wantsLayer = true

        // Tab bar in the title bar area
        tasksTabButton = makeTabButton(symbolName: "checklist.unchecked", action: #selector(switchToTasks))
        archiveTabButton = makeTabButton(symbolName: "archivebox", action: #selector(switchToArchive))

        let tabBar = NSStackView(views: [tasksTabButton, archiveTabButton])
        tabBar.orientation = .horizontal
        tabBar.spacing = 0
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabBar)

        // Stretch buttons to fill the full title bar height
        tasksTabButton.topAnchor.constraint(equalTo: tabBar.topAnchor).isActive = true
        tasksTabButton.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor).isActive = true
        archiveTabButton.topAnchor.constraint(equalTo: tabBar.topAnchor).isActive = true
        archiveTabButton.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor).isActive = true

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
            // Tab bar spans the full title bar height
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            divider.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
            stackView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.view = container
        updateTabAppearance()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Event monitor ONLY for cmd+key combos (cmd+return, cmd+delete)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard !self.isAnimating else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command else { return event }

            if event.keyCode == 36 { // cmd+return
                self.syncSelectedIndex()
                if self.currentTab == .tasks {
                    if self.selectedIndex < self.store.items.count {
                        self.animateCompletion(at: self.selectedIndex)
                        return nil
                    } else if self.selectedIndex == self.inputIndex {
                        // On input row: add the todo then immediately complete it
                        let row = self.rowViews[self.selectedIndex]
                        let text = row.currentText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return nil }
                        self.store.add(text)
                        let newItemIndex = self.store.items.count - 1
                        self.rebuildRows()
                        self.animateCompletion(at: newItemIndex)
                        return nil
                    } else {
                        return nil
                    }
                } else {
                    if self.selectedIndex < self.store.archivedItems.count {
                        self.store.restore(self.store.archivedItems[self.selectedIndex])
                        if self.selectedIndex >= self.store.archivedItems.count && self.selectedIndex > 0 {
                            self.selectedIndex = self.store.archivedItems.count - 1
                        }
                        self.deferredRebuild()
                    }
                    return nil
                }
            }
            if event.keyCode == 51 { // cmd+delete
                self.syncSelectedIndex()
                if self.currentTab == .tasks {
                    if self.selectedIndex < self.store.items.count {
                        self.store.delete(self.store.items[self.selectedIndex])
                        if self.selectedIndex >= self.store.items.count && self.selectedIndex > 0 {
                            self.selectedIndex = self.store.items.count - 1
                        }
                        self.deferredRebuild()
                    }
                } else {
                    if self.selectedIndex < self.store.archivedItems.count {
                        self.store.deleteArchived(self.store.archivedItems[self.selectedIndex])
                        if self.selectedIndex >= self.store.archivedItems.count && self.selectedIndex > 0 {
                            self.selectedIndex = self.store.archivedItems.count - 1
                        }
                        self.deferredRebuild()
                    }
                }
                return nil
            }
            return event
        }

        rebuildRows()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Initial resize — viewDidLoad runs before the view is in the window,
        // so resizeWindow() silently fails there. Do it here once the window exists.
        resizeWindow()
    }

    deinit {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Focus Sync

    /// Sync selectedIndex with whichever text field actually has focus (e.g. after a click)
    private func syncSelectedIndex() {
        for (i, row) in rowViews.enumerated() {
            if let field = row.textField, field.currentEditor() != nil {
                selectedIndex = i
                return
            }
        }
    }

    /// Called by RowFieldDelegate when a row's text field begins editing (click or tab into)
    func rowDidBeginEditing(_ row: TodoRowView) {
        if let idx = rowViews.firstIndex(where: { $0 === row }) {
            selectedIndex = idx
        }
    }

    // MARK: - Tabs

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
        tasksTabButton.contentTintColor = currentTab == .tasks
            ? .white
            : .white.withAlphaComponent(0.35)
        archiveTabButton.contentTintColor = currentTab == .archive
            ? .white
            : .white.withAlphaComponent(0.35)
    }

    @objc private func switchToTasks() {
        guard currentTab != .tasks else { return }
        currentTab = .tasks
        selectedIndex = 0
        updateTabAppearance()
        rebuildRows(resize: false)
    }

    @objc private func switchToArchive() {
        guard currentTab != .archive else { return }
        currentTab = .archive
        selectedIndex = 0
        updateTabAppearance()
        rebuildRows(resize: false)
    }

    // MARK: - Completion Animation

    private func animateCompletion(at index: Int) {
        guard !isAnimating, index < store.items.count, index < rowViews.count else { return }
        isAnimating = true

        let row = rowViews[index]
        let item = store.items[index]

        fputs("[ANIM] start: archiving '\(item.text)' at index \(index), items=\(store.items.count) [\(store.items.map { $0.text })]\n", stderr)

        // Clear focus during animation
        view.window?.makeFirstResponder(nil)

        // Safety timeout: reset isAnimating if completion chain breaks
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.isAnimating = false
        }

        // Phase 1: Strikethrough → Phase 2: Circle swap → Phase 3: Row clear
        row.playCompletionAnimation { [weak self] in
            guard let self else { return }

            fputs("[ANIM] phase3 start: items=\(self.store.items.count)\n", stderr)

            // Phase 3: Blur + shrink + collapse
            self.animateRowCollapse(row: row) {
                fputs("[ANIM] collapse done: items=\(self.store.items.count) before archive\n", stderr)

                // Post-animation: archive and rebuild
                self.store.archive(item)

                fputs("[ANIM] after archive: items=\(self.store.items.count) [\(self.store.items.map { $0.text })]\n", stderr)

                // selectedIndex stays at same position (now points to next item)
                if index < self.store.items.count {
                    self.selectedIndex = index
                } else {
                    // Archived the last item — land on the input row
                    self.selectedIndex = self.store.items.count
                }

                self.rebuildRows(animateResize: false)
                self.isAnimating = false
            }
        }
    }

    private func animateRowCollapse(row: TodoRowView, completion: @escaping () -> Void) {
        guard let rowLayer = row.layer else {
            completion()
            return
        }

        rowLayer.masksToBounds = true

        // Blur effect on row content
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.name = "blur"
            blur.setValue(0, forKey: "inputRadius")
            rowLayer.filters = [blur]

            let blurAnim = CABasicAnimation(keyPath: "filters.blur.inputRadius")
            blurAnim.fromValue = 0
            blurAnim.toValue = 8
            blurAnim.duration = 0.35
            blurAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            blurAnim.fillMode = .forwards
            blurAnim.isRemovedOnCompletion = false
            rowLayer.add(blurAnim, forKey: "blurOut")
        }

        // Shrink checkmark to 40% from center (use full transform to avoid anchorPoint issues)
        if let circleLayer = row.circleView.layer {
            let b = circleLayer.bounds
            let cx = b.width / 2
            let cy = b.height / 2
            let toOrigin = CATransform3DMakeTranslation(-cx, -cy, 0)
            let scale = CATransform3DMakeScale(0.4, 0.4, 1)
            let back = CATransform3DMakeTranslation(cx, cy, 0)
            let target = CATransform3DConcat(CATransform3DConcat(toOrigin, scale), back)

            let shrinkOut = CABasicAnimation(keyPath: "transform")
            shrinkOut.fromValue = CATransform3DIdentity
            shrinkOut.toValue = target
            shrinkOut.duration = 0.35
            shrinkOut.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shrinkOut.fillMode = .forwards
            shrinkOut.isRemovedOnCompletion = false
            circleLayer.add(shrinkOut, forKey: "shrinkOut")
        }

        // Fade out
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0
        fadeAnim.duration = 0.35
        fadeAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fadeAnim.fillMode = .forwards
        fadeAnim.isRemovedOnCompletion = false
        rowLayer.add(fadeAnim, forKey: "fadeOut")

        // Layout collapse + other rows shift (350ms easeOut)
        // Note: window resize is handled by rebuildRows() after archive, not here,
        // to avoid conflicts between animator().setFrame() and setFrame(animate:).
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true

            row.heightConstraint.animator().constant = 0
            self.stackView.layoutSubtreeIfNeeded()
        }, completionHandler: completion)
    }

    // MARK: - Navigation (called by field delegate via row callbacks)

    func moveUp() {
        guard !isAnimating, selectedIndex > 0 else { return }
        selectedIndex -= 1
        focusRow(selectedIndex)
    }

    func moveDown() {
        guard !isAnimating, selectedIndex < rowCount - 1 else { return }
        selectedIndex += 1
        focusRow(selectedIndex)
    }

    func submitRow() {
        guard !isAnimating, currentTab == .tasks else { return }

        if selectedIndex < store.items.count {
            // On a filled row: return moves down
            moveDown()
        } else if selectedIndex == inputIndex {
            // On the input row: add the todo
            let row = rowViews[selectedIndex]
            let text = row.currentText
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            store.add(text)
            selectedIndex = inputIndex
            deferredRebuild()
        }
    }

    // MARK: - Focus

    private func focusRow(_ index: Int) {
        guard index < rowViews.count else { return }
        let row = rowViews[index]
        guard let field = row.textField else { return }
        field.window?.makeFirstResponder(field)
    }

    // MARK: - Rebuild

    private func deferredRebuild() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(nil)
            self.rebuildRows()
        }
    }

    private func rebuildRows(resize: Bool = true, animateResize: Bool = true) {
        for row in rowViews {
            stackView.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowViews.removeAll()

        let count = rowCount

        fputs("[REBUILD] items=\(store.items.count) rowCount=\(count) resize=\(resize)\n", stderr)

        if currentTab == .tasks {
            rebuildTaskRows(count: count)
        } else {
            rebuildArchiveRows(count: count)
        }

        if selectedIndex >= count { selectedIndex = max(0, count - 1) }

        if resize { resizeWindow(animate: animateResize) }

        // Focus after layout settles
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusRow(self.selectedIndex)
        }
    }

    private func rebuildTaskRows(count: Int) {
        for i in 0..<count {
            let emptyIndex = i - store.items.count
            let emptyCount = count - store.items.count
            let row: TodoRowView

            if i < store.items.count {
                let item = store.items[i]
                row = TodoRowView(
                    text: item.text, isDone: false,
                    circleOpacity: 0.4,
                    isEditable: true
                )
                let idx = i
                row.onTextChange = { [weak self] newText in
                    guard let self, idx < self.store.items.count else { return }
                    self.store.items[idx].text = newText
                }
            } else if i == inputIndex {
                row = TodoRowView(
                    text: "", isDone: false,
                    circleOpacity: fadeOpacity(emptyIndex: emptyIndex, emptyCount: emptyCount),
                    isEditable: true
                )
            } else {
                row = TodoRowView(
                    text: "", isDone: false,
                    circleOpacity: fadeOpacity(emptyIndex: emptyIndex, emptyCount: emptyCount),
                    isEditable: false
                )
            }

            row.controller = self
            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            rowViews.append(row)
        }
    }

    private func rebuildArchiveRows(count: Int) {
        for i in 0..<count {
            let row: TodoRowView
            if i < store.archivedItems.count {
                let item = store.archivedItems[i]
                row = TodoRowView(
                    text: item.text, isDone: true,
                    circleOpacity: 1.0,
                    isEditable: true
                )
            } else {
                row = TodoRowView(
                    text: "", isDone: false,
                    circleOpacity: fadeOpacity(emptyIndex: i - store.archivedItems.count,
                                               emptyCount: count - store.archivedItems.count),
                    isEditable: false
                )
            }

            row.controller = self
            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            rowViews.append(row)
        }
    }

    private func resizeWindow(animate: Bool = true) {
        guard let window = view.window else { return }
        let rows = max(rowCount, 1)
        let contentHeight = CGFloat(rows) * 36.0 + 16.5
        let titlebar = window.titlebarHeight
        let fullHeight = max(contentHeight + titlebar, window.minSize.height)
        let oldFrame = window.frame

        // Only grow the window, never shrink it automatically
        if fullHeight <= oldFrame.height {
            fputs("[RESIZE] SKIP (no shrink): need=\(fullHeight) have=\(oldFrame.height)\n", stderr)
            return
        }

        let newFrame = NSRect(
            x: oldFrame.origin.x,
            y: oldFrame.maxY - fullHeight,
            width: oldFrame.width,
            height: fullHeight
        )
        fputs("[RESIZE] GROW: rows=\(rows) titlebar=\(titlebar) \(oldFrame.height) -> \(fullHeight)\n", stderr)
        window.setFrame(newFrame, display: true, animate: animate)
    }

    private func fadeOpacity(emptyIndex: Int, emptyCount: Int) -> Double {
        let fromEnd = emptyCount - 1 - emptyIndex
        switch fromEnd {
        case 0: return 0.10
        case 1: return 0.20
        default: return 0.30
        }
    }
}

private extension NSWindow {
    var titlebarHeight: CGFloat {
        // With .fullSizeContentView, contentRect == frame, so use safe area instead
        contentView?.safeAreaInsets.top ?? 0
    }
}

// MARK: - Row View

final class TodoRowView: NSView {
    private(set) var circleView: NSImageView
    private(set) var textField: NSTextField?
    private(set) var heightConstraint: NSLayoutConstraint!
    weak var controller: TodoViewController?
    var onTextChange: ((String) -> Void)?

    var currentText: String { textField?.stringValue ?? "" }

    init(text: String, isDone: Bool, circleOpacity: Double, isEditable: Bool) {
        let symbolName = isDone ? "checkmark.circle.fill" : "circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        circleView = NSImageView(image: image.withSymbolConfiguration(config)!)
        circleView.contentTintColor = NSColor.white.withAlphaComponent(circleOpacity)

        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        circleView.wantsLayer = true
        circleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circleView)

        heightConstraint = heightAnchor.constraint(equalToConstant: 36)

        var constraints: [NSLayoutConstraint] = [
            heightConstraint,
            circleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 18),
            circleView.heightAnchor.constraint(equalToConstant: 18),
        ]

        if isEditable {
            let field = CaretEndTextField()
            field.stringValue = text
            field.isBordered = false
            field.drawsBackground = false
            field.font = .systemFont(ofSize: 13)
            field.focusRingType = .none
            field.lineBreakMode = .byTruncatingTail
            field.cell?.isScrollable = true
            field.wantsLayer = true
            field.translatesAutoresizingMaskIntoConstraints = false

            if isDone {
                field.textColor = NSColor.white.withAlphaComponent(0.3)
                let attrs: [NSAttributedString.Key: Any] = [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.3),
                    .font: NSFont.systemFont(ofSize: 13),
                ]
                field.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
            } else {
                field.textColor = NSColor.white.withAlphaComponent(0.9)
            }

            let delegate = RowFieldDelegate(row: self)
            field.delegate = delegate
            objc_setAssociatedObject(field, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            addSubview(field)
            self.textField = field

            constraints.append(contentsOf: [
                field.leadingAnchor.constraint(equalTo: circleView.trailingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                field.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) { textField?.stringValue = text }

    // MARK: - Completion Animation (Phase 1)

    func playCompletionAnimation(completion: @escaping () -> Void) {
        guard let circleLayer = circleView.layer else {
            completion()
            return
        }

        self.layoutSubtreeIfNeeded()

        // Strikethrough (250ms) and circle swap (400ms bouncy spring) start together
        // Phase 3 fires at 500ms to let the spring fully settle

        // 1. Strikethrough sweeps across text (250ms)
        if let textField = self.textField, !textField.stringValue.isEmpty {
            let textWidth = (textField.stringValue as NSString).size(
                withAttributes: [.font: textField.font!]
            ).width

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
            self.layer?.addSublayer(strikeLayer)

            let strokeAnim = CABasicAnimation(keyPath: "strokeEnd")
            strokeAnim.fromValue = 0.0
            strokeAnim.toValue = 1.0
            strokeAnim.duration = 0.25
            strokeAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            strokeAnim.fillMode = .forwards
            strokeAnim.isRemovedOnCompletion = false
            strikeLayer.add(strokeAnim, forKey: "strikethrough")

            // Fade text as strikethrough sweeps
            let fadeText = CABasicAnimation(keyPath: "opacity")
            fadeText.fromValue = 1.0
            fadeText.toValue = 0.3
            fadeText.duration = 0.25
            fadeText.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fadeText.fillMode = .forwards
            fadeText.isRemovedOnCompletion = false
            textField.layer?.add(fadeText, forKey: "fadeText")
        }

        // Helper: force anchorPoint to center (AppKit resets it on layer-backed views)
        func centerAnchor() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let pos = circleLayer.position
            let anc = circleLayer.anchorPoint
            let b = circleLayer.bounds
            circleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            circleLayer.position = CGPoint(
                x: pos.x + b.width * (0.5 - anc.x),
                y: pos.y + b.height * (0.5 - anc.y)
            )
            CATransaction.commit()
        }

        // 2. Circle spring swap (starts at t=0, bouncier spring ~400ms)
        centerAnchor()

        // Shrink out the empty circle
        let shrink = CASpringAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = 0.0
        shrink.stiffness = 200
        shrink.damping = 15
        shrink.duration = shrink.settlingDuration
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        circleLayer.add(shrink, forKey: "shrinkOut")

        // Swap icon + grow in the checkmark at 100ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill",
                                      accessibilityDescription: nil)!
            self.circleView.image = checkImage.withSymbolConfiguration(config)
            self.circleView.contentTintColor = .white

            circleLayer.removeAnimation(forKey: "shrinkOut")

            // Re-apply anchorPoint (AppKit may have reset it between run loop iterations)
            centerAnchor()

            let growIn = CASpringAnimation(keyPath: "transform.scale")
            growIn.fromValue = 0.0
            growIn.toValue = 1.0
            growIn.stiffness = 200
            growIn.damping = 15
            growIn.duration = growIn.settlingDuration
            growIn.fillMode = .forwards
            growIn.isRemovedOnCompletion = false
            circleLayer.add(growIn, forKey: "growIn")
        }

        // Fire Phase 3 at 600ms from start (spring fully settled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            completion()
        }
    }
}

// MARK: - Field Delegate (routes everything to controller)

private class RowFieldDelegate: NSObject, NSTextFieldDelegate {
    weak var row: TodoRowView?

    init(row: TodoRowView) { self.row = row }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let row else { return }
        row.controller?.rowDidBeginEditing(row)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        row?.onTextChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard let controller = row?.controller else { return false }

        switch sel {
        case #selector(NSResponder.moveUp(_:)):
            controller.moveUp()
            return true
        case #selector(NSResponder.moveDown(_:)):
            controller.moveDown()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            controller.submitRow()
            return true
        case #selector(NSResponder.insertTab(_:)):
            controller.moveDown()
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            controller.moveUp()
            return true
        default:
            return false
        }
    }
}

// MARK: - NSTextField: caret at end, no select-all

private class CaretEndTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
        // Sync selectedIndex when focus changes via click
        if result, let row = superview as? TodoRowView {
            row.controller?.rowDidBeginEditing(row)
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

// Custom field editor: intercepts select-all to prevent highlight flash
class CaretEndFieldEditor: NSTextView {
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        if charRange.length == string.count && charRange.length > 0 && !flag {
            super.setSelectedRange(NSRange(location: string.count, length: 0), affinity: affinity, stillSelecting: flag)
        } else {
            super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        }
    }
}

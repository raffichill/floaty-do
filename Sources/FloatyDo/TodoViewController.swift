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

        // Clear focus during animation
        view.window?.makeFirstResponder(nil)

        // Safety timeout: reset isAnimating if completion chain breaks
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isAnimating = false
        }

        // Phase 1: Check bounce + strikethrough (300ms)
        row.playCompletionAnimation { [weak self] in
            guard let self else { return }

            // Phase 2: Collapse row + fade out (300ms)
            self.animateRowCollapse(row: row) {
                // Post-animation: archive and rebuild
                self.store.archive(item)

                // selectedIndex stays at same position (now points to next item)
                if index < self.store.items.count {
                    self.selectedIndex = index
                } else {
                    // Archived the last item — land on the input row
                    self.selectedIndex = self.store.items.count
                }

                self.rebuildRows()
                self.isAnimating = false
            }
        }
    }

    private func animateRowCollapse(row: TodoRowView, completion: @escaping () -> Void) {
        row.layer?.masksToBounds = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            row.heightConstraint.animator().constant = 0
            row.animator().alphaValue = 0.0

            // Animate window frame to match new content height
            if let window = self.view.window {
                let newRowCount = max(self.rowCount - 1, 1)
                let contentHeight = CGFloat(newRowCount) * 36.0 + 16.5
                let fullHeight = max(contentHeight + window.titlebarHeight, window.minSize.height)
                let oldFrame = window.frame
                let newFrame = NSRect(
                    x: oldFrame.origin.x,
                    y: oldFrame.maxY - fullHeight,
                    width: oldFrame.width,
                    height: fullHeight
                )
                window.animator().setFrame(newFrame, display: true)
            }

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

    private func rebuildRows(resize: Bool = true) {
        for row in rowViews {
            stackView.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowViews.removeAll()

        let count = rowCount

        if currentTab == .tasks {
            rebuildTaskRows(count: count)
        } else {
            rebuildArchiveRows(count: count)
        }

        if selectedIndex >= count { selectedIndex = max(0, count - 1) }

        if resize { resizeWindow() }

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

    private func resizeWindow() {
        guard let window = view.window else { return }
        let rows = max(rowCount, 1)
        let contentHeight = CGFloat(rows) * 36.0 + 16.5
        let fullHeight = max(contentHeight + window.titlebarHeight, window.minSize.height)
        let oldFrame = window.frame
        let newFrame = NSRect(
            x: oldFrame.origin.x,
            y: oldFrame.maxY - fullHeight,
            width: oldFrame.width,
            height: fullHeight
        )
        window.setFrame(newFrame, display: true, animate: true)
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
        frame.height - contentRect(forFrameRect: frame).height
    }
}

// MARK: - Row View

final class TodoRowView: NSView {
    private let circleView: NSImageView
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
        circleView.contentTintColor = isDone
            ? NSColor.systemGreen.withAlphaComponent(circleOpacity)
            : NSColor.white.withAlphaComponent(circleOpacity)

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

        // Fix anchorPoint: macOS layer-backed views default to (0,0), we need (0.5,0.5) for center scaling
        let oldAnchor = circleLayer.anchorPoint
        let oldPosition = circleLayer.position
        let bounds = circleLayer.bounds
        circleLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        circleLayer.position = CGPoint(
            x: oldPosition.x + bounds.width * (0.5 - oldAnchor.x),
            y: oldPosition.y + bounds.height * (0.5 - oldAnchor.y)
        )

        // 1. Spring shrink the circle out from center
        let shrink = CASpringAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.0
        shrink.toValue = 0.0
        shrink.stiffness = 300
        shrink.damping = 30
        shrink.duration = shrink.settlingDuration
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        circleLayer.add(shrink, forKey: "shrinkOut")

        // 2. Swap icon mid-shrink, then spring grow the checkmark in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill",
                                      accessibilityDescription: nil)!
            self.circleView.image = checkImage.withSymbolConfiguration(config)
            self.circleView.contentTintColor = .white

            circleLayer.removeAnimation(forKey: "shrinkOut")

            let growIn = CASpringAnimation(keyPath: "transform.scale")
            growIn.fromValue = 0.0
            growIn.toValue = 1.0
            growIn.stiffness = 300
            growIn.damping = 30
            growIn.duration = growIn.settlingDuration
            growIn.fillMode = .forwards
            growIn.isRemovedOnCompletion = false
            circleLayer.add(growIn, forKey: "growIn")
        }

        // 3. Strikethrough line sweeping left to right
        if let textField = self.textField, !textField.stringValue.isEmpty {
            // Force layout so textField.frame is up to date
            self.layoutSubtreeIfNeeded()

            let textWidth = (textField.stringValue as NSString).size(
                withAttributes: [.font: textField.font!]
            ).width

            let strikeLayer = CAShapeLayer()
            let textFrame = textField.frame
            // NSView and CALayer both use bottom-left origin (non-flipped)
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
            strokeAnim.duration = 0.3
            strokeAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            strokeAnim.fillMode = .forwards
            strokeAnim.isRemovedOnCompletion = false
            strikeLayer.add(strokeAnim, forKey: "strikethrough")

            // 4. Fade text to dimmed
            let fadeText = CABasicAnimation(keyPath: "opacity")
            fadeText.fromValue = 1.0
            fadeText.toValue = 0.3
            fadeText.duration = 0.3
            fadeText.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fadeText.fillMode = .forwards
            fadeText.isRemovedOnCompletion = false
            textField.layer?.add(fadeText, forKey: "fadeText")
        }

        // Fire Phase 2 after 300ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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

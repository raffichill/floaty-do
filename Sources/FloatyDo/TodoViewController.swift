import AppKit

// MARK: - Controller

final class TodoViewController: NSViewController {
    private let store: TodoStore
    private let stackView = NSStackView()
    private var selectedIndex: Int = 0
    private var rowViews: [TodoRowView] = []
    private var eventMonitor: Any?

    init(store: TodoStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var rowCount: Int { min(store.items.count + 3, TodoStore.maxItems) }
    private var inputIndex: Int { store.items.count }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 200))
        container.wantsLayer = true

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
            divider.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
            stackView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Event monitor ONLY for cmd+key combos (cmd+return, cmd+delete)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command else { return event }

            if event.keyCode == 36 { // cmd+return
                if self.selectedIndex < self.store.items.count {
                    self.store.toggle(self.store.items[self.selectedIndex])
                    self.deferredRebuild()
                }
                return nil
            }
            if event.keyCode == 51 { // cmd+delete
                if self.selectedIndex < self.store.items.count {
                    self.store.delete(self.store.items[self.selectedIndex])
                    self.deferredRebuild()
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

    // MARK: - Navigation (called by field delegate via row callbacks)

    func moveUp() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
        focusRow(selectedIndex)
    }

    func moveDown() {
        guard selectedIndex < rowCount - 1 else { return }
        selectedIndex += 1
        focusRow(selectedIndex)
    }

    func submitRow() {
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

    private func rebuildRows() {
        for row in rowViews {
            stackView.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowViews.removeAll()

        let count = rowCount
        for i in 0..<count {
            let emptyIndex = i - store.items.count
            let emptyCount = count - store.items.count
            let row: TodoRowView

            if i < store.items.count {
                let item = store.items[i]
                row = TodoRowView(
                    text: item.text, isDone: item.isDone,
                    circleOpacity: item.isDone ? 1.0 : 0.4,
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

            // Wire navigation — every editable row talks to the controller
            row.controller = self

            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
            rowViews.append(row)
        }

        if selectedIndex >= count { selectedIndex = max(0, count - 1) }

        resizeWindow()

        // Focus after layout settles
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusRow(self.selectedIndex)
        }
    }

    private func resizeWindow() {
        guard let window = view.window else { return }
        let contentHeight = CGFloat(rowCount) * 36.0 + 16.5
        let fullHeight = contentHeight + window.titlebarHeight
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

        circleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circleView)

        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 36),
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
}

// MARK: - Field Delegate (routes everything to controller)

private class RowFieldDelegate: NSObject, NSTextFieldDelegate {
    weak var row: TodoRowView?

    init(row: TodoRowView) { self.row = row }

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

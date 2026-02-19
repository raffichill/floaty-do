import AppKit
import Combine

final class TodoViewController: NSViewController {
    private let store: TodoStore
    private let stackView = NSStackView()
    private var cancellables = Set<AnyCancellable>()
    private var selectedIndex: Int = 0
    private var rowViews: [TodoRowView] = []
    private var eventMonitor: Any?

    init(store: TodoStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var rowCount: Int {
        min(store.items.count + 3, TodoStore.maxItems)
    }

    private var inputIndex: Int { store.items.count }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 200))
        container.wantsLayer = true

        // Header divider
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

        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildRows() }
            .store(in: &cancellables)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handleKey(event) ?? event
        }

        rebuildRows()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Row management

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
                    text: item.text,
                    isDone: item.isDone,
                    circleOpacity: item.isDone ? 1.0 : 0.4,
                    isEditable: true
                )
                let index = i
                row.onTextChange = { [weak self] newText in
                    guard let self, index < self.store.items.count else { return }
                    self.store.items[index].text = newText
                }
            } else if i == store.items.count {
                row = TodoRowView(
                    text: "",
                    isDone: false,
                    circleOpacity: fadeOpacity(emptyIndex: emptyIndex, emptyCount: emptyCount),
                    isEditable: true
                )
                row.onSubmit = { [weak self] in
                    guard let self else { return }
                    let text = row.currentText
                    self.store.add(text)
                    row.setText("")
                    self.selectedIndex = self.inputIndex
                }
            } else {
                row = TodoRowView(
                    text: "",
                    isDone: false,
                    circleOpacity: fadeOpacity(emptyIndex: emptyIndex, emptyCount: emptyCount),
                    isEditable: false
                )
            }

            // Make each row fill the stack view width
            row.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

            rowViews.append(row)
        }

        // Clamp selectedIndex
        if selectedIndex >= count {
            selectedIndex = max(0, count - 1)
        }

        focusSelectedRow()
        resizeWindow()
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

    private func focusSelectedRow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectedIndex < self.rowViews.count else { return }
            self.rowViews[self.selectedIndex].focusTextField()
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

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.specialKey == .upArrow {
            if selectedIndex > 0 {
                selectedIndex -= 1
                focusSelectedRow()
            }
            return nil
        }

        if event.specialKey == .downArrow {
            if selectedIndex < rowCount - 1 {
                selectedIndex += 1
                focusSelectedRow()
            }
            return nil
        }

        if event.keyCode == 36 && mods == .command {
            if selectedIndex < store.items.count {
                store.toggle(store.items[selectedIndex])
            }
            return nil
        }

        if event.keyCode == 51 && mods == .command {
            if selectedIndex < store.items.count {
                store.delete(store.items[selectedIndex])
            }
            return nil
        }

        return event
    }
}

// MARK: - Helper to get titlebar height

private extension NSWindow {
    var titlebarHeight: CGFloat {
        frame.height - contentRect(forFrameRect: frame).height
    }
}

// MARK: - Row View

final class TodoRowView: NSView {
    private let circleView: NSImageView
    private var textField: NSTextField?
    var onTextChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?

    var currentText: String {
        textField?.stringValue ?? ""
    }

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

            let delegate = FieldDelegate()
            delegate.onChange = { [weak self] newText in self?.onTextChange?(newText) }
            delegate.onSubmit = { [weak self] in self?.onSubmit?() }
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

    func setText(_ text: String) {
        textField?.stringValue = text
    }

    func focusTextField() {
        guard let field = textField else { return }
        field.window?.makeFirstResponder(field)
    }
}

// MARK: - NSTextField that puts caret at end

private class CaretEndTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.currentEditor() as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
        return result
    }

    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.currentEditor() as? NSTextView else { return }
            editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        }
    }
}

// MARK: - Field Delegate

private class FieldDelegate: NSObject, NSTextFieldDelegate {
    var onChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        onChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?()
            return true
        }
        return false
    }
}

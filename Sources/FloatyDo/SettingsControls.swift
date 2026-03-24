import AppKit

final class ThemePresetButton: NSButton {
    private let outerCircle = NSView()
    private let innerCircle = NSView()
    private let pressedScale: CGFloat = 0.92

    var isSelected = false {
        didSet { updateAppearance() }
    }

    init(color: NSColor, selectedIndicatorColor: NSColor, selectedIndicatorOpacity: CGFloat, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        setButtonType(.momentaryChange)
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true

        outerCircle.wantsLayer = true
        outerCircle.translatesAutoresizingMaskIntoConstraints = false
        outerCircle.layer?.backgroundColor = color.cgColor
        outerCircle.layer?.cornerRadius = size / 2
        addSubview(outerCircle)

        innerCircle.wantsLayer = true
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.layer?.backgroundColor = selectedIndicatorColor.withAlphaComponent(selectedIndicatorOpacity).cgColor
        let innerCircleSize = round(size * 0.46)
        innerCircle.layer?.cornerRadius = innerCircleSize / 2
        addSubview(innerCircle)

        NSLayoutConstraint.activate([
            outerCircle.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerCircle.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerCircle.topAnchor.constraint(equalTo: topAnchor),
            outerCircle.bottomAnchor.constraint(equalTo: bottomAnchor),

            innerCircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: innerCircleSize),
            innerCircle.heightAnchor.constraint(equalToConstant: innerCircleSize),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        setPressedAppearance(true, duration: 0.08)
        super.mouseDown(with: event)
        setPressedAppearance(false, duration: 0.12)
    }

    private func updateAppearance() {
        innerCircle.isHidden = !isSelected
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
}

final class SettingsTabButton: PressScaleButton {
    private let container = NSView()
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var selectedTint: NSColor = .labelColor
    private var inactiveTint: NSColor = .secondaryLabelColor
    private var selectedBackgroundColor: NSColor = NSColor.black.withAlphaComponent(0.05)

    var isSelected = false {
        didSet { updateAppearance() }
    }

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        wantsLayer = true

        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: 11, weight: .regular)
        titleField.alignment = .center

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            imageView.image = image.withSymbolConfiguration(config)
        }

        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer?.cornerRadius = 12

        imageView.translatesAutoresizingMaskIntoConstraints = false
        titleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        container.addSubview(imageView)
        container.addSubview(titleField)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),

            titleField.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleField.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(selectedTint: NSColor, inactiveTint: NSColor, selectedBackground: NSColor) {
        self.selectedTint = selectedTint
        self.inactiveTint = inactiveTint
        self.selectedBackgroundColor = selectedBackground
        updateAppearance()
    }

    private func updateAppearance() {
        let tint = isSelected ? selectedTint : inactiveTint
        container.layer?.backgroundColor = isSelected
            ? selectedBackgroundColor.cgColor
            : NSColor.clear.cgColor
        imageView.contentTintColor = tint
        titleField.textColor = tint
    }
}

final class HotkeyRecorderButton: PressScaleButton {
    private let container = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { updateAppearance() }
    }

    var hotkey: GlobalHotkey = .defaultToggle {
        didSet { updateAppearance() }
    }

    var textColor: NSColor = .labelColor {
        didSet { updateAppearance() }
    }

    var borderColor: NSColor = NSColor.black.withAlphaComponent(0.16) {
        didSet { updateAppearance() }
    }

    var hoverBorderColor: NSColor = NSColor.black.withAlphaComponent(0.28) {
        didSet { updateAppearance() }
    }

    init() {
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        suppressSystemHighlight = true
        pressedScale = 0.97
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1

        titleField.alignment = .center
        titleField.font = .systemFont(ofSize: 10, weight: .medium)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        container.addSubview(titleField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            titleField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            titleField.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
    }

    private func updateAppearance() {
        titleField.textColor = textColor
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.borderColor = (isHovering ? hoverBorderColor : borderColor).cgColor
        titleField.stringValue = hotkey.displayString
    }
}

private final class HotkeyCaptureView: NSView {
    var onPreviewTokens: (([String]) -> Void)?
    var onCapture: ((GlobalHotkey) -> Void)?
    var onCancel: (() -> Void)?
    private var fallbackTokens: [String] = []

    override var acceptsFirstResponder: Bool { true }

    func beginRecording(showing tokens: [String]) {
        fallbackTokens = tokens
        onPreviewTokens?(tokens)
        window?.makeFirstResponder(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        let tokens = modifierTokens(from: event.modifierFlags)
        onPreviewTokens?(tokens.isEmpty ? fallbackTokens : tokens)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        guard let hotkey = GlobalHotkey(event: event) else {
            NSSound.beep()
            return
        }

        onPreviewTokens?(hotkey.displayTokens)
        onCapture?(hotkey)
    }

    private func modifierTokens(from flags: NSEvent.ModifierFlags) -> [String] {
        let filtered = flags.intersection([.control, .option, .shift, .command])
        var tokens: [String] = []
        if filtered.contains(.control) { tokens.append("control") }
        if filtered.contains(.option) { tokens.append("option") }
        if filtered.contains(.shift) { tokens.append("shift") }
        if filtered.contains(.command) { tokens.append("command") }
        return tokens
    }
}

final class HotkeyCapturePopoverViewController: NSViewController {
    var onCapture: ((GlobalHotkey) -> Void)?
    var onCancel: (() -> Void)?

    var backgroundColor: NSColor = .windowBackgroundColor {
        didSet { updateAppearance() }
    }

    var borderColor: NSColor = NSColor.black.withAlphaComponent(0.12) {
        didSet { updateAppearance() }
    }

    var primaryTextColor: NSColor = .labelColor {
        didSet { updateAppearance() }
    }

    var secondaryTextColor: NSColor = .secondaryLabelColor {
        didSet { updateAppearance() }
    }

    var keycapFillColor: NSColor = NSColor.black.withAlphaComponent(0.06) {
        didSet { updateKeycapAppearance() }
    }

    private let root = HotkeyCaptureView()
    private let bubble = NSView()
    private let keycapsRow = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Recording…")
    private let hintLabel = NSTextField(labelWithString: "Press Esc to cancel")
    private let closeButton = NSButton()

    private var previewTokens: [String] = []

    override func loadView() {
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false
        root.onPreviewTokens = { [weak self] tokens in
            self?.setPreviewTokens(tokens)
        }
        root.onCapture = { [weak self] hotkey in
            self?.onCapture?(hotkey)
        }
        root.onCancel = { [weak self] in
            self?.onCancel?()
        }

        bubble.wantsLayer = true
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer?.cornerRadius = 14
        bubble.layer?.borderWidth = 1

        keycapsRow.orientation = .horizontal
        keycapsRow.alignment = .centerY
        keycapsRow.spacing = 6
        keycapsRow.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.isBordered = false
        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Close hotkey recorder"
        )
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)

        root.addSubview(bubble)
        bubble.addSubview(closeButton)
        bubble.addSubview(keycapsRow)
        bubble.addSubview(statusLabel)
        bubble.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 244),
            root.heightAnchor.constraint(equalToConstant: 118),

            bubble.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: root.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            keycapsRow.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            keycapsRow.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 24),

            statusLabel.topAnchor.constraint(equalTo: keycapsRow.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            hintLabel.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
        ])

        view = root
        updateAppearance()
    }

    func beginRecording(currentHotkey: GlobalHotkey) {
        root.beginRecording(showing: currentHotkey.displayTokens)
    }

    private func setPreviewTokens(_ tokens: [String]) {
        previewTokens = tokens
        keycapsRow.arrangedSubviews.forEach {
            keycapsRow.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let visibleTokens = tokens.isEmpty ? ["Type keys"] : tokens
        visibleTokens.forEach { keycapsRow.addArrangedSubview(makeKeycap($0)) }
        updateKeycapAppearance()
    }

    private func makeKeycap(_ token: String) -> NSView {
        let label = NSTextField(labelWithString: GlobalHotkey.displayLabel(for: token))
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = primaryTextColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer?.cornerRadius = 8
        container.setContentHuggingPriority(.required, for: .horizontal)

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
            container.heightAnchor.constraint(equalToConstant: 32),
        ])
        return container
    }

    private func updateAppearance() {
        bubble.layer?.backgroundColor = backgroundColor.cgColor
        bubble.layer?.borderColor = borderColor.cgColor
        statusLabel.textColor = primaryTextColor
        hintLabel.textColor = secondaryTextColor
        closeButton.contentTintColor = secondaryTextColor
        updateKeycapAppearance()
    }

    private func updateKeycapAppearance() {
        keycapsRow.arrangedSubviews.forEach { view in
            view.layer?.backgroundColor = keycapFillColor.cgColor
            (view.subviews.first as? NSTextField)?.textColor = primaryTextColor
        }
    }

    @objc private func closeTapped() {
        onCancel?()
    }
}

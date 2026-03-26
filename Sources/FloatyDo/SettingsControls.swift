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

final class IconOptionButton: PressScaleButton {
    private enum Metrics {
        static let rowHeight: CGFloat = 92
        static let previewSize: CGFloat = 52
        static let previewCornerRadius: CGFloat = previewSize * 0.233
        static let titleToSubtitleSpacing: CGFloat = 3
        static let subtitleBaselineOffset: CGFloat = -4
        static let subtitleOpacity: CGFloat = 0.7
    }

    private let container = NSView()
    private let selectionRing = NSView()
    private let selectionDot = NSView()
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let textStack = NSStackView()

    private var primaryTextColor: NSColor = .labelColor
    private var accentColor: NSColor = .labelColor
    private var strokeColor: NSColor = NSColor.black.withAlphaComponent(0.12)

    var isOptionSelected = false {
        didSet { updateAppearance() }
    }

    var isCurrentOption = false {
        didSet { updateAppearance() }
    }

    var isPendingOption = false {
        didSet { updateAppearance() }
    }

    init(title: String, image: NSImage?) {
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        suppressSystemHighlight = true
        pressedScale = 0.985
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: 14, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        subtitleField.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.isHidden = true
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer?.cornerRadius = 12

        selectionRing.wantsLayer = true
        selectionRing.translatesAutoresizingMaskIntoConstraints = false
        selectionRing.layer?.cornerRadius = 10
        selectionRing.layer?.borderWidth = 1.5

        selectionDot.wantsLayer = true
        selectionDot.translatesAutoresizingMaskIntoConstraints = false
        selectionDot.layer?.cornerRadius = 5

        previewContainer.wantsLayer = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.layer?.cornerRadius = Metrics.previewCornerRadius
        previewContainer.layer?.cornerCurve = .continuous
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.borderWidth = 1

        previewImageView.image = image
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.translatesAutoresizingMaskIntoConstraints = false

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = Metrics.titleToSubtitleSpacing
        textStack.detachesHiddenViews = true
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(titleField)
        textStack.addArrangedSubview(subtitleField)

        addSubview(container)
        container.addSubview(selectionRing)
        selectionRing.addSubview(selectionDot)
        container.addSubview(previewContainer)
        previewContainer.addSubview(previewImageView)
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.rowHeight),

            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            selectionRing.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            selectionRing.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            selectionRing.widthAnchor.constraint(equalToConstant: 20),
            selectionRing.heightAnchor.constraint(equalToConstant: 20),

            selectionDot.centerXAnchor.constraint(equalTo: selectionRing.centerXAnchor),
            selectionDot.centerYAnchor.constraint(equalTo: selectionRing.centerYAnchor),
            selectionDot.widthAnchor.constraint(equalToConstant: 10),
            selectionDot.heightAnchor.constraint(equalToConstant: 10),

            previewContainer.leadingAnchor.constraint(equalTo: selectionRing.trailingAnchor, constant: 16),
            previewContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            previewContainer.widthAnchor.constraint(equalToConstant: Metrics.previewSize),
            previewContainer.heightAnchor.constraint(equalToConstant: Metrics.previewSize),

            previewImageView.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            previewImageView.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            textStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(
        primaryText: NSColor,
        accent: NSColor,
        stroke: NSColor
    ) {
        primaryTextColor = primaryText
        accentColor = accent
        strokeColor = stroke
        previewContainer.layer?.backgroundColor = NSColor.clear.cgColor
        updateAppearance()
    }

    private func updateAppearance() {
        container.layer?.backgroundColor = NSColor.clear.cgColor
        selectionRing.layer?.borderColor = (isOptionSelected ? accentColor : strokeColor).cgColor
        selectionDot.layer?.backgroundColor = accentColor.cgColor
        selectionDot.isHidden = !isOptionSelected
        previewContainer.layer?.borderColor = strokeColor.cgColor
        titleField.textColor = primaryTextColor

        if isCurrentOption {
            subtitleField.stringValue = "CURRENT ICON"
            subtitleField.isHidden = false
        } else {
            subtitleField.stringValue = ""
            subtitleField.isHidden = true
        }

        subtitleField.textColor = accentColor.withAlphaComponent(Metrics.subtitleOpacity)
        subtitleField.alphaValue = subtitleField.isHidden ? 0 : 1
        subtitleField.attributedStringValue = NSAttributedString(
            string: subtitleField.stringValue,
            attributes: [
                .font: subtitleField.font ?? .systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: accentColor.withAlphaComponent(Metrics.subtitleOpacity),
                .baselineOffset: Metrics.subtitleBaselineOffset,
            ]
        )
    }
}

final class InlineFooterTokenButton: PressScaleButton {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 3
        static let verticalPadding: CGFloat = 2
        static let minimumHeight: CGFloat = 18
        static let cornerRadius: CGFloat = 6
    }

    private let container = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    var leadingInsetAdjustment: CGFloat = 0 {
        didSet { updateInsets() }
    }

    var trailingInsetAdjustment: CGFloat = 0 {
        didSet { updateInsets() }
    }

    var tokenText: String = "" {
        didSet {
            titleField.stringValue = tokenText
            invalidateIntrinsicContentSize()
        }
    }

    var fillColor: NSColor = .labelColor {
        didSet { updateAppearance() }
    }

    var tokenTextColor: NSColor = .controlBackgroundColor {
        didSet { updateAppearance() }
    }

    var isInteractive = true

    init(text: String) {
        super.init(frame: .zero)
        tokenText = text
        setButtonType(.momentaryChange)
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        suppressSystemHighlight = true
        pressedScale = 0.985
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumHeight).isActive = true

        container.wantsLayer = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer?.cornerRadius = Metrics.cornerRadius
        container.layer?.cornerCurve = .continuous

        titleField.stringValue = text
        titleField.font = .systemFont(ofSize: 11, weight: .regular)
        titleField.alignment = .center
        titleField.lineBreakMode = .byClipping
        titleField.usesSingleLineMode = true
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleField.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(container)
        container.addSubview(titleField)

        let leadingConstraint = titleField.leadingAnchor.constraint(
            equalTo: container.leadingAnchor,
            constant: Metrics.horizontalPadding
        )
        let trailingConstraint = titleField.trailingAnchor.constraint(
            equalTo: container.trailingAnchor,
            constant: -Metrics.horizontalPadding
        )
        self.leadingConstraint = leadingConstraint
        self.trailingConstraint = trailingConstraint

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),

            leadingConstraint,
            trailingConstraint,
            titleField.topAnchor.constraint(
                equalTo: container.topAnchor,
                constant: Metrics.verticalPadding
            ),
            titleField.bottomAnchor.constraint(
                equalTo: container.bottomAnchor,
                constant: -Metrics.verticalPadding
            ),
        ])

        updateAppearance()
        updateInsets()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = titleField.intrinsicContentSize
        let horizontalInset = resolvedLeadingInset + resolvedTrailingInset
        return NSSize(
            width: ceil(labelSize.width) + horizontalInset,
            height: max(Metrics.minimumHeight, ceil(labelSize.height) + (Metrics.verticalPadding * 2))
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        super.mouseDown(with: event)
    }

    private func updateAppearance() {
        container.layer?.backgroundColor = fillColor.cgColor
        titleField.textColor = tokenTextColor
    }

    private var resolvedLeadingInset: CGFloat {
        Metrics.horizontalPadding + leadingInsetAdjustment
    }

    private var resolvedTrailingInset: CGFloat {
        Metrics.horizontalPadding + trailingInsetAdjustment
    }

    private func updateInsets() {
        leadingConstraint?.constant = resolvedLeadingInset
        trailingConstraint?.constant = -resolvedTrailingInset
        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

final class ShimmerStatusLabel: NSView {
    private enum Metrics {
        static let baseOpacity: CGFloat = 0.6
        static let animationDuration: CFTimeInterval = 1.15
        static let shimmerLocations: [NSNumber] = [0, 0.34, 0.5, 0.66, 1]
    }

    private let baseLabel = NSTextField(labelWithString: "")
    private let shimmerContainer = NSView()
    private let shimmerLabel = NSTextField(labelWithString: "")
    private let shimmerMask = CAGradientLayer()

    var stringValue: String = "" {
        didSet {
            baseLabel.stringValue = stringValue
            shimmerLabel.stringValue = stringValue
            invalidateIntrinsicContentSize()
        }
    }

    var textColor: NSColor = .labelColor {
        didSet { updateAppearance() }
    }

    var font: NSFont? {
        didSet {
            baseLabel.font = font
            shimmerLabel.font = font
            invalidateIntrinsicContentSize()
        }
    }

    var alignment: NSTextAlignment = .left {
        didSet {
            baseLabel.alignment = alignment
            shimmerLabel.alignment = alignment
        }
    }

    var lineBreakMode: NSLineBreakMode = .byTruncatingTail {
        didSet {
            baseLabel.lineBreakMode = lineBreakMode
            shimmerLabel.lineBreakMode = lineBreakMode
        }
    }

    var shimmerEnabled = false {
        didSet { updateShimmerState() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        [baseLabel, shimmerLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.usesSingleLineMode = true
            $0.lineBreakMode = .byTruncatingTail
            $0.alignment = .left
        }

        shimmerContainer.wantsLayer = true
        shimmerContainer.translatesAutoresizingMaskIntoConstraints = false
        shimmerContainer.layer?.masksToBounds = true
        shimmerMask.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerMask.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerMask.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.white.withAlphaComponent(1).cgColor,
            NSColor.white.withAlphaComponent(0.12).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        shimmerMask.locations = Metrics.shimmerLocations

        addSubview(baseLabel)
        addSubview(shimmerContainer)
        shimmerContainer.addSubview(shimmerLabel)

        NSLayoutConstraint.activate([
            baseLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            baseLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            baseLabel.topAnchor.constraint(equalTo: topAnchor),
            baseLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            shimmerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            shimmerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            shimmerContainer.topAnchor.constraint(equalTo: topAnchor),
            shimmerContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            shimmerLabel.leadingAnchor.constraint(equalTo: shimmerContainer.leadingAnchor),
            shimmerLabel.trailingAnchor.constraint(equalTo: shimmerContainer.trailingAnchor),
            shimmerLabel.topAnchor.constraint(equalTo: shimmerContainer.topAnchor),
            shimmerLabel.bottomAnchor.constraint(equalTo: shimmerContainer.bottomAnchor),
        ])

        updateAppearance()
        updateShimmerState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        baseLabel.intrinsicContentSize
    }

    override func layout() {
        super.layout()
        shimmerMask.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
        shimmerContainer.layer?.mask = shimmerMask
        if shimmerEnabled {
            startShimmerIfNeeded()
        }
    }

    private func updateAppearance() {
        baseLabel.textColor = textColor.withAlphaComponent(Metrics.baseOpacity)
        shimmerLabel.textColor = textColor
    }

    private func updateShimmerState() {
        shimmerContainer.isHidden = !shimmerEnabled
        if shimmerEnabled {
            startShimmerIfNeeded()
        } else {
            shimmerMask.removeAnimation(forKey: "shimmerSlide")
        }
    }

    private func startShimmerIfNeeded() {
        guard shimmerMask.animation(forKey: "shimmerSlide") == nil, bounds.width > 0 else { return }
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -bounds.width
        animation.toValue = bounds.width
        animation.duration = Metrics.animationDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0, 0.68, 1)
        shimmerMask.add(animation, forKey: "shimmerSlide")
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
        container.layer?.cornerRadius = 4
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

class HotkeyCaptureView: NSView {
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

private enum HotkeyCapturePopoverMetrics {
    static let width: CGFloat = 244
    static let bodyHeight: CGFloat = 118
    static let nubWidth: CGFloat = 34
    static let nubHeight: CGFloat = 14
    static let cornerRadius: CGFloat = 14
    static let shadowRadius: CGFloat = 18
    static let shadowOpacity: Float = 0.16
    static let shadowOffset = CGSize(width: 0, height: -2)
    static let anchorSpacing: CGFloat = 4
}

final class HotkeyCapturePopoverView: HotkeyCaptureView {
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

    private let chromeLayer = CAShapeLayer()
    private let contentContainer = NSView()
    private let keycapsRow = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Recording…")
    private let hintLabel = NSTextField(labelWithString: "Press Esc to cancel")
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: HotkeyCapturePopoverMetrics.width).isActive = true
        heightAnchor.constraint(
            equalToConstant: HotkeyCapturePopoverMetrics.bodyHeight
                + HotkeyCapturePopoverMetrics.nubHeight
        ).isActive = true

        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(chromeLayer)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = HotkeyCapturePopoverMetrics.shadowOpacity
        layer?.shadowRadius = HotkeyCapturePopoverMetrics.shadowRadius
        layer?.shadowOffset = HotkeyCapturePopoverMetrics.shadowOffset
        onPreviewTokens = { [weak self] tokens in
            self?.setPreviewTokens(tokens)
        }

        contentContainer.translatesAutoresizingMaskIntoConstraints = false

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

        addSubview(contentContainer)
        contentContainer.addSubview(closeButton)
        contentContainer.addSubview(keycapsRow)
        contentContainer.addSubview(statusLabel)
        contentContainer.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.topAnchor.constraint(
                equalTo: topAnchor, constant: HotkeyCapturePopoverMetrics.nubHeight),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            keycapsRow.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            keycapsRow.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 24),

            statusLabel.topAnchor.constraint(equalTo: keycapsRow.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            hintLabel.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateChromePath()
    }

    func beginRecording(currentHotkey: GlobalHotkey) {
        super.beginRecording(showing: currentHotkey.displayTokens)
    }

    private func updateChromePath() {
        let path = popoverPath(in: bounds)
        chromeLayer.path = path
        chromeLayer.frame = bounds
        layer?.shadowPath = path
    }

    private func popoverPath(in bounds: CGRect) -> CGPath {
        let radius = HotkeyCapturePopoverMetrics.cornerRadius
        let nubWidth = HotkeyCapturePopoverMetrics.nubWidth
        let nubHeight = HotkeyCapturePopoverMetrics.nubHeight
        let nubShoulder: CGFloat = 8
        let bodyTop = bounds.maxY - nubHeight
        let centerX = bounds.midX
        let left = bounds.minX
        let right = bounds.maxX
        let bottom = bounds.minY

        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + radius, y: bottom))
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addArc(
            center: CGPoint(x: right - radius, y: bottom + radius),
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: right, y: bodyTop - radius))
        path.addArc(
            center: CGPoint(x: right - radius, y: bodyTop - radius),
            radius: radius,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: centerX + nubWidth / 2 + nubShoulder, y: bodyTop))
        path.addCurve(
            to: CGPoint(x: centerX + nubWidth / 2, y: bodyTop),
            control1: CGPoint(x: centerX + nubWidth / 2 + 4, y: bodyTop),
            control2: CGPoint(x: centerX + nubWidth / 2 + 2, y: bodyTop)
        )
        path.addCurve(
            to: CGPoint(x: centerX, y: bounds.maxY),
            control1: CGPoint(x: centerX + nubWidth / 2 - 5, y: bodyTop),
            control2: CGPoint(x: centerX + 6, y: bounds.maxY)
        )
        path.addCurve(
            to: CGPoint(x: centerX - nubWidth / 2, y: bodyTop),
            control1: CGPoint(x: centerX - 6, y: bounds.maxY),
            control2: CGPoint(x: centerX - nubWidth / 2 + 5, y: bodyTop)
        )
        path.addCurve(
            to: CGPoint(x: centerX - nubWidth / 2 - nubShoulder, y: bodyTop),
            control1: CGPoint(x: centerX - nubWidth / 2 - 2, y: bodyTop),
            control2: CGPoint(x: centerX - nubWidth / 2 - 4, y: bodyTop)
        )
        path.addLine(to: CGPoint(x: left + radius, y: bodyTop))
        path.addArc(
            center: CGPoint(x: left + radius, y: bodyTop - radius),
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: false
        )
        path.addLine(to: CGPoint(x: left, y: bottom + radius))
        path.addArc(
            center: CGPoint(x: left + radius, y: bottom + radius),
            radius: radius,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    private func setPreviewTokens(_ tokens: [String]) {
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
        chromeLayer.fillColor = backgroundColor.cgColor
        chromeLayer.strokeColor = borderColor.cgColor
        chromeLayer.lineWidth = 1
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

final class HotkeyCaptureOverlayView: NSView {
    let popoverView = HotkeyCapturePopoverView()
    var onOutsideClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(popoverView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView ?? self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !popoverView.frame.contains(point) else {
            super.mouseDown(with: event)
            return
        }
        onOutsideClick?()
    }
}

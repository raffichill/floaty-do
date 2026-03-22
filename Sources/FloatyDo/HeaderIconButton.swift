import AppKit

private final class NonVibrantSymbolImageView: NSImageView {
    override var allowsVibrancy: Bool { false }
}

final class HeaderIconButton: PressScaleButton {
    private let iconView = NonVibrantSymbolImageView()
    var onHoverChange: ((Bool) -> Void)?
    private(set) var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            onHoverChange?(isHovered)
        }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override var allowsVibrancy: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    init(symbolName: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setButtonType(.momentaryChange)
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let configuredImage = image.withSymbolConfiguration(config)
            configuredImage?.isTemplate = true
            iconView.image = configuredImage
        }

        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if let cell = cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTint(_ tint: NSColor) {
        iconView.contentTintColor = tint
    }

    func resetHoverState() {
        isHovered = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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

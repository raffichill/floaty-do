import AppKit

final class ThemePresetButton: NSButton {
    private let outerCircle = NSView()
    private let innerCircle = NSView()

    var isSelected = false {
        didSet { updateAppearance() }
    }

    init(color: NSColor, size: CGFloat) {
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
        innerCircle.layer?.backgroundColor = NSColor.white.cgColor
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

    private func updateAppearance() {
        innerCircle.isHidden = !isSelected
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

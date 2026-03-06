import AppKit

final class SettingsViewController: NSViewController {
    var onPreferencesChange: ((AppPreferences) -> Void)?

    private var preferences: AppPreferences
    private var rowHeightSlider: NSSlider!
    private var rowHeightValueLabel: NSTextField!
    private var panelWidthSlider: NSSlider!
    private var panelWidthValueLabel: NSTextField!
    private var snapPaddingSlider: NSSlider!
    private var snapPaddingValueLabel: NSTextField!
    private var animationPresetButton: NSPopUpButton!

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 220))
        root.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let title = NSTextField(labelWithString: "Interface")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        stack.addArrangedSubview(title)

        rowHeightSlider = NSSlider(value: preferences.rowHeight, minValue: LayoutMetrics.minRowHeight, maxValue: LayoutMetrics.maxRowHeight, target: self, action: #selector(rowHeightChanged(_:)))
        rowHeightValueLabel = valueLabel()
        stack.addArrangedSubview(makeSliderRow(title: "Row height", slider: rowHeightSlider, valueLabel: rowHeightValueLabel))

        panelWidthSlider = NSSlider(value: preferences.panelWidth, minValue: LayoutMetrics.minPanelWidth, maxValue: LayoutMetrics.maxPanelWidth, target: self, action: #selector(panelWidthChanged(_:)))
        panelWidthValueLabel = valueLabel()
        stack.addArrangedSubview(makeSliderRow(title: "Panel width", slider: panelWidthSlider, valueLabel: panelWidthValueLabel))

        snapPaddingSlider = NSSlider(value: preferences.snapPadding, minValue: 0, maxValue: 80, target: self, action: #selector(snapPaddingChanged(_:)))
        snapPaddingValueLabel = valueLabel()
        stack.addArrangedSubview(makeSliderRow(title: "Snap padding", slider: snapPaddingSlider, valueLabel: snapPaddingValueLabel))

        let animationRow = NSStackView()
        animationRow.orientation = .horizontal
        animationRow.alignment = .centerY
        animationRow.spacing = 8

        let animationLabel = NSTextField(labelWithString: "Motion")
        animationLabel.font = .systemFont(ofSize: 12)

        animationPresetButton = NSPopUpButton()
        animationPresetButton.translatesAutoresizingMaskIntoConstraints = false
        animationPresetButton.target = self
        animationPresetButton.action = #selector(animationPresetChanged(_:))
        AnimationPreset.allCases.forEach { preset in
            animationPresetButton.addItem(withTitle: preset.displayName)
            animationPresetButton.lastItem?.representedObject = preset.rawValue
        }
        animationPresetButton.widthAnchor.constraint(equalToConstant: 140).isActive = true
        if let index = AnimationPreset.allCases.firstIndex(of: preferences.animationPreset) {
            animationPresetButton.selectItem(at: index)
        }

        animationRow.addArrangedSubview(animationLabel)
        animationRow.addArrangedSubview(animationPresetButton)
        stack.addArrangedSubview(animationRow)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -16),
        ])

        self.view = root
        refreshValueLabels()
    }

    private func makeSliderRow(title: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 4
        container.alignment = .leading

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        topRow.addArrangedSubview(label)
        topRow.addArrangedSubview(valueLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 240).isActive = true

        container.addArrangedSubview(topRow)
        container.addArrangedSubview(slider)
        return container
    }

    private func valueLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func refreshValueLabels() {
        rowHeightValueLabel.stringValue = "\(Int(preferences.rowHeight)) px"
        panelWidthValueLabel.stringValue = "\(Int(preferences.panelWidth)) px"
        snapPaddingValueLabel.stringValue = "\(Int(preferences.snapPadding)) px"
    }

    private func pushPreferences() {
        refreshValueLabels()
        onPreferencesChange?(preferences)
    }

    @objc private func rowHeightChanged(_ sender: NSSlider) {
        preferences.rowHeight = sender.doubleValue.rounded()
        pushPreferences()
    }

    @objc private func panelWidthChanged(_ sender: NSSlider) {
        preferences.panelWidth = sender.doubleValue.rounded()
        pushPreferences()
    }

    @objc private func snapPaddingChanged(_ sender: NSSlider) {
        preferences.snapPadding = sender.doubleValue.rounded()
        pushPreferences()
    }

    @objc private func animationPresetChanged(_ sender: NSPopUpButton) {
        let selectedPreset = AnimationPreset.allCases[sender.indexOfSelectedItem]
        preferences.animationPreset = selectedPreset
        pushPreferences()
    }
}

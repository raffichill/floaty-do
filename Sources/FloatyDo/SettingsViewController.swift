import AppKit

final class SettingsViewController: NSTabViewController {
    var onPreferencesChange: ((AppPreferences) -> Void)?

    private var preferences: AppPreferences

    private lazy var themePane = ThemeSettingsPaneViewController(preferences: preferences)
    private lazy var fontPane = FontSettingsPaneViewController(preferences: preferences)
    private lazy var shapePane = ShapeSettingsPaneViewController(preferences: preferences)

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tabStyle = .toolbar
        transitionOptions = []
        preferredContentSize = NSSize(width: 820, height: 560)

        configurePanes()
        addTabViewItem(makeTabItem(for: themePane, label: "Theme", symbolName: "paintpalette"))
        addTabViewItem(makeTabItem(for: fontPane, label: "Font", symbolName: "textformat.size"))
        addTabViewItem(makeTabItem(for: shapePane, label: "Shape", symbolName: "square.on.square"))
    }

    func updatePreferences(_ preferences: AppPreferences) {
        self.preferences = preferences
        guard isViewLoaded else { return }
        themePane.updatePreferences(preferences)
        fontPane.updatePreferences(preferences)
        shapePane.updatePreferences(preferences)
    }

    private func configurePanes() {
        let panes: [SettingsPaneViewController] = [themePane, fontPane, shapePane]
        panes.forEach { pane in
            pane.onPreferencesChange = { [weak self] updatedPreferences in
                self?.handlePreferencesChange(updatedPreferences)
            }
        }

    }

    private func handlePreferencesChange(_ preferences: AppPreferences) {
        self.preferences = preferences
        updatePreferences(preferences)
        onPreferencesChange?(preferences)
    }

    private func makeTabItem(for viewController: NSViewController, label: String, symbolName: String) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: viewController)
        item.label = label
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) {
            image.isTemplate = true
            item.image = image
        }
        return item
    }
}

private class SettingsPaneViewController: NSViewController {
    var onPreferencesChange: ((AppPreferences) -> Void)?

    private(set) var preferences: AppPreferences
    private let previewCardView = SettingsPreviewCardView()
    private let contentStack = NSStackView()

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 28
        content.translatesAutoresizingMaskIntoConstraints = false

        let previewSection = NSStackView()
        previewSection.orientation = .vertical
        previewSection.alignment = .leading
        previewSection.spacing = 14
        previewSection.translatesAutoresizingMaskIntoConstraints = false

        let previewLabel = NSTextField(labelWithString: "Live Preview")
        previewLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        previewLabel.textColor = .secondaryLabelColor
        previewSection.addArrangedSubview(previewLabel)

        previewCardView.translatesAutoresizingMaskIntoConstraints = false
        previewSection.addArrangedSubview(previewCardView)
        previewCardView.widthAnchor.constraint(equalToConstant: 280).isActive = true
        previewCardView.heightAnchor.constraint(equalToConstant: 360).isActive = true

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let controlsSection = NSView()
        controlsSection.translatesAutoresizingMaskIntoConstraints = false
        controlsSection.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: controlsSection.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: controlsSection.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: controlsSection.trailingAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: controlsSection.bottomAnchor),
            controlsSection.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
        ])

        content.addArrangedSubview(previewSection)
        content.addArrangedSubview(controlsSection)
        root.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 30),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -30),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildControls(into: contentStack)
        applyPreferencesToControls()
        previewCardView.update(preferences: preferences)
    }

    func updatePreferences(_ preferences: AppPreferences) {
        self.preferences = preferences
        guard isViewLoaded else { return }
        applyPreferencesToControls()
        previewCardView.update(preferences: preferences)
    }

    func buildControls(into stack: NSStackView) {
        fatalError("Subclasses must implement buildControls(into:)")
    }

    func applyPreferencesToControls() {
        fatalError("Subclasses must implement applyPreferencesToControls()")
    }

    func updatePreferences(mutating mutation: (inout AppPreferences) -> Void) {
        var updated = preferences
        mutation(&updated)
        preferences = updated
        previewCardView.update(preferences: updated)
        onPreferencesChange?(updated)
    }

    func makeCard(title: String, subtitle: String? = nil, content: NSView) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer?.cornerRadius = 18
        card.layer?.backgroundColor = NSColor(
            red: 0.965,
            green: 0.969,
            blue: 0.978,
            alpha: 1.0
        ).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        stack.addArrangedSubview(titleLabel)

        if let subtitle {
            let subtitleLabel = NSTextField(wrappingLabelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 12)
            subtitleLabel.textColor = .secondaryLabelColor
            stack.addArrangedSubview(subtitleLabel)
        }

        stack.addArrangedSubview(content)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            card.widthAnchor.constraint(equalToConstant: 420),
        ])

        return card
    }

    func makeSliderRow(
        title: String,
        minValue: Double,
        maxValue: Double,
        target: AnyObject,
        action: Selector
    ) -> (view: NSView, slider: NSSlider, valueLabel: NSTextField) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor

        let valueLabel = NSTextField(labelWithString: "")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(valueLabel)

        let slider = NSSlider(value: minValue, minValue: minValue, maxValue: maxValue, target: target, action: action)
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false

        container.addArrangedSubview(header)
        container.addArrangedSubview(slider)
        container.widthAnchor.constraint(equalToConstant: 380).isActive = true

        return (container, slider, valueLabel)
    }

    func makeLabeledPopup(
        title: String,
        items: [String],
        target: AnyObject,
        action: Selector
    ) -> (view: NSView, popup: NSPopUpButton) {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor

        let popup = NSPopUpButton()
        popup.addItems(withTitles: items)
        popup.target = target
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 220).isActive = true

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(popup)

        return (container, popup)
    }
}

private final class ThemeSettingsPaneViewController: SettingsPaneViewController {
    private let colorWell = NSColorWell()
    private var motionPopup: NSPopUpButton!

    override func buildControls(into stack: NSStackView) {
        let colorContent = NSStackView()
        colorContent.orientation = .vertical
        colorContent.alignment = .leading
        colorContent.spacing = 12
        colorContent.translatesAutoresizingMaskIntoConstraints = false

        let colorLabel = NSTextField(labelWithString: "Accent color")
        colorLabel.font = .systemFont(ofSize: 13, weight: .medium)
        colorLabel.textColor = .labelColor

        colorWell.target = self
        colorWell.action = #selector(colorChanged(_:))
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 96).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 34).isActive = true

        colorContent.addArrangedSubview(colorLabel)
        colorContent.addArrangedSubview(colorWell)

        let motionContent = makeLabeledPopup(
            title: "Animation feel",
            items: AnimationPreset.allCases.map(\.displayName),
            target: self,
            action: #selector(motionChanged(_:))
        )
        motionPopup = motionContent.popup

        stack.addArrangedSubview(
            makeCard(
                title: "Color",
                subtitle: "Set the active row theme color for the live app surface.",
                content: colorContent
            )
        )
        stack.addArrangedSubview(
            makeCard(
                title: "Motion",
                subtitle: "Tune the overall timing preset for list motion and window movement.",
                content: motionContent.view
            )
        )
    }

    override func applyPreferencesToControls() {
        colorWell.color = preferences.themeColor.nsColor
        motionPopup.removeAllItems()
        motionPopup.addItems(withTitles: AnimationPreset.allCases.map(\.displayName))
        if let index = AnimationPreset.allCases.firstIndex(of: preferences.animationPreset) {
            motionPopup.selectItem(at: index)
        }
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        updatePreferences { preferences in
            preferences.themeColor = ThemeColor(nsColor: sender.color)
        }
    }

    @objc private func motionChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        let preset = AnimationPreset.allCases[sender.indexOfSelectedItem]
        updatePreferences { preferences in
            preferences.animationPreset = preset
        }
    }
}

private final class FontSettingsPaneViewController: SettingsPaneViewController {
    private var fontPopup: NSPopUpButton!
    private var fontSizeSlider: NSSlider!
    private var fontSizeValueLabel: NSTextField!
    private var rowHeightSlider: NSSlider!
    private var rowHeightValueLabel: NSTextField!

    override func buildControls(into stack: NSStackView) {
        let fontPicker = makeLabeledPopup(
            title: "Font family",
            items: FontStylePreset.allCases.map(\.displayName),
            target: self,
            action: #selector(fontStyleChanged(_:))
        )
        fontPopup = fontPicker.popup

        let fontSizeRow = makeSliderRow(
            title: "Font size",
            minValue: LayoutMetrics.minFontSize,
            maxValue: LayoutMetrics.maxFontSize,
            target: self,
            action: #selector(fontSizeChanged(_:))
        )
        fontSizeSlider = fontSizeRow.slider
        fontSizeValueLabel = fontSizeRow.valueLabel

        let rowHeightRow = makeSliderRow(
            title: "Row height",
            minValue: LayoutMetrics.minRowHeight,
            maxValue: LayoutMetrics.maxRowHeight,
            target: self,
            action: #selector(rowHeightChanged(_:))
        )
        rowHeightSlider = rowHeightRow.slider
        rowHeightValueLabel = rowHeightRow.valueLabel

        stack.addArrangedSubview(
            makeCard(
                title: "Typography",
                subtitle: "Choose the face and optical size used across tasks, drafts, and selection states.",
                content: {
                    let content = NSStackView(views: [fontPicker.view, fontSizeRow.view])
                    content.orientation = .vertical
                    content.alignment = .leading
                    content.spacing = 14
                    return content
                }()
            )
        )
        stack.addArrangedSubview(
            makeCard(
                title: "Density",
                subtitle: "Adjust how spacious each row feels without changing the overall panel structure.",
                content: rowHeightRow.view
            )
        )
    }

    override func applyPreferencesToControls() {
        fontPopup.removeAllItems()
        fontPopup.addItems(withTitles: FontStylePreset.allCases.map(\.displayName))
        if let index = FontStylePreset.allCases.firstIndex(of: preferences.fontStyle) {
            fontPopup.selectItem(at: index)
        }
        fontSizeSlider.doubleValue = preferences.fontSize
        fontSizeValueLabel.stringValue = "\(Int(preferences.fontSize.rounded())) pt"
        rowHeightSlider.doubleValue = preferences.rowHeight
        rowHeightValueLabel.stringValue = "\(Int(preferences.rowHeight.rounded())) px"
    }

    @objc private func fontStyleChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        let preset = FontStylePreset.allCases[sender.indexOfSelectedItem]
        updatePreferences { preferences in
            preferences.fontStyle = preset
        }
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        fontSizeValueLabel.stringValue = "\(Int(value)) pt"
        updatePreferences { preferences in
            preferences.fontSize = value
        }
    }

    @objc private func rowHeightChanged(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        rowHeightValueLabel.stringValue = "\(Int(value)) px"
        updatePreferences { preferences in
            preferences.rowHeight = value
        }
    }
}

private final class ShapeSettingsPaneViewController: SettingsPaneViewController {
    private var radiusSlider: NSSlider!
    private var radiusValueLabel: NSTextField!
    private var widthSlider: NSSlider!
    private var widthValueLabel: NSTextField!
    private var snapSlider: NSSlider!
    private var snapValueLabel: NSTextField!

    override func buildControls(into stack: NSStackView) {
        let radiusRow = makeSliderRow(
            title: "Border radius",
            minValue: LayoutMetrics.minCornerRadius,
            maxValue: LayoutMetrics.maxCornerRadius,
            target: self,
            action: #selector(radiusChanged(_:))
        )
        radiusSlider = radiusRow.slider
        radiusValueLabel = radiusRow.valueLabel

        let widthRow = makeSliderRow(
            title: "Panel width",
            minValue: LayoutMetrics.minPanelWidth,
            maxValue: LayoutMetrics.maxPanelWidth,
            target: self,
            action: #selector(widthChanged(_:))
        )
        widthSlider = widthRow.slider
        widthValueLabel = widthRow.valueLabel

        let snapRow = makeSliderRow(
            title: "Snap padding",
            minValue: 0,
            maxValue: 80,
            target: self,
            action: #selector(snapChanged(_:))
        )
        snapSlider = snapRow.slider
        snapValueLabel = snapRow.valueLabel

        stack.addArrangedSubview(
            makeCard(
                title: "Surface",
                subtitle: "Control the roundness and visual footprint of the panel and active row surfaces.",
                content: {
                    let content = NSStackView(views: [radiusRow.view, widthRow.view])
                    content.orientation = .vertical
                    content.alignment = .leading
                    content.spacing = 14
                    return content
                }()
            )
        )
        stack.addArrangedSubview(
            makeCard(
                title: "Window snapping",
                subtitle: "Set how much space the panel keeps from the screen edges when it snaps around.",
                content: snapRow.view
            )
        )
    }

    override func applyPreferencesToControls() {
        radiusSlider.doubleValue = preferences.cornerRadius
        radiusValueLabel.stringValue = "\(Int(preferences.cornerRadius.rounded())) px"
        widthSlider.doubleValue = preferences.panelWidth
        widthValueLabel.stringValue = "\(Int(preferences.panelWidth.rounded())) px"
        snapSlider.doubleValue = preferences.snapPadding
        snapValueLabel.stringValue = "\(Int(preferences.snapPadding.rounded())) px"
    }

    @objc private func radiusChanged(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        radiusValueLabel.stringValue = "\(Int(value)) px"
        updatePreferences { preferences in
            preferences.cornerRadius = value
        }
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        widthValueLabel.stringValue = "\(Int(value)) px"
        updatePreferences { preferences in
            preferences.panelWidth = value
        }
    }

    @objc private func snapChanged(_ sender: NSSlider) {
        let value = sender.doubleValue.rounded()
        snapValueLabel.stringValue = "\(Int(value)) px"
        updatePreferences { preferences in
            preferences.snapPadding = value
        }
    }
}

private final class SettingsPreviewCardView: NSView {
    private let cardBackground = NSView()
    private let panelPreview = NSView()
    private let headerStack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "FloatyDo")
    private let subtitleLabel = NSTextField(labelWithString: "Appearance")
    private let rowStack = NSStackView()
    private let rowViews = [PreviewRowView(), PreviewRowView(), PreviewRowView()]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        cardBackground.wantsLayer = true
        cardBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardBackground)

        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)

        panelPreview.wantsLayer = true
        panelPreview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panelPreview)
        addSubview(headerStack)

        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        panelPreview.addSubview(rowStack)

        rowViews.forEach { rowStack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            cardBackground.topAnchor.constraint(equalTo: topAnchor),
            cardBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardBackground.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            panelPreview.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            panelPreview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            panelPreview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            panelPreview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),

            rowStack.topAnchor.constraint(equalTo: panelPreview.topAnchor, constant: 18),
            rowStack.leadingAnchor.constraint(equalTo: panelPreview.leadingAnchor, constant: 14),
            rowStack.trailingAnchor.constraint(equalTo: panelPreview.trailingAnchor, constant: -14),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(preferences: AppPreferences) {
        layer?.cornerRadius = 26
        layer?.backgroundColor = NSColor(
            red: 0.976,
            green: 0.978,
            blue: 0.984,
            alpha: 1.0
        ).cgColor
        cardBackground.layer?.cornerRadius = 26
        cardBackground.layer?.backgroundColor = NSColor(
            red: 0.976,
            green: 0.978,
            blue: 0.984,
            alpha: 1.0
        ).cgColor
        cardBackground.layer?.borderWidth = 1
        cardBackground.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor

        panelPreview.layer?.cornerRadius = 24
        panelPreview.layer?.backgroundColor = NSColor(
            red: 0.039,
            green: 0.039,
            blue: 0.094,
            alpha: 1.0
        ).cgColor

        titleLabel.font = preferences.appFont(weight: .semibold).withSize(16)
        subtitleLabel.font = preferences.appFont(weight: .medium).withSize(12)

        let samples = [
            ("Plan sprint scope", false),
            ("Review calendar", true),
            ("Clean archive", false),
        ]

        for (rowView, sample) in zip(rowViews, samples) {
            rowView.configure(
                text: sample.0,
                selected: sample.1,
                preferences: preferences
            )
        }
    }
}

private final class PreviewRowView: NSView {
    private let backgroundView = NSView()
    private let circleView = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 42).isActive = true

        backgroundView.wantsLayer = true
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        circleView.wantsLayer = true
        circleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circleView)

        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            circleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 18),
            circleView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: circleView.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, selected: Bool, preferences: AppPreferences) {
        backgroundView.layer?.cornerRadius = CGFloat(preferences.cornerRadius)
        backgroundView.layer?.backgroundColor = selected
            ? preferences.activeFillColor.cgColor
            : NSColor.clear.cgColor

        circleView.layer?.cornerRadius = 9
        circleView.layer?.borderWidth = 2
        circleView.layer?.borderColor = NSColor.white.withAlphaComponent(selected ? 0.95 : 0.4).cgColor
        circleView.layer?.backgroundColor = NSColor.clear.cgColor

        label.stringValue = text
        label.font = preferences.appFont(weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(selected ? 0.98 : 0.9)
    }
}

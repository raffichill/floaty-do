import AppKit

final class SettingsViewController: NSViewController {
    private enum Metrics {
        static let labelWidth: CGFloat = 112
        static let controlWidth: CGFloat = 360
        static let rowHeight: CGFloat = 58
        static let rowSpacing: CGFloat = 2
        static let sliderGroupWidth: CGFloat = 200
        static let sliderWidth: CGFloat = 148
        static let popupWidth: CGFloat = 200
        static let valueWidth: CGFloat = 44
        static let sliderValueSpacing: CGFloat = 8
        static let iconStatusWidth: CGFloat = 190
        static let iconButtonWidth: CGFloat = 158
    }

    var onPreferencesChange: ((AppPreferences) -> Void)?

    private var preferences: AppPreferences
    private var isUpdatingControls = false

    private let titleLabel = NSTextField(labelWithString: "Theme")
    private let divider = NSBox()

    private let resetThemeButton = NSButton(title: "Reset", target: nil, action: nil)
    private let iconStatusLabel = NSTextField(labelWithString: "")
    private let applyIconButton = NSButton(title: "Apply & Relaunch", target: nil, action: nil)
    private var themeButtons: [ThemePresetButton] = []
    private let fontPopup = NSPopUpButton()
    private let resetFontButton = NSButton(title: "Reset", target: nil, action: nil)
    private let fontSizeSlider = NSSlider()
    private let fontSizeDetailLabel = NSTextField(labelWithString: "")
    private let resetFontSizeButton = NSButton(title: "Reset", target: nil, action: nil)
    private let borderRadiusSlider = NSSlider()
    private let borderRadiusValueLabel = NSTextField(labelWithString: "")
    private let resetRadiusButton = NSButton(title: "Reset", target: nil, action: nil)

    private let contentStack = NSStackView()
    private var currentAppliedIconTheme: BuiltInTheme
    private var isApplyingPrimaryIconChange = false

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.currentAppliedIconTheme = PrimaryAppIconRelaunchController.shared.currentTheme()
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

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Metrics.rowSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleLabel)
        root.addSubview(divider)
        root.addSubview(contentStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            divider.topAnchor.constraint(equalTo: root.topAnchor, constant: 45),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 24),
            contentStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -28),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildControls()
        applyPreferencesToControls()
    }

    func updatePreferences(_ preferences: AppPreferences) {
        guard self.preferences != preferences else { return }
        self.preferences = preferences
        guard isViewLoaded else { return }
        applyPreferencesToControls()
    }

    private func buildControls() {
        contentStack.arrangedSubviews.forEach { subview in
            contentStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        configureThemeButtons()
        configureIconApplyControls()
        configureFontPopup()
        configureFontSizeSlider()
        configureBorderRadiusSlider()

        contentStack.addArrangedSubview(makeFormRow(title: "Background", control: makeThemeControl()))
        contentStack.addArrangedSubview(makeFormRow(title: "App Icon", control: makeAppIconControl()))
        contentStack.addArrangedSubview(makeFormRow(title: "Font", control: makeFontControl()))
        contentStack.addArrangedSubview(makeFormRow(title: "Font Size", control: makeFontSizeControl()))
        contentStack.addArrangedSubview(makeFormRow(title: "Radius", control: makeBorderRadiusControl()))
    }

    private func configureThemeButtons() {
        themeButtons = BuiltInTheme.allCases.enumerated().map { index, theme in
            let button = ThemePresetButton(color: theme.color.nsColor)
            button.tag = index
            button.target = self
            button.action = #selector(themePresetSelected(_:))
            return button
        }

        resetThemeButton.target = self
        resetThemeButton.action = #selector(resetThemeColor(_:))
        resetThemeButton.bezelStyle = .rounded
        resetThemeButton.controlSize = .small
    }

    private func configureIconApplyControls() {
        iconStatusLabel.font = .systemFont(ofSize: 11)
        iconStatusLabel.textColor = .secondaryLabelColor
        iconStatusLabel.alignment = .left
        iconStatusLabel.lineBreakMode = .byTruncatingTail
        iconStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        iconStatusLabel.widthAnchor.constraint(equalToConstant: Metrics.iconStatusWidth).isActive = true

        applyIconButton.target = self
        applyIconButton.action = #selector(applyIconAndRelaunch(_:))
        applyIconButton.bezelStyle = .rounded
        applyIconButton.controlSize = .small
        applyIconButton.font = .systemFont(ofSize: 12)
        applyIconButton.translatesAutoresizingMaskIntoConstraints = false
        applyIconButton.widthAnchor.constraint(equalToConstant: Metrics.iconButtonWidth).isActive = true
    }

    private func configureFontPopup() {
        fontPopup.removeAllItems()
        fontPopup.addItems(withTitles: FontStylePreset.allCases.map(\.displayName))
        fontPopup.target = self
        fontPopup.action = #selector(fontChanged(_:))
        fontPopup.controlSize = .small
        fontPopup.font = .systemFont(ofSize: 12)
        fontPopup.translatesAutoresizingMaskIntoConstraints = false
        fontPopup.widthAnchor.constraint(equalToConstant: Metrics.popupWidth).isActive = true

        resetFontButton.target = self
        resetFontButton.action = #selector(resetFont(_:))
        resetFontButton.bezelStyle = .rounded
        resetFontButton.controlSize = .small
    }

    private func configureFontSizeSlider() {
        fontSizeSlider.minValue = 0
        fontSizeSlider.maxValue = Double(LayoutMetrics.fontSizeOptions.count - 1)
        fontSizeSlider.numberOfTickMarks = LayoutMetrics.fontSizeOptions.count
        fontSizeSlider.allowsTickMarkValuesOnly = false
        fontSizeSlider.isContinuous = true
        fontSizeSlider.sendAction(on: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged(_:))
        fontSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        fontSizeSlider.widthAnchor.constraint(equalToConstant: Metrics.sliderWidth).isActive = true

        fontSizeDetailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        fontSizeDetailLabel.textColor = .secondaryLabelColor
        fontSizeDetailLabel.alignment = .right
        fontSizeDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        fontSizeDetailLabel.widthAnchor.constraint(equalToConstant: Metrics.valueWidth).isActive = true

        resetFontSizeButton.target = self
        resetFontSizeButton.action = #selector(resetFontSize(_:))
        resetFontSizeButton.bezelStyle = .rounded
        resetFontSizeButton.controlSize = .small
    }

    private func configureBorderRadiusSlider() {
        borderRadiusSlider.minValue = LayoutMetrics.minCornerRadius
        borderRadiusSlider.isContinuous = true
        borderRadiusSlider.sendAction(on: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        borderRadiusSlider.target = self
        borderRadiusSlider.action = #selector(borderRadiusChanged(_:))
        borderRadiusSlider.translatesAutoresizingMaskIntoConstraints = false
        borderRadiusSlider.widthAnchor.constraint(equalToConstant: Metrics.sliderWidth).isActive = true

        borderRadiusValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        borderRadiusValueLabel.textColor = .secondaryLabelColor
        borderRadiusValueLabel.alignment = .right
        borderRadiusValueLabel.translatesAutoresizingMaskIntoConstraints = false
        borderRadiusValueLabel.widthAnchor.constraint(equalToConstant: Metrics.valueWidth).isActive = true

        resetRadiusButton.target = self
        resetRadiusButton.action = #selector(resetRadius(_:))
        resetRadiusButton.bezelStyle = .rounded
        resetRadiusButton.controlSize = .small
    }

    private func makeThemeControl() -> NSView {
        let swatchRow = NSStackView(views: themeButtons)
        swatchRow.orientation = .horizontal
        swatchRow.alignment = .centerY
        swatchRow.spacing = 14

        let stack = NSStackView(views: [swatchRow, resetThemeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        return stack
    }

    private func makeFontControl() -> NSView {
        let stack = NSStackView(views: [fontPopup, resetFontButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        return stack
    }

    private func makeAppIconControl() -> NSView {
        let stack = NSStackView(views: [iconStatusLabel, applyIconButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        return stack
    }

    private func makeFontSizeControl() -> NSView {
        let sliderGroup = NSStackView(views: [fontSizeSlider, fontSizeDetailLabel])
        sliderGroup.orientation = .horizontal
        sliderGroup.alignment = .centerY
        sliderGroup.spacing = Metrics.sliderValueSpacing
        sliderGroup.translatesAutoresizingMaskIntoConstraints = false
        sliderGroup.widthAnchor.constraint(equalToConstant: Metrics.sliderGroupWidth).isActive = true

        let stack = NSStackView(views: [sliderGroup, resetFontSizeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        return stack
    }

    private func makeBorderRadiusControl() -> NSView {
        let sliderGroup = NSStackView(views: [borderRadiusSlider, borderRadiusValueLabel])
        sliderGroup.orientation = .horizontal
        sliderGroup.alignment = .centerY
        sliderGroup.spacing = Metrics.sliderValueSpacing
        sliderGroup.translatesAutoresizingMaskIntoConstraints = false
        sliderGroup.widthAnchor.constraint(equalToConstant: Metrics.sliderGroupWidth).isActive = true

        let stack = NSStackView(views: [sliderGroup, resetRadiusButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        return stack
    }

    private func makeFormRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: Metrics.labelWidth).isActive = true

        let controlContainer = NSView()
        controlContainer.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        controlContainer.heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        controlContainer.addSubview(control)

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: controlContainer.leadingAnchor),
            control.centerYAnchor.constraint(equalTo: controlContainer.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: controlContainer.topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo: controlContainer.bottomAnchor),
        ])

        let row = NSStackView(views: [label, controlContainer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        return row
    }

    private func applyPreferencesToControls() {
        isUpdatingControls = true
        defer { isUpdatingControls = false }

        if !isApplyingPrimaryIconChange {
            currentAppliedIconTheme = PrimaryAppIconRelaunchController.shared.currentTheme()
        }

        let selectedTheme = BuiltInTheme.nearest(to: preferences.themeColor)
        for (index, button) in themeButtons.enumerated() {
            button.isSelected = BuiltInTheme.allCases[index] == selectedTheme
        }

        if let index = FontStylePreset.allCases.firstIndex(of: preferences.fontStyle) {
            fontPopup.selectItem(at: index)
        }

        let fontSize = LayoutMetrics.nearestFontSizeOption(to: preferences.fontSize)
        let fontSizeIndex = LayoutMetrics.fontSizeOptions.firstIndex(of: fontSize) ?? LayoutMetrics.defaultFontSizeIndex
        fontSizeSlider.doubleValue = Double(fontSizeIndex)
        fontSizeDetailLabel.stringValue = "\(Int(fontSize)) pt"

        borderRadiusSlider.maxValue = preferences.maximumCornerRadius
        borderRadiusSlider.doubleValue = min(preferences.cornerRadius, preferences.maximumCornerRadius)
        borderRadiusValueLabel.stringValue = "\(Int(round(borderRadiusSlider.doubleValue))) px"
        updateAppIconControls()
    }

    private func commitPreferenceChange(_ mutation: (inout AppPreferences) -> Void) {
        var updated = preferences
        mutation(&updated)
        preferences = updated
        applyPreferencesToControls()
        onPreferencesChange?(updated)
    }

    @objc private func themePresetSelected(_ sender: ThemePresetButton) {
        guard !isUpdatingControls else { return }
        guard BuiltInTheme.allCases.indices.contains(sender.tag) else { return }
        let theme = BuiltInTheme.allCases[sender.tag]
        commitPreferenceChange { updated in
            updated.themeColor = theme.color
        }
    }

    @objc private func resetThemeColor(_ sender: NSButton) {
        guard !isUpdatingControls else { return }
        commitPreferenceChange { updated in
            updated.themeColor = BuiltInTheme.theme1.color
        }
    }

    @objc private func fontChanged(_ sender: NSPopUpButton) {
        guard !isUpdatingControls else { return }
        guard FontStylePreset.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        commitPreferenceChange { updated in
            updated.fontStyle = FontStylePreset.allCases[sender.indexOfSelectedItem]
        }
    }

    @objc private func resetFont(_ sender: NSButton) {
        guard !isUpdatingControls else { return }
        commitPreferenceChange { updated in
            updated.fontStyle = .system
        }
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) {
        guard !isUpdatingControls else { return }
        let index = Int(round(sender.doubleValue))
        guard LayoutMetrics.fontSizeOptions.indices.contains(index) else { return }
        let snappedValue = Double(index)
        if sender.doubleValue != snappedValue {
            sender.doubleValue = snappedValue
        }
        commitPreferenceChange { updated in
            updated.fontSize = LayoutMetrics.fontSizeOptions[index]
        }
    }

    @objc private func resetFontSize(_ sender: NSButton) {
        guard !isUpdatingControls else { return }
        commitPreferenceChange { updated in
            updated.fontSize = LayoutMetrics.defaultFontSize
        }
    }

    @objc private func borderRadiusChanged(_ sender: NSSlider) {
        guard !isUpdatingControls else { return }
        commitPreferenceChange { updated in
            updated.cornerRadius = sender.doubleValue
        }
    }

    @objc private func resetRadius(_ sender: NSButton) {
        guard !isUpdatingControls else { return }
        commitPreferenceChange { updated in
            updated.cornerRadius = 10
        }
    }

    @objc private func applyIconAndRelaunch(_ sender: NSButton) {
        guard !isApplyingPrimaryIconChange else { return }
        let controller = PrimaryAppIconRelaunchController.shared
        guard controller.canApplyIconChanges() else {
            presentIconApplyError(message: "App icon rebuilding is only available from the local project checkout.")
            return
        }

        isApplyingPrimaryIconChange = true
        updateAppIconControls()

        do {
            try controller.applyAndRelaunch(theme: selectedTheme)
        } catch {
            isApplyingPrimaryIconChange = false
            updateAppIconControls()
            presentIconApplyError(message: error.localizedDescription)
        }
    }

    private var selectedTheme: BuiltInTheme {
        BuiltInTheme.nearest(to: preferences.themeColor)
    }

    private func updateAppIconControls() {
        let controller = PrimaryAppIconRelaunchController.shared
        guard controller.canApplyIconChanges() else {
            iconStatusLabel.stringValue = "Local build only."
            applyIconButton.title = "Apply & Relaunch"
            applyIconButton.isEnabled = false
            return
        }

        let themeMatchesIcon = selectedTheme == currentAppliedIconTheme
        if isApplyingPrimaryIconChange {
            iconStatusLabel.stringValue = "Building, then relaunching…"
            applyIconButton.title = "Rebuilding…"
            applyIconButton.isEnabled = false
            return
        }

        iconStatusLabel.stringValue = themeMatchesIcon ? "Icon matches this theme." : "Relaunch to apply current theme."
        applyIconButton.title = themeMatchesIcon ? "Icon Is Current" : "Apply & Relaunch"
        applyIconButton.isEnabled = !themeMatchesIcon
    }

    private func presentIconApplyError(message: String) {
        guard isViewLoaded else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t update the app icon"
        alert.informativeText = message
        if let window = view.window ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}

private final class ThemePresetButton: NSButton {
    private let outerCircle = NSView()
    private let innerCircle = NSView()

    var isSelected = false {
        didSet { updateAppearance() }
    }

    init(color: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        setButtonType(.momentaryChange)
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        outerCircle.wantsLayer = true
        outerCircle.translatesAutoresizingMaskIntoConstraints = false
        outerCircle.layer?.backgroundColor = color.cgColor
        outerCircle.layer?.cornerRadius = 14
        addSubview(outerCircle)

        innerCircle.wantsLayer = true
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.layer?.backgroundColor = NSColor.white.cgColor
        innerCircle.layer?.cornerRadius = 6.5
        addSubview(innerCircle)

        NSLayoutConstraint.activate([
            outerCircle.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerCircle.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerCircle.topAnchor.constraint(equalTo: topAnchor),
            outerCircle.bottomAnchor.constraint(equalTo: bottomAnchor),

            innerCircle.centerXAnchor.constraint(equalTo: centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 13),
            innerCircle.heightAnchor.constraint(equalToConstant: 13),
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

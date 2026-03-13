import AppKit

final class SettingsViewController: NSViewController {
    private enum Metrics {
        static let outerPadding = NSEdgeInsets(top: 20, left: 34, bottom: 28, right: 34)
        static let titleTopInset: CGFloat = 10
        static let tabTopInset: CGFloat = 36
        static let dividerTopInset: CGFloat = 104
        static let contentTopInset: CGFloat = 36

        static let tabWidth: CGFloat = 70
        static let tabHeight: CGFloat = 58

        static let labelWidth: CGFloat = 104
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
        static let shortcutsColumnWidth: CGFloat = 220
        static let shortcutsColumnGap: CGFloat = 16
    }

    private enum SettingsTab: CaseIterable, Hashable {
        case appearance
        case shortcuts
        case statistics

        var title: String {
            switch self {
            case .appearance: return "Theme"
            case .shortcuts: return "Shortcuts"
            case .statistics: return "Statistics"
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "paintpalette"
            case .shortcuts: return "command"
            case .statistics: return "chart.bar"
            }
        }
    }

    var onPreferencesChange: ((AppPreferences) -> Void)?

    private var preferences: AppPreferences
    private var isUpdatingControls = false
    private var selectedTab: SettingsTab = .appearance

    private let titleLabel = NSTextField(labelWithString: "Settings")
    private let tabStack = NSStackView()
    private let divider = NSBox()
    private let contentHostView = NSView()

    private var tabButtons: [SettingsTab: SettingsTabButton] = [:]
    private var pageViews: [SettingsTab: NSView] = [:]

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

        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        contentHostView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleLabel)
        root.addSubview(tabStack)
        root.addSubview(divider)
        root.addSubview(contentHostView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.titleTopInset),
            titleLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            tabStack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.tabTopInset),
            tabStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            divider.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.dividerTopInset),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            contentHostView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: Metrics.contentTopInset),
            contentHostView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.outerPadding.left),
            contentHostView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.outerPadding.right),
            contentHostView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Metrics.outerPadding.bottom),
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTabButtons()
        configureControls()
        buildPages()
        selectTab(.appearance)
        applyPreferencesToControls()
    }

    func updatePreferences(_ preferences: AppPreferences) {
        guard self.preferences != preferences else { return }
        self.preferences = preferences
        guard isViewLoaded else { return }
        applyPreferencesToControls()
    }

    private func configureTabButtons() {
        tabStack.arrangedSubviews.forEach {
            tabStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        SettingsTab.allCases.forEach { tab in
            let button = SettingsTabButton(title: tab.title, symbolName: tab.symbolName)
            button.target = self
            button.action = #selector(tabSelected(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Metrics.tabWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: Metrics.tabHeight).isActive = true
            button.tag = SettingsTab.allCases.firstIndex(of: tab) ?? 0
            tabButtons[tab] = button
            tabStack.addArrangedSubview(button)
        }
    }

    private func configureControls() {
        configureThemeButtons()
        configureIconApplyControls()
        configureFontPopup()
        configureFontSizeSlider()
        configureBorderRadiusSlider()
    }

    private func buildPages() {
        pageViews = [
            .appearance: makeAppearancePage(),
            .shortcuts: makeShortcutsPage(),
            .statistics: makeStatisticsPage(),
        ]
    }

    @objc private func tabSelected(_ sender: NSButton) {
        guard SettingsTab.allCases.indices.contains(sender.tag) else { return }
        selectTab(SettingsTab.allCases[sender.tag])
    }

    private func selectTab(_ tab: SettingsTab) {
        selectedTab = tab
        tabButtons.forEach { key, button in
            button.isSelected = key == tab
        }

        contentHostView.subviews.forEach { $0.removeFromSuperview() }
        guard let pageView = pageViews[tab] else { return }
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: contentHostView.topAnchor),
            pageView.bottomAnchor.constraint(lessThanOrEqualTo: contentHostView.bottomAnchor),
        ])
    }

    private func makeAppearancePage() -> NSView {
        let contentStack = NSStackView(views: [
            makeFormRow(title: "Background", control: makeThemeControl()),
            makeFormRow(title: "App Icon", control: makeAppIconControl()),
            makeFormRow(title: "Font", control: makeFontControl()),
            makeFormRow(title: "Font Size", control: makeFontSizeControl()),
            makeFormRow(title: "Radius", control: makeBorderRadiusControl()),
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = Metrics.rowSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: container.topAnchor),
            contentStack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeShortcutsPage() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        [
            ("New row below", ["return"]),
            ("Complete selected", ["command", "return"]),
            ("Delete selected", ["command", "delete"]),
            ("Move selection", ["up/down"]),
            ("Expand selection", ["shift", "up/down"]),
            ("Jump to top or bottom", ["command", "up/down"]),
            ("Select to top or bottom", ["command", "shift", "up/down"]),
            ("Select all", ["command", "A"]),
            ("Open theme", ["command", ","]),
            ("Reset window size", ["command", "0"]),
            ("Snap window", ["control", "option", "arrow"]),
            ("Fullscreen", ["control", "command", "F"]),
        ].forEach { label, shortcut in
            stack.addArrangedSubview(makeShortcutRow(label: label, shortcut: shortcut))
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeStatisticsPage() -> NSView {
        let label = NSTextField(labelWithString: "stats page here")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])

        return container
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
        configureResetButton(resetThemeButton)
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
        configureResetButton(resetFontButton)
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

        configureValueLabel(fontSizeDetailLabel)

        resetFontSizeButton.target = self
        resetFontSizeButton.action = #selector(resetFontSize(_:))
        configureResetButton(resetFontSizeButton)
    }

    private func configureBorderRadiusSlider() {
        borderRadiusSlider.minValue = LayoutMetrics.minCornerRadius
        borderRadiusSlider.isContinuous = true
        borderRadiusSlider.sendAction(on: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        borderRadiusSlider.target = self
        borderRadiusSlider.action = #selector(borderRadiusChanged(_:))
        borderRadiusSlider.translatesAutoresizingMaskIntoConstraints = false
        borderRadiusSlider.widthAnchor.constraint(equalToConstant: Metrics.sliderWidth).isActive = true

        configureValueLabel(borderRadiusValueLabel)

        resetRadiusButton.target = self
        resetRadiusButton.action = #selector(resetRadius(_:))
        configureResetButton(resetRadiusButton)
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: Metrics.valueWidth).isActive = true
    }

    private func configureResetButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
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

    private func makeShortcutRow(label: String, shortcut: [String]) -> NSView {
        let descriptionLabel = NSTextField(labelWithString: label)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .right
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth).isActive = true

        let keysRow = NSStackView(views: shortcut.map(makeKeycap))
        keysRow.orientation = .horizontal
        keysRow.alignment = .centerY
        keysRow.spacing = 2
        keysRow.translatesAutoresizingMaskIntoConstraints = false

        let keysContainer = NSView()
        keysContainer.translatesAutoresizingMaskIntoConstraints = false
        keysContainer.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth).isActive = true
        keysContainer.addSubview(keysRow)

        NSLayoutConstraint.activate([
            keysRow.leadingAnchor.constraint(equalTo: keysContainer.leadingAnchor),
            keysRow.centerYAnchor.constraint(equalTo: keysContainer.centerYAnchor),
            keysRow.topAnchor.constraint(greaterThanOrEqualTo: keysContainer.topAnchor),
            keysRow.bottomAnchor.constraint(lessThanOrEqualTo: keysContainer.bottomAnchor),
        ])

        let row = NSStackView(views: [descriptionLabel, keysContainer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Metrics.shortcutsColumnGap
        return row
    }

    private func makeKeycap(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: keycapDisplayText(for: text))
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = NSColor(
            calibratedRed: 128.0 / 255.0,
            green: 128.0 / 255.0,
            blue: 128.0 / 255.0,
            alpha: 1.0
        )

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.949, alpha: 1.0).cgColor
        container.layer?.cornerRadius = 3
        container.translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        return container
    }

    private func keycapDisplayText(for text: String) -> String {
        switch text.lowercased() {
        case "command":
            return "⌘"
        case "control":
            return "⌃"
        case "option":
            return "⌥"
        case "shift":
            return "⇧"
        case "return":
            return "↩"
        case "delete":
            return "⌫"
        case "up/down":
            return "↑  ↓"
        case "arrow":
            return "←  ↑  ↓  →"
        default:
            return text
        }
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
            let process = try controller.iconApplyProcess(for: selectedTheme)
            try process.run()

            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                guard process.terminationStatus != 0 else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isApplyingPrimaryIconChange = false
                    self.updateAppIconControls()
                    self.presentIconApplyError(message: "Failed to apply icon. Please try again.")
                }
            }
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

private final class SettingsTabButton: NSButton {
    private let container = NSView()
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

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

    private func updateAppearance() {
        let tint = isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor
        container.layer?.backgroundColor = isSelected
            ? NSColor.black.withAlphaComponent(0.05).cgColor
            : NSColor.clear.cgColor
        imageView.contentTintColor = tint
        titleField.textColor = tint
    }
}

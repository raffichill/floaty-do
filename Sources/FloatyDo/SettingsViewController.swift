import AppKit

final class SettingsViewController: NSViewController {
    private enum Metrics {
        static let outerPadding = NSEdgeInsets(top: 20, left: 34, bottom: 56, right: 34)
        static let titleTopInset: CGFloat = 10
        static let tabTopInset: CGFloat = 36
        static let dividerTopInset: CGFloat = 104
        static let contentTopInset: CGFloat = 36

        static let tabWidth: CGFloat = 70
        static let tabHeight: CGFloat = 58

        static let labelWidth: CGFloat = 104
        static let rowHeight: CGFloat = 58
        static let rowSpacing: CGFloat = 2
        static let actionSpacing: CGFloat = 12
        static let actionButtonWidth: CGFloat = 88
        static let themeSwatchButtonCount: CGFloat = CGFloat(BuiltInTheme.allCases.count)
        static let themeSwatchButtonSize: CGFloat = 24
        static let themeSwatchSpacing: CGFloat = 12
        static let themeSwatchContainerHeight: CGFloat = 42
        static let themeSwatchInset: CGFloat = (themeSwatchContainerHeight - themeSwatchButtonSize) / 2
        static let themeSwatchContainerWidth: CGFloat =
            (themeSwatchButtonCount * themeSwatchButtonSize) +
            ((themeSwatchButtonCount - 1) * themeSwatchSpacing) +
            (themeSwatchInset * 2)
        static let valueWidth: CGFloat = 44
        static let sliderValueSpacing: CGFloat = 8
        static let controlWidth: CGFloat = themeSwatchContainerWidth
        static let primaryControlWidth: CGFloat = controlWidth - actionButtonWidth - actionSpacing
        static let sliderGroupWidth: CGFloat = primaryControlWidth
        static let sliderWidth: CGFloat = sliderGroupWidth - valueWidth - sliderValueSpacing
        static let popupWidth: CGFloat = primaryControlWidth
        static let iconStatusWidth: CGFloat = primaryControlWidth
        static let transparencyLabelWidth: CGFloat = 52
        static let transparencyItemSpacing: CGFloat = 12
        static let shortcutsColumnWidth: CGFloat = 220
        static let shortcutsColumnGap: CGFloat = 16
        static let shortcutsRowSpacing: CGFloat = 14
    }

    private enum AnimationMetrics {
        static let resizeDuration: TimeInterval = 0.18
        static let crossfadeDuration: TimeInterval = 0.14
    }

    static let preferredWindowWidth: CGFloat = 680

    private final class SettingsPageContainerView: NSView {
        var allowsHitTesting = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard allowsHitTesting, alphaValue > 0.01, !isHidden else { return nil }
            return super.hitTest(point)
        }
    }

    private struct SettingsPage {
        let container: SettingsPageContainerView
        let contentHeight: CGFloat
    }

    private enum SettingsTab: CaseIterable, Hashable {
        case appearance
        case shortcuts
        case about

        var title: String {
            switch self {
            case .appearance: return "Theme"
            case .shortcuts: return "Shortcuts"
            case .about: return "About"
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "paintpalette"
            case .shortcuts: return "command"
            case .about: return "info.circle"
            }
        }
    }

    var onPreferencesChange: ((AppPreferences) -> Void)?
    var onPreferredWindowHeightChange: ((CGFloat, Bool) -> Void)?

    private var preferences: AppPreferences
    private var isUpdatingControls = false
    private var selectedTab: SettingsTab = .appearance
    private var displayedTab: SettingsTab?
    private var transitionGeneration = 0

    private let titleLabel = NSTextField(labelWithString: "Settings")
    private let tabStack = NSStackView()
    private let headerView = NSView()
    private let divider = NSView()
    private let contentHostView = NSView()
    private var contentHostHeightConstraint: NSLayoutConstraint?
    private var primaryLabels: [NSTextField] = []
    private var secondaryLabels: [NSTextField] = []
    private var keycapLabels: [NSTextField] = []
    private var keycapBackgroundViews: [NSView] = []

    private var tabButtons: [SettingsTab: SettingsTabButton] = [:]
    private var pages: [SettingsTab: SettingsPage] = [:]

    private let iconStatusLabel = NSTextField(labelWithString: "")
    private let applyIconButton = NSButton(title: "Relaunch", target: nil, action: nil)
    private var themeButtons: [ThemePresetButton] = []
    private let themeSwatchContainer = NSView()
    private let blurToggle = NSSwitch()
    private let transparencyLabel = NSTextField(labelWithString: "Opacity")
    private let transparencySlider = NSSlider()
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

    private var themeableButtons: [NSButton] {
        [
            applyIconButton,
            resetFontButton,
            resetFontSizeButton,
            resetRadiusButton,
        ]
    }

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
        root.layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center
        primaryLabels.append(titleLabel)

        headerView.translatesAutoresizingMaskIntoConstraints = false

        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 4
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.wantsLayer = true

        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        contentHostView.wantsLayer = true
        contentHostView.layer?.masksToBounds = true

        root.addSubview(headerView)
        root.addSubview(divider)
        root.addSubview(contentHostView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(tabStack)

        let contentHostHeightConstraint = contentHostView.heightAnchor.constraint(equalToConstant: 0)
        self.contentHostHeightConstraint = contentHostHeightConstraint

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: root.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Metrics.dividerTopInset),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: Metrics.titleTopInset),
            titleLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            tabStack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: Metrics.tabTopInset),
            tabStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            divider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            contentHostView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: Metrics.contentTopInset),
            contentHostView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.outerPadding.left),
            contentHostView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.outerPadding.right),
            contentHostView.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -Metrics.outerPadding.bottom),
            contentHostHeightConstraint,
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

    override func viewDidAppear() {
        super.viewDidAppear()
        reportPreferredWindowHeight(animated: false)
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
        configureBlurToggle()
        configureTransparencySlider()
        configureIconApplyControls()
        configureFontPopup()
        configureFontSizeSlider()
        configureBorderRadiusSlider()
    }

    private func buildPages() {
        let pageContentViews: [SettingsTab: NSView] = [
            .appearance: makeAppearancePage(),
            .shortcuts: makeShortcutsPage(),
            .about: makeAboutPage(),
        ]
        var pageContainers: [SettingsTab: SettingsPageContainerView] = [:]

        pages = [:]
        contentHostView.subviews.forEach { $0.removeFromSuperview() }

        for tab in SettingsTab.allCases {
            guard let contentView = pageContentViews[tab] else { continue }
            let pageView = SettingsPageContainerView()
            pageView.translatesAutoresizingMaskIntoConstraints = false
            pageView.wantsLayer = true
            pageView.alphaValue = 0
            pageView.allowsHitTesting = false
            pageView.addSubview(contentView)
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentHostView.addSubview(pageView)
            pageContainers[tab] = pageView
            NSLayoutConstraint.activate([
                pageView.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
                pageView.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
                pageView.topAnchor.constraint(equalTo: contentHostView.topAnchor),

                contentView.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
                contentView.trailingAnchor.constraint(equalTo: pageView.trailingAnchor),
                contentView.topAnchor.constraint(equalTo: pageView.topAnchor),
                contentView.bottomAnchor.constraint(equalTo: pageView.bottomAnchor),
            ])
        }

        view.layoutSubtreeIfNeeded()

        for tab in SettingsTab.allCases {
            guard let pageView = pageContainers[tab] else { continue }

            let contentHeight = ceil(pageView.fittingSize.height)
            let heightConstraint = pageView.heightAnchor.constraint(equalToConstant: contentHeight)
            heightConstraint.isActive = true
            pages[tab] = SettingsPage(container: pageView, contentHeight: contentHeight)
        }

        view.layoutSubtreeIfNeeded()
    }

    @objc private func tabSelected(_ sender: NSButton) {
        guard SettingsTab.allCases.indices.contains(sender.tag) else { return }
        selectTab(SettingsTab.allCases[sender.tag])
    }

    private func selectTab(_ tab: SettingsTab) {
        let outgoingTab = displayedTab ?? tab
        selectedTab = tab
        tabButtons.forEach { key, button in
            button.isSelected = key == tab
        }

        let targetContentHeight = measuredContentHeight(for: tab)
        let shouldAnimate = view.window?.isVisible == true && displayedTab != nil && outgoingTab != tab

        transitionGeneration += 1
        let transitionID = transitionGeneration

        guard shouldAnimate else {
            applyVisiblePage(tab)
            transitionDisplayedContentHeight(to: targetContentHeight, animated: false)
            reportPreferredWindowHeight(forContentHeight: targetContentHeight, animated: false)
            return
        }

        preparePagesForTransition(from: outgoingTab, to: tab)
        let currentContentHeight = contentHostHeightConstraint?.constant ?? measuredContentHeight(for: outgoingTab)
        let grows = targetContentHeight > currentContentHeight + 0.5

        reportPreferredWindowHeight(forContentHeight: targetContentHeight, animated: true)

        if grows {
            transitionDisplayedContentHeight(to: targetContentHeight, animated: true) { [weak self] in
                self?.crossfadeIfCurrent(from: outgoingTab, to: tab, transitionID: transitionID)
            }
            return
        }

        crossfadePages(from: outgoingTab, to: tab, transitionID: transitionID)
        transitionDisplayedContentHeight(to: targetContentHeight, animated: true)
    }

    private func makeAppearancePage() -> NSView {
        let labelsStack = NSStackView(views: [
            makeAppearanceLabelRow(title: "Background"),
            makeAppearanceLabelRow(title: "Transparent"),
            makeAppearanceLabelRow(title: "Font"),
            makeAppearanceLabelRow(title: "Font Size"),
            makeAppearanceLabelRow(title: "Radius"),
            makeAppearanceLabelRow(title: "App Icon"),
        ])
        labelsStack.orientation = .vertical
        labelsStack.alignment = .trailing
        labelsStack.spacing = Metrics.rowSpacing
        labelsStack.translatesAutoresizingMaskIntoConstraints = false

        let controlsStack = NSStackView(views: [
            wrapAppearanceControl(makeThemeControl()),
            wrapAppearanceControl(makeTransparencyAndBlurControl()),
            wrapAppearanceControl(makeFontControl()),
            wrapAppearanceControl(makeFontSizeControl()),
            wrapAppearanceControl(makeBorderRadiusControl()),
            wrapAppearanceControl(makeAppIconControl()),
        ])
        controlsStack.orientation = .vertical
        controlsStack.alignment = .centerX
        controlsStack.spacing = Metrics.rowSpacing
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(labelsStack)
        content.addSubview(controlsStack)

        NSLayoutConstraint.activate([
            controlsStack.topAnchor.constraint(equalTo: content.topAnchor),
            controlsStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            controlsStack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
            controlsStack.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            labelsStack.topAnchor.constraint(equalTo: controlsStack.topAnchor),
            labelsStack.trailingAnchor.constraint(equalTo: controlsStack.leadingAnchor, constant: -18),
            labelsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            labelsStack.bottomAnchor.constraint(equalTo: controlsStack.bottomAnchor),
        ])

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeShortcutsPage() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Metrics.shortcutsRowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        [
            ("New row below", ["return"]),
            ("Complete selected", ["command", "return"]),
            ("Delete selected", ["command", "delete"]),
            ("Show list", ["command", "1"]),
            ("Show archive", ["command", "2"]),
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
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeAboutPage() -> NSView {
        let label = NSTextField(wrappingLabelWithString: "paragraph goes here")
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 420
        secondaryLabels.append(label)

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        return container
    }

    private func configureThemeButtons() {
        themeButtons = BuiltInTheme.allCases.enumerated().map { index, theme in
            let button = ThemePresetButton(
                color: theme.color.nsColor,
                size: Metrics.themeSwatchButtonSize
            )
            button.tag = index
            button.target = self
            button.action = #selector(themePresetSelected(_:))
            return button
        }

        themeSwatchContainer.wantsLayer = true
        themeSwatchContainer.translatesAutoresizingMaskIntoConstraints = false
        themeSwatchContainer.widthAnchor.constraint(equalToConstant: Metrics.themeSwatchContainerWidth).isActive = true
        themeSwatchContainer.heightAnchor.constraint(equalToConstant: Metrics.themeSwatchContainerHeight).isActive = true
    }

    private func configureIconApplyControls() {
        iconStatusLabel.font = .systemFont(ofSize: 11)
        iconStatusLabel.alignment = .left
        iconStatusLabel.lineBreakMode = .byTruncatingTail
        iconStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        iconStatusLabel.widthAnchor.constraint(equalToConstant: Metrics.iconStatusWidth).isActive = true
        secondaryLabels.append(iconStatusLabel)

        applyIconButton.target = self
        applyIconButton.action = #selector(applyIconAndRelaunch(_:))
        configureResetButton(applyIconButton)
    }

    private func configureTransparencySlider() {
        transparencySlider.minValue = LayoutMetrics.minWindowOpacity * 100.0
        transparencySlider.maxValue = 100.0
        transparencySlider.isContinuous = true
        transparencySlider.sendAction(on: [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        transparencySlider.target = self
        transparencySlider.action = #selector(transparencyChanged(_:))
        transparencySlider.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureBlurToggle() {
        blurToggle.target = self
        blurToggle.action = #selector(blurToggled(_:))
        blurToggle.controlSize = .small
        blurToggle.translatesAutoresizingMaskIntoConstraints = false

        transparencyLabel.font = .systemFont(ofSize: 12, weight: .regular)
        transparencyLabel.alignment = .right
        transparencyLabel.translatesAutoresizingMaskIntoConstraints = false
        transparencyLabel.setContentHuggingPriority(.required, for: .horizontal)
        transparencyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        transparencyLabel.widthAnchor.constraint(equalToConstant: Metrics.transparencyLabelWidth).isActive = true
        primaryLabels.append(transparencyLabel)
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
        secondaryLabels.append(fontSizeDetailLabel)

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
        secondaryLabels.append(borderRadiusValueLabel)

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
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth).isActive = true
    }

    private func makeThemeControl() -> NSView {
        let swatchRow = NSStackView(views: themeButtons)
        swatchRow.orientation = .horizontal
        swatchRow.alignment = .centerY
        swatchRow.spacing = Metrics.themeSwatchSpacing
        swatchRow.translatesAutoresizingMaskIntoConstraints = false

        themeSwatchContainer.subviews.forEach { $0.removeFromSuperview() }
        themeSwatchContainer.addSubview(swatchRow)
        NSLayoutConstraint.activate([
            swatchRow.leadingAnchor.constraint(equalTo: themeSwatchContainer.leadingAnchor, constant: Metrics.themeSwatchInset),
            swatchRow.trailingAnchor.constraint(equalTo: themeSwatchContainer.trailingAnchor, constant: -Metrics.themeSwatchInset),
            swatchRow.centerYAnchor.constraint(equalTo: themeSwatchContainer.centerYAnchor),
        ])

        return themeSwatchContainer
    }

    private func makeTransparencyAndBlurControl() -> NSView {
        let control = NSView()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        control.heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true

        blurToggle.translatesAutoresizingMaskIntoConstraints = false
        transparencyLabel.translatesAutoresizingMaskIntoConstraints = false
        transparencySlider.translatesAutoresizingMaskIntoConstraints = false
        control.addSubview(blurToggle)
        control.addSubview(transparencyLabel)
        control.addSubview(transparencySlider)

        NSLayoutConstraint.activate([
            blurToggle.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            blurToggle.centerYAnchor.constraint(equalTo: control.centerYAnchor),

            transparencyLabel.leadingAnchor.constraint(equalTo: blurToggle.trailingAnchor, constant: Metrics.transparencyItemSpacing),
            transparencyLabel.centerYAnchor.constraint(equalTo: control.centerYAnchor),

            transparencySlider.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            transparencySlider.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            transparencySlider.leadingAnchor.constraint(equalTo: transparencyLabel.trailingAnchor, constant: Metrics.transparencyItemSpacing),
        ])

        return control
    }

    private func makeFontControl() -> NSView {
        let stack = NSStackView(views: [fontPopup, resetFontButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.actionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        return stack
    }

    private func makeAppIconControl() -> NSView {
        let stack = NSStackView(views: [iconStatusLabel, applyIconButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.actionSpacing
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
        stack.spacing = Metrics.actionSpacing
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
        stack.spacing = Metrics.actionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        return stack
    }

    private func makeAppearanceLabelRow(title: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: Metrics.labelWidth).isActive = true
        primaryLabels.append(label)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        ])

        return container
    }

    private func wrapAppearanceControl(_ control: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: Metrics.controlWidth).isActive = true
        container.heightAnchor.constraint(equalToConstant: Metrics.rowHeight).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(control)

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
        ])

        return container
    }

    func preferredWindowHeight() -> CGFloat {
        loadViewIfNeeded()
        return totalWindowHeight(forContentHeight: measuredContentHeight(for: selectedTab))
    }

    private func reportPreferredWindowHeight(forContentHeight contentHeight: CGFloat? = nil, animated: Bool) {
        guard isViewLoaded else { return }
        let resolvedContentHeight = contentHeight ?? measuredContentHeight(for: selectedTab)
        onPreferredWindowHeightChange?(totalWindowHeight(forContentHeight: resolvedContentHeight), animated)
    }

    private func measuredContentHeight(for tab: SettingsTab) -> CGFloat {
        pages[tab]?.contentHeight ?? 0
    }

    private func totalWindowHeight(forContentHeight contentHeight: CGFloat) -> CGFloat {
        Metrics.dividerTopInset + 1 + Metrics.contentTopInset + contentHeight + Metrics.outerPadding.bottom
    }

    private func transitionDisplayedContentHeight(to targetHeight: CGFloat, animated: Bool, completion: (() -> Void)? = nil) {
        guard let contentHostHeightConstraint else { return }
        let currentHeight = contentHostHeightConstraint.constant

        guard abs(currentHeight - targetHeight) > 0.5 else {
            completion?()
            return
        }

        guard animated else {
            contentHostHeightConstraint.constant = targetHeight
            view.layoutSubtreeIfNeeded()
            completion?()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = AnimationMetrics.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            contentHostHeightConstraint.animator().constant = targetHeight
            view.layoutSubtreeIfNeeded()
        } completionHandler: {
            completion?()
        }
    }

    private func applyVisiblePage(_ tab: SettingsTab) {
        for (key, page) in pages {
            let isVisible = key == tab
            page.container.alphaValue = isVisible ? 1 : 0
            page.container.isHidden = false
            page.container.allowsHitTesting = isVisible
        }
        displayedTab = tab
    }

    private func preparePagesForTransition(from outgoingTab: SettingsTab, to incomingTab: SettingsTab) {
        for (key, page) in pages {
            page.container.layer?.removeAllAnimations()
            page.container.isHidden = false
            page.container.allowsHitTesting = false
            switch key {
            case outgoingTab:
                page.container.alphaValue = 1
            case incomingTab:
                page.container.alphaValue = 0
            default:
                page.container.alphaValue = 0
            }
        }
        displayedTab = outgoingTab
    }

    private func crossfadeIfCurrent(from outgoingTab: SettingsTab, to incomingTab: SettingsTab, transitionID: Int) {
        guard transitionGeneration == transitionID else { return }
        crossfadePages(from: outgoingTab, to: incomingTab, transitionID: transitionID)
    }

    private func crossfadePages(from outgoingTab: SettingsTab, to incomingTab: SettingsTab, transitionID: Int) {
        guard let outgoingPage = pages[outgoingTab],
              let incomingPage = pages[incomingTab] else {
            applyVisiblePage(incomingTab)
            return
        }

        outgoingPage.container.isHidden = false
        incomingPage.container.isHidden = false
        outgoingPage.container.allowsHitTesting = false
        incomingPage.container.allowsHitTesting = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = AnimationMetrics.crossfadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            outgoingPage.container.animator().alphaValue = 0
            incomingPage.container.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self, self.transitionGeneration == transitionID else { return }
            self.applyVisiblePage(incomingTab)
        }
    }

    private func makeShortcutRow(label: String, shortcut: [String]) -> NSView {
        let descriptionLabel = NSTextField(labelWithString: label)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.alignment = .right
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth).isActive = true
        secondaryLabels.append(descriptionLabel)

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
        keycapLabels.append(label)

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 3
        container.translatesAutoresizingMaskIntoConstraints = false
        keycapBackgroundViews.append(container)

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

        let selectedTheme = preferences.theme
        for (index, button) in themeButtons.enumerated() {
            button.isSelected = BuiltInTheme.allCases[index] == selectedTheme
        }

        let opacityControlsEnabled = preferences.blurEnabled
        let displayedTransparency = preferences.clampedWindowOpacity * 100.0
        blurToggle.state = preferences.blurEnabled ? .on : .off
        transparencySlider.doubleValue = displayedTransparency
        transparencySlider.isEnabled = opacityControlsEnabled

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
        applyThemeAppearance()
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
            updated.theme = theme
        }
    }

    @objc private func transparencyChanged(_ sender: NSSlider) {
        guard !isUpdatingControls else { return }
        let snappedValue = round(sender.doubleValue)
        if sender.doubleValue != snappedValue {
            sender.doubleValue = snappedValue
        }
        commitPreferenceChange { updated in
            updated.blurEnabled = true
            updated.windowOpacity = snappedValue / 100.0
        }
    }

    @objc private func blurToggled(_ sender: NSButton) {
        guard !isUpdatingControls else { return }
        commitPreferenceChange { updated in
            updated.blurEnabled = sender.state == .on
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
        guard selectedTheme.supportsPrimaryAppIcon else {
            presentIconApplyError(message: "This theme doesn’t have a matching app icon yet.")
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
        preferences.theme
    }

    private func updateAppIconControls() {
        let controller = PrimaryAppIconRelaunchController.shared
        guard controller.canApplyIconChanges() else {
            iconStatusLabel.stringValue = "Local build only."
            applyIconButton.title = "Relaunch"
            applyIconButton.isEnabled = false
            return
        }

        guard selectedTheme.supportsPrimaryAppIcon else {
            iconStatusLabel.stringValue = "No matching icon yet."
            applyIconButton.title = "Unavailable"
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
        applyIconButton.title = themeMatchesIcon ? "Current" : "Relaunch"
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

    private func applyThemeAppearance() {
        view.layer?.backgroundColor = NSColor.clear.cgColor
        divider.layer?.backgroundColor = preferences.subtleStrokeColor.cgColor
        themeSwatchContainer.layer?.backgroundColor = preferences.activeFillColor.cgColor
        themeSwatchContainer.layer?.cornerRadius = Metrics.themeSwatchContainerHeight / 2

        primaryLabels.forEach { $0.textColor = preferences.primaryTextColor }
        secondaryLabels.forEach { $0.textColor = preferences.secondaryTextColor }
        keycapLabels.forEach { $0.textColor = preferences.secondaryTextColor }
        keycapBackgroundViews.forEach {
            $0.layer?.backgroundColor = preferences.activeFillColor.cgColor
        }
        themeableButtons.forEach { applyThemeStyle(to: $0) }
        applyThemeStyle(to: fontPopup)

        tabButtons.values.forEach {
            $0.applyTheme(
                selectedTint: preferences.primaryTextColor,
                inactiveTint: preferences.secondaryTextColor,
                selectedBackground: preferences.activeFillColor
            )
        }
    }

    private func applyThemeStyle(to button: NSButton) {
        let titleColor = button.isEnabled
            ? preferences.primaryTextColor
            : preferences.primaryTextColor.withAlphaComponent(0.42)
        let fillColor = button.isEnabled
            ? preferences.activeFillColor
            : preferences.activeFillColor.withAlphaComponent(max(0.12, preferences.activeFillColor.alphaComponent * 0.48))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: titleColor,
                .font: button.font ?? .systemFont(ofSize: 11, weight: .medium),
                .paragraphStyle: paragraphStyle,
            ]
        )
        button.contentTintColor = titleColor
        button.bezelColor = fillColor
    }

    private func applyThemeStyle(to popup: NSPopUpButton) {
        let titleColor = popup.isEnabled
            ? preferences.primaryTextColor
            : preferences.primaryTextColor.withAlphaComponent(0.42)
        let fillColor = popup.isEnabled
            ? preferences.activeFillColor
            : preferences.activeFillColor.withAlphaComponent(max(0.12, preferences.activeFillColor.alphaComponent * 0.48))
        let font = popup.font ?? .systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: titleColor,
            .font: font,
        ]

        popup.contentTintColor = titleColor
        popup.bezelColor = fillColor
        popup.itemArray.forEach { item in
            item.attributedTitle = NSAttributedString(string: item.title, attributes: attributes)
        }

        let selectedTitle = popup.titleOfSelectedItem ?? ""
        popup.attributedTitle = NSAttributedString(string: selectedTitle, attributes: attributes)
    }
}

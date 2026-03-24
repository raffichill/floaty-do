import AppKit

final class SettingsViewController: NSViewController, NSPopoverDelegate {
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
        static let themeSwatchInset: CGFloat =
            (themeSwatchContainerHeight - themeSwatchButtonSize) / 2
        static let themeSwatchContainerWidth: CGFloat =
            (themeSwatchButtonCount * themeSwatchButtonSize)
            + ((themeSwatchButtonCount - 1) * themeSwatchSpacing) + (themeSwatchInset * 2)
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
        static let shortcutsRowSpacing: CGFloat = 10
        static let shortcutsSectionGap: CGFloat = 25
        static let aboutBlockWidth: CGFloat = 400
        static let opacityStops: [Double] = [0.67, 0.78, 0.89, 1.0]
    }

    private enum AnimationMetrics {
        static let resizeDuration: TimeInterval = 0.18
        static let crossfadeDuration: TimeInterval = 0.14
        static let growCrossfadeDelay: TimeInterval = 0.04
    }

    static let preferredWindowWidth: CGFloat = 680

    private final class SettingsPageContainerView: NSView {
        var allowsHitTesting = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard allowsHitTesting, alphaValue > 0.01, !isHidden else { return nil }
            return super.hitTest(point)
        }
    }

    private final class HoverAwareTextView: NSTextView {
        var onActivatedLink: ((String) -> Void)?
        var onHoveredLinkChange: ((String?) -> Void)?

        private var hoverTrackingArea: NSTrackingArea?
        private var hoveredLink: String?

        override var acceptsFirstResponder: Bool { false }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTrackingArea {
                removeTrackingArea(hoverTrackingArea)
            }

            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            hoverTrackingArea = trackingArea
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            updateHoveredLink(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            updateHoveredLink(at: convert(event.locationInWindow, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            updateHoveredLink(at: convert(event.locationInWindow, from: nil))
            if let hoveredLink {
                onActivatedLink?(hoveredLink)
                return
            }
            super.mouseUp(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            applyHoveredLink(nil)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }

        private func updateHoveredLink(at point: NSPoint) {
            guard let textContainer, let layoutManager, let textStorage else {
                applyHoveredLink(nil)
                return
            }

            let containerOrigin = textContainerOrigin
            let containerPoint = NSPoint(
                x: point.x - containerOrigin.x, y: point.y - containerOrigin.y)
            guard containerPoint.x >= 0, containerPoint.y >= 0 else {
                applyHoveredLink(nil)
                return
            }

            let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
            let glyphRange = NSRange(location: glyphIndex, length: 1)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            guard glyphRect.contains(containerPoint) else {
                applyHoveredLink(nil)
                return
            }

            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            guard characterIndex < textStorage.length else {
                applyHoveredLink(nil)
                return
            }

            let linkAttribute = textStorage.attribute(
                .link, at: characterIndex, effectiveRange: nil)
            let linkString = (linkAttribute as? URL)?.absoluteString ?? (linkAttribute as? String)
            applyHoveredLink(linkString)
        }

        private func applyHoveredLink(_ link: String?) {
            if link != nil {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }

            guard hoveredLink != link else { return }
            hoveredLink = link
            onHoveredLinkChange?(link)
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
    private var hoveredAboutLink: String?
    private let titleLabel = NSTextField(labelWithString: "FloatyDo")
    private let tabStack = NSStackView()
    private let headerView = NSView()
    private let divider = NSView()
    private let contentHostView = NSView()
    private var contentHostHeightConstraint: NSLayoutConstraint?
    private var primaryLabels: [NSTextField] = []
    private var secondaryLabels: [NSTextField] = []
    private var shortcutDescriptionLabels: [NSTextField] = []
    private var shortcutConjunctionLabels: [NSTextField] = []
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
    private let hotkeyRecorder = HotkeyRecorderButton()
    private let fontPopup = NSPopUpButton()
    private let aboutTextView = HoverAwareTextView(frame: .zero)
    private let resetFontButton = NSButton(title: "Reset", target: nil, action: nil)
    private let fontSizeSlider = NSSlider()
    private let fontSizeDetailLabel = NSTextField(labelWithString: "")
    private let resetFontSizeButton = NSButton(title: "Reset", target: nil, action: nil)
    private let borderRadiusSlider = NSSlider()
    private let borderRadiusValueLabel = NSTextField(labelWithString: "")
    private let resetRadiusButton = NSButton(title: "Reset", target: nil, action: nil)

    private var currentAppliedIconTheme: BuiltInTheme
    private var isApplyingPrimaryIconChange = false
    private var hotkeyCapturePopover: NSPopover?

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

        let contentHostHeightConstraint = contentHostView.heightAnchor.constraint(
            equalToConstant: 0)
        self.contentHostHeightConstraint = contentHostHeightConstraint

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: root.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: Metrics.dividerTopInset),

            titleLabel.topAnchor.constraint(
                equalTo: headerView.topAnchor, constant: Metrics.titleTopInset),
            titleLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            tabStack.topAnchor.constraint(
                equalTo: headerView.topAnchor, constant: Metrics.tabTopInset),
            tabStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),

            divider.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            contentHostView.topAnchor.constraint(
                equalTo: divider.bottomAnchor, constant: Metrics.contentTopInset),
            contentHostView.leadingAnchor.constraint(
                equalTo: root.leadingAnchor, constant: Metrics.outerPadding.left),
            contentHostView.trailingAnchor.constraint(
                equalTo: root.trailingAnchor, constant: -Metrics.outerPadding.right),
            contentHostView.bottomAnchor.constraint(
                lessThanOrEqualTo: root.bottomAnchor, constant: -Metrics.outerPadding.bottom),
            contentHostHeightConstraint,
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTabButtons()
        configureControls()
        buildPages()
        selectTab(.appearance, animated: false)
        applyPreferencesToControls()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reportPreferredWindowHeight(animated: false)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        dismissHotkeyCapturePopover()
    }

    var isHotkeyCaptureActive: Bool {
        hotkeyCapturePopover?.isShown == true
    }

    func showAppearanceTab(animated: Bool = false) {
        loadViewIfNeeded()
        selectTab(.appearance, animated: animated)
    }

    func showShortcutsTab(animated: Bool = false) {
        loadViewIfNeeded()
        selectTab(.shortcuts, animated: animated)
    }

    func showAboutTab(animated: Bool = false) {
        loadViewIfNeeded()
        selectTab(.about, animated: animated)
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
        configureHotkeyRecorder()
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

    private func selectTab(_ tab: SettingsTab, animated explicitAnimated: Bool? = nil) {
        let outgoingTab = displayedTab ?? tab
        selectedTab = tab
        if hotkeyCapturePopover?.isShown == true {
            dismissHotkeyCapturePopover()
        }
        if tab != .about, hoveredAboutLink != nil {
            hoveredAboutLink = nil
            updateAboutTextView()
            NSCursor.arrow.set()
            view.window?.invalidateCursorRects(for: aboutTextView)
        }
        tabButtons.forEach { key, button in
            button.isSelected = key == tab
        }

        let targetContentHeight = measuredContentHeight(for: tab)
        let shouldAnimate =
            explicitAnimated
            ?? (view.window?.isVisible == true && displayedTab != nil && outgoingTab != tab)

        transitionGeneration += 1
        let transitionID = transitionGeneration

        guard shouldAnimate else {
            applyVisiblePage(tab)
            transitionDisplayedContentHeight(to: targetContentHeight, animated: false)
            reportPreferredWindowHeight(forContentHeight: targetContentHeight, animated: false)
            return
        }

        preparePagesForTransition(from: outgoingTab, to: tab)
        let currentContentHeight =
            contentHostHeightConstraint?.constant ?? measuredContentHeight(for: outgoingTab)
        let grows = targetContentHeight > currentContentHeight + 0.5

        reportPreferredWindowHeight(forContentHeight: targetContentHeight, animated: true)

        if grows {
            transitionDisplayedContentHeight(to: targetContentHeight, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + AnimationMetrics.growCrossfadeDelay) {
                [weak self] in
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
            labelsStack.trailingAnchor.constraint(
                equalTo: controlsStack.leadingAnchor, constant: -18),
            labelsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            labelsStack.bottomAnchor.constraint(equalTo: controlsStack.bottomAnchor),
        ])

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeShortcutsPage() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let sections: [NSView] = [
            makeShortcutsSection(rows: [
                makeShortcutRecorderRow(label: "Global Hotkey")
            ]),
            makeShortcutsSection(rows: [
                makeShortcutRow(label: "Complete selected", shortcut: ["command", "return"]),
                makeShortcutRow(label: "Delete selected", shortcut: ["command", "delete"]),
                makeShortcutRow(label: "New row below", shortcut: ["return"]),
            ]),
            makeShortcutsSection(rows: [
                makeShortcutRow(label: "Navigate", shortcut: ["up/down"]),
                makeShortcutRow(label: "Select multiple", shortcut: ["shift", "up/down"]),
                makeShortcutRow(label: "Jump to top or bottom", shortcut: ["command", "up/down"]),
                makeShortcutRow(label: "Select to top or bottom", shortcut: ["command", "shift", "up/down"]),
            ]),
            makeShortcutsSection(rows: [
                makeShortcutRow(label: "Show todo list", shortcut: ["command", "1"]),
                makeShortcutRow(label: "Show archive", shortcut: ["command", "2"]),
                makeShortcutRow(label: "Show settings", shortcuts: [["command", "3"], ["command", ","]]),
            ]),
            makeShortcutsSection(rows: [
                makeShortcutRow(label: "Reset window size", shortcut: ["command", "0"]),
                makeShortcutRow(label: "Snap window", shortcut: ["control", "option", "arrow"]),
                makeShortcutRow(label: "Fullscreen", shortcut: ["control", "command", "F"]),
            ]),
        ]

        for (index, section) in sections.enumerated() {
            stack.addArrangedSubview(section)
            if index < sections.count - 1 {
                stack.setCustomSpacing(Metrics.shortcutsSectionGap, after: section)
            }
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func makeShortcutsSection(rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = Metrics.shortcutsRowSpacing
        return stack
    }

    private func makeShortcutRecorderRow(label: String) -> NSView {
        let descriptionLabel = NSTextField(labelWithString: label)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.alignment = .right
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth)
            .isActive = true
        secondaryLabels.append(descriptionLabel)
        shortcutDescriptionLabels.append(descriptionLabel)

        let recorderContainer = NSView()
        recorderContainer.translatesAutoresizingMaskIntoConstraints = false
        recorderContainer.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth)
            .isActive = true
        recorderContainer.addSubview(hotkeyRecorder)

        let recorderWidth = measuredShortcutGroupWidth(["command", "return"]) * 1.6

        NSLayoutConstraint.activate([
            hotkeyRecorder.leadingAnchor.constraint(equalTo: recorderContainer.leadingAnchor),
            hotkeyRecorder.widthAnchor.constraint(equalToConstant: recorderWidth),
            hotkeyRecorder.centerYAnchor.constraint(equalTo: recorderContainer.centerYAnchor),
            hotkeyRecorder.topAnchor.constraint(greaterThanOrEqualTo: recorderContainer.topAnchor),
            hotkeyRecorder.bottomAnchor.constraint(lessThanOrEqualTo: recorderContainer.bottomAnchor),
        ])

        let row = NSStackView(views: [descriptionLabel, recorderContainer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Metrics.shortcutsColumnGap
        return row
    }

    private func measuredShortcutGroupWidth(_ shortcut: [String]) -> CGFloat {
        let keycapWidths = shortcut.map { measuredKeycapWidth(for: $0) }
        let spacing = CGFloat(max(0, shortcut.count - 1)) * 2
        return keycapWidths.reduce(0, +) + spacing
    }

    private func measuredKeycapWidth(for text: String) -> CGFloat {
        let displayText = keycapDisplayText(for: text)
        let font = NSFont.systemFont(ofSize: 11, weight: .regular)
        let labelWidth = ceil((displayText as NSString).size(withAttributes: [.font: font]).width)
        return labelWidth + 18
    }

    private func makeAboutPage() -> NSView {
        aboutTextView.translatesAutoresizingMaskIntoConstraints = false
        aboutTextView.drawsBackground = false
        aboutTextView.isEditable = false
        aboutTextView.isSelectable = false
        aboutTextView.isRichText = true
        aboutTextView.importsGraphics = false
        aboutTextView.allowsUndo = false
        aboutTextView.textContainerInset = .zero
        aboutTextView.isHorizontallyResizable = false
        aboutTextView.isVerticallyResizable = true
        aboutTextView.minSize = .zero
        aboutTextView.maxSize = NSSize(
            width: Metrics.aboutBlockWidth, height: .greatestFiniteMagnitude)
        aboutTextView.textContainer?.containerSize = NSSize(
            width: Metrics.aboutBlockWidth, height: .greatestFiniteMagnitude)
        aboutTextView.textContainer?.widthTracksTextView = true
        aboutTextView.textContainer?.lineFragmentPadding = 0
        aboutTextView.onHoveredLinkChange = { [weak self] link in
            guard let self, self.hoveredAboutLink != link else { return }
            self.hoveredAboutLink = link
            self.updateAboutTextView()
        }
        aboutTextView.onActivatedLink = { [weak self] link in
            self?.handleAboutLinkActivation(link)
        }
        updateAboutTextView()
        aboutTextView.heightAnchor.constraint(equalToConstant: ceil(aboutTextView.frame.height))
            .isActive = true

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(aboutTextView)

        NSLayoutConstraint.activate([
            aboutTextView.topAnchor.constraint(equalTo: container.topAnchor),
            aboutTextView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            aboutTextView.widthAnchor.constraint(equalToConstant: Metrics.aboutBlockWidth),
            aboutTextView.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            aboutTextView.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor, constant: -24),
            aboutTextView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func configureThemeButtons() {
        themeButtons = BuiltInTheme.allCases.enumerated().map { index, theme in
            let backgroundColor = theme.color.nsColor.resolvedSRGB
            let contentColor = theme.style.contentColor.nsColor.resolvedSRGB
            let usesLightText = contentColor.relativeLuminance > backgroundColor.relativeLuminance
            let button = ThemePresetButton(
                color: backgroundColor,
                selectedIndicatorColor: contentColor,
                selectedIndicatorOpacity: usesLightText ? 0.85 : 0.65,
                size: Metrics.themeSwatchButtonSize
            )
            button.tag = index
            button.target = self
            button.action = #selector(themePresetSelected(_:))
            return button
        }

        themeSwatchContainer.wantsLayer = true
        themeSwatchContainer.translatesAutoresizingMaskIntoConstraints = false
        themeSwatchContainer.widthAnchor.constraint(
            equalToConstant: Metrics.themeSwatchContainerWidth
        ).isActive = true
        themeSwatchContainer.heightAnchor.constraint(
            equalToConstant: Metrics.themeSwatchContainerHeight
        ).isActive = true
    }

    private func configureIconApplyControls() {
        iconStatusLabel.font = .systemFont(ofSize: 11)
        iconStatusLabel.alignment = .left
        iconStatusLabel.lineBreakMode = .byTruncatingTail
        iconStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        iconStatusLabel.widthAnchor.constraint(equalToConstant: Metrics.iconStatusWidth).isActive =
            true
        secondaryLabels.append(iconStatusLabel)

        applyIconButton.target = self
        applyIconButton.action = #selector(applyIconAndRelaunch(_:))
        configureResetButton(applyIconButton)
    }

    private func configureHotkeyRecorder() {
        hotkeyRecorder.target = self
        hotkeyRecorder.action = #selector(toggleHotkeyCapturePopover(_:))
    }

    private func configureTransparencySlider() {
        transparencySlider.minValue = 0
        transparencySlider.maxValue = Double(Metrics.opacityStops.count - 1)
        transparencySlider.numberOfTickMarks = Metrics.opacityStops.count
        transparencySlider.allowsTickMarkValuesOnly = true
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
        transparencyLabel.widthAnchor.constraint(equalToConstant: Metrics.transparencyLabelWidth)
            .isActive = true
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
        borderRadiusSlider.widthAnchor.constraint(equalToConstant: Metrics.sliderWidth).isActive =
            true

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
            swatchRow.leadingAnchor.constraint(
                equalTo: themeSwatchContainer.leadingAnchor, constant: Metrics.themeSwatchInset),
            swatchRow.trailingAnchor.constraint(
                equalTo: themeSwatchContainer.trailingAnchor, constant: -Metrics.themeSwatchInset),
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

            transparencyLabel.leadingAnchor.constraint(
                equalTo: blurToggle.trailingAnchor, constant: Metrics.transparencyItemSpacing),
            transparencyLabel.centerYAnchor.constraint(equalTo: control.centerYAnchor),

            transparencySlider.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            transparencySlider.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            transparencySlider.leadingAnchor.constraint(
                equalTo: transparencyLabel.trailingAnchor, constant: Metrics.transparencyItemSpacing
            ),
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
        sliderGroup.widthAnchor.constraint(equalToConstant: Metrics.sliderGroupWidth).isActive =
            true

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
        sliderGroup.widthAnchor.constraint(equalToConstant: Metrics.sliderGroupWidth).isActive =
            true

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

    private func reportPreferredWindowHeight(
        forContentHeight contentHeight: CGFloat? = nil, animated: Bool
    ) {
        guard isViewLoaded else { return }
        let resolvedContentHeight = contentHeight ?? measuredContentHeight(for: selectedTab)
        onPreferredWindowHeightChange?(
            totalWindowHeight(forContentHeight: resolvedContentHeight), animated)
    }

    private func measuredContentHeight(for tab: SettingsTab) -> CGFloat {
        pages[tab]?.contentHeight ?? 0
    }

    private func totalWindowHeight(forContentHeight contentHeight: CGFloat) -> CGFloat {
        Metrics.dividerTopInset + 1 + Metrics.contentTopInset + contentHeight
            + Metrics.outerPadding.bottom
    }

    private func transitionDisplayedContentHeight(
        to targetHeight: CGFloat, animated: Bool, completion: (() -> Void)? = nil
    ) {
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

    private func preparePagesForTransition(
        from outgoingTab: SettingsTab, to incomingTab: SettingsTab
    ) {
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

    private func crossfadeIfCurrent(
        from outgoingTab: SettingsTab, to incomingTab: SettingsTab, transitionID: Int
    ) {
        guard transitionGeneration == transitionID else { return }
        crossfadePages(from: outgoingTab, to: incomingTab, transitionID: transitionID)
    }

    private func crossfadePages(
        from outgoingTab: SettingsTab, to incomingTab: SettingsTab, transitionID: Int
    ) {
        guard let outgoingPage = pages[outgoingTab],
            let incomingPage = pages[incomingTab]
        else {
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
        descriptionLabel.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth)
            .isActive = true
        secondaryLabels.append(descriptionLabel)
        shortcutDescriptionLabels.append(descriptionLabel)

        let keysRow = NSStackView(views: shortcut.map(makeKeycap))
        keysRow.orientation = .horizontal
        keysRow.alignment = .centerY
        keysRow.spacing = 2
        keysRow.translatesAutoresizingMaskIntoConstraints = false

        let keysContainer = NSView()
        keysContainer.translatesAutoresizingMaskIntoConstraints = false
        keysContainer.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth)
            .isActive = true
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

    private func makeShortcutRow(label: String, shortcuts: [[String]]) -> NSView {
        let descriptionLabel = NSTextField(labelWithString: label)
        descriptionLabel.font = .systemFont(ofSize: 12)
        descriptionLabel.alignment = .right
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth)
            .isActive = true
        secondaryLabels.append(descriptionLabel)
        shortcutDescriptionLabels.append(descriptionLabel)

        let keysRow = NSStackView()
        keysRow.orientation = .horizontal
        keysRow.alignment = .centerY
        keysRow.spacing = 6
        keysRow.translatesAutoresizingMaskIntoConstraints = false

        for (index, shortcut) in shortcuts.enumerated() {
            keysRow.addArrangedSubview(makeShortcutKeycapGroup(shortcut))
            if index < shortcuts.count - 1 {
                let orLabel = NSTextField(labelWithString: "or")
                orLabel.font = .systemFont(ofSize: 11, weight: .regular)
                shortcutConjunctionLabels.append(orLabel)
                secondaryLabels.append(orLabel)
                keysRow.addArrangedSubview(orLabel)
            }
        }

        let keysContainer = NSView()
        keysContainer.translatesAutoresizingMaskIntoConstraints = false
        keysContainer.widthAnchor.constraint(equalToConstant: Metrics.shortcutsColumnWidth)
            .isActive = true
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

    private func makeShortcutKeycapGroup(_ shortcut: [String]) -> NSView {
        let stack = NSStackView(views: shortcut.map(makeKeycap))
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        return stack
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
        blurToggle.state = preferences.blurEnabled ? .on : .off
        transparencySlider.doubleValue = Double(nearestOpacityStopIndex(for: preferences.clampedWindowOpacity))
        transparencySlider.isEnabled = opacityControlsEnabled
        hotkeyRecorder.hotkey = preferences.globalHotkey

        if let index = FontStylePreset.allCases.firstIndex(of: preferences.fontStyle) {
            fontPopup.selectItem(at: index)
        }

        let fontSize = LayoutMetrics.nearestFontSizeOption(to: preferences.fontSize)
        let fontSizeIndex =
            LayoutMetrics.fontSizeOptions.firstIndex(of: fontSize)
            ?? LayoutMetrics.defaultFontSizeIndex
        fontSizeSlider.doubleValue = Double(fontSizeIndex)
        fontSizeDetailLabel.stringValue = "\(Int(fontSize)) pt"

        borderRadiusSlider.maxValue = preferences.maximumCornerRadius
        borderRadiusSlider.doubleValue = min(
            preferences.cornerRadius, preferences.maximumCornerRadius)
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
        let snappedIndex = nearestOpacityStopIndex(forSliderValue: sender.doubleValue)
        let snappedValue = Double(snappedIndex)
        if sender.doubleValue != snappedValue {
            sender.doubleValue = snappedValue
        }
        commitPreferenceChange { updated in
            updated.blurEnabled = true
            updated.windowOpacity = Metrics.opacityStops[snappedIndex]
        }
    }

    private func nearestOpacityStopIndex(for opacity: Double) -> Int {
        Metrics.opacityStops.enumerated().min(by: { lhs, rhs in
            abs(lhs.element - opacity) < abs(rhs.element - opacity)
        })?.offset ?? 0
    }

    private func nearestOpacityStopIndex(forSliderValue value: Double) -> Int {
        let roundedValue = Int(round(value))
        return min(max(roundedValue, 0), Metrics.opacityStops.count - 1)
    }

    @objc private func blurToggled(_ sender: NSButton) {
        guard !isUpdatingControls else { return }
        commitPreferenceChange { updated in
            let blurEnabled = sender.state == .on
            updated.blurEnabled = blurEnabled
            if !blurEnabled {
                updated.windowOpacity = 1.0
            }
        }
    }

    @objc private func toggleHotkeyCapturePopover(_ sender: NSButton) {
        if hotkeyCapturePopover?.isShown == true {
            dismissHotkeyCapturePopover()
            return
        }

        let contentController = HotkeyCapturePopoverViewController()
        contentController.backgroundColor = preferences.panelBackgroundColor.withAlphaComponent(0.98)
        contentController.borderColor = preferences.subtleStrokeColor
        contentController.primaryTextColor = preferences.primaryTextColor
        contentController.secondaryTextColor = preferences.secondaryTextColor
        contentController.keycapFillColor = preferences.activeFillColor
        contentController.onCapture = { [weak self] hotkey in
            self?.dismissHotkeyCapturePopover()
            self?.commitPreferenceChange { updated in
                updated.globalHotkey = hotkey
            }
        }
        contentController.onCancel = { [weak self] in
            self?.dismissHotkeyCapturePopover()
        }

        let popover = NSPopover()
        popover.animates = true
        popover.behavior = .transient
        popover.contentViewController = contentController
        popover.delegate = self
        hotkeyCapturePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        contentController.beginRecording(currentHotkey: preferences.globalHotkey)
    }

    private func dismissHotkeyCapturePopover() {
        hotkeyCapturePopover?.performClose(nil)
        hotkeyCapturePopover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        hotkeyCapturePopover = nil
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
            presentIconApplyError(
                message: "App icon rebuilding is only available from the local project checkout.")
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

        iconStatusLabel.stringValue =
            themeMatchesIcon ? "Icon matches this theme." : "Relaunch to apply current theme."
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
        let boostedShortcutLabelColor = preferences.secondaryTextColor.withAlphaComponent(
            min(1.0, preferences.secondaryTextColor.alphaComponent + 0.10)
        )
        shortcutDescriptionLabels.forEach { $0.textColor = boostedShortcutLabelColor }
        shortcutConjunctionLabels.forEach { $0.textColor = boostedShortcutLabelColor }
        keycapLabels.forEach { $0.textColor = preferences.secondaryTextColor }
        keycapBackgroundViews.forEach {
            $0.layer?.backgroundColor = preferences.activeFillColor.cgColor
        }
        hotkeyRecorder.textColor = preferences.primaryTextColor
        hotkeyRecorder.borderColor = preferences.subtleStrokeColor
        hotkeyRecorder.hoverBorderColor = preferences.secondaryTextColor.withAlphaComponent(0.42)
        themeableButtons.forEach { applyThemeStyle(to: $0) }
        applyThemeStyle(to: fontPopup)
        updateAboutTextView()

        tabButtons.values.forEach {
            $0.applyTheme(
                selectedTint: preferences.primaryTextColor,
                inactiveTint: preferences.secondaryTextColor,
                selectedBackground: preferences.activeFillColor
            )
        }
    }

    private func applyThemeStyle(to button: NSButton) {
        let titleColor =
            button.isEnabled
            ? preferences.primaryTextColor
            : preferences.primaryTextColor.withAlphaComponent(0.42)
        let fillColor =
            button.isEnabled
            ? preferences.activeFillColor
            : preferences.activeFillColor.withAlphaComponent(
                max(0.12, preferences.activeFillColor.alphaComponent * 0.48))
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
        let fullContrastTitleColor =
            popup.isEnabled
            ? preferences.contentBaseColor
            : preferences.contentBaseColor.withAlphaComponent(0.42)
        let fillColor =
            popup.isEnabled
            ? preferences.activeFillColor
            : preferences.activeFillColor.withAlphaComponent(
                max(0.12, preferences.activeFillColor.alphaComponent * 0.48))
        let font = popup.font ?? .systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: fullContrastTitleColor,
            .font: font,
        ]

        popup.contentTintColor = fullContrastTitleColor
        popup.bezelColor = fillColor
        popup.menu?.appearance =
            preferences.usesLightText
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
        popup.itemArray.forEach { item in
            item.view = nil
            item.attributedTitle = NSAttributedString(string: item.title, attributes: attributes)
        }

        let selectedTitle = popup.titleOfSelectedItem ?? ""
        popup.attributedTitle = NSAttributedString(string: selectedTitle, attributes: attributes)
    }

    private func openAboutURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleAboutLinkActivation(_ link: String) {
        if link == "floatydo://shortcuts" {
            selectTab(.shortcuts)
            return
        }

        if link == "floatydo://theme" {
            selectTab(.appearance)
            return
        }

        openAboutURL(link)
    }

    private func updateAboutTextView() {
        guard isViewLoaded else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 20

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: preferences.primaryTextColor.withAlphaComponent(0.85),
            .font: NSFont.systemFont(ofSize: 13),
            .paragraphStyle: paragraphStyle,
        ]

        let text = NSMutableAttributedString()
        func appendParagraphBreak() {
            text.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
        }
        func appendBody(_ string: String) {
            text.append(NSAttributedString(string: string, attributes: bodyAttributes))
        }
        func appendLink(_ title: String, link: String) {
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: preferences.primaryTextColor.withAlphaComponent(
                    hoveredAboutLink == link ? 1.0 : 0.85
                ),
                .font: NSFont.systemFont(ofSize: 13),
                .paragraphStyle: paragraphStyle,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
            attributes[.link] = link
            text.append(NSAttributedString(string: title, attributes: attributes))
        }

        appendBody(
            "FloatyDo is a minimal app designed to keep you focused on your next few tasks and nothing else."
        )
        appendParagraphBreak()
        appendBody(
            "It is not a project management tool. It has no groups, scheduling, badges, or calendar sync. But for what it does I hope it works well and feels like it’s "
        )
        appendLink("your own", link: "floatydo://theme")
        appendBody(".")
        appendParagraphBreak()
        appendBody("I recommend taking some time to get familiar with the ")
        appendLink("keyboard shortcuts", link: "floatydo://shortcuts")
        appendBody(" as it makes the FloatyDo experience significantly better.")
        appendParagraphBreak()
        appendBody("Feel free to ")
        appendLink("email me", link: "mailto:raffi.chilingaryan@gmail.com")
        appendBody(" with any feedback or requests, and thanks for giving the app a try.")
        appendParagraphBreak()
        appendBody("Raffi")
        appendParagraphBreak()
        appendBody("App icons and iconography by ")
        appendLink("Emirhan", link: "https://x.com/_eugrl")

        aboutTextView.textStorage?.setAttributedString(text)
        aboutTextView.linkTextAttributes = [
            .foregroundColor: preferences.primaryTextColor.withAlphaComponent(0.85),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        aboutTextView.layoutManager?.ensureLayout(for: aboutTextView.textContainer!)
        let usedRect =
            aboutTextView.layoutManager?.usedRect(for: aboutTextView.textContainer!) ?? .zero
        aboutTextView.frame.size = NSSize(
            width: Metrics.aboutBlockWidth, height: ceil(usedRect.height))
        aboutTextView.invalidateIntrinsicContentSize()
    }

}

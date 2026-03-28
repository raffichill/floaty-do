import AppKit
import Carbon.HIToolbox
import XCTest
@testable import FloatyDoLib

@MainActor
final class SettingsViewControllerTests: XCTestCase {
    func testAppearancePageHidesTransparencyControls() {
        let controller = SettingsViewController(preferences: .default)
        controller.loadViewIfNeeded()

        let labels = allLabels(in: controller.view).map(\.stringValue)

        XCTAssertFalse(labels.contains("Transparent"))
        XCTAssertFalse(labels.contains("Opacity"))
        XCTAssertFalse(labels.contains("App Icon"))
    }

    func testSettingsTabsIncludeIconBetweenShortcutsAndAbout() {
        let controller = SettingsViewController(preferences: .default)
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.testingTabTitles(), ["Theme", "Shortcuts", "Icon", "About"])
    }

    func testIconPageListsAvailableIconAssets() {
        let controller = SettingsViewController(preferences: .default)
        controller.loadViewIfNeeded()

        XCTAssertEqual(
            controller.testingIconOptionTitles(),
            ["Theme 1", "Theme 2", "Theme 3", "Theme 4", "Theme 5", "Theme 6", "Theme 7", "Theme 8"]
        )
    }

    func testThemeDigitShortcutAppliesMatchingThemeOnlyOnAppearanceTab() {
        let controller = SettingsViewController(preferences: .default)
        controller.loadViewIfNeeded()

        var updatedTheme: BuiltInTheme?
        controller.onPreferencesChange = { updated in
            updatedTheme = updated.theme
        }

        XCTAssertTrue(controller.handleThemeDigitShortcut(6))
        XCTAssertEqual(updatedTheme, .theme6)

        controller.showIconTab(animated: false)
        updatedTheme = nil

        XCTAssertFalse(controller.handleThemeDigitShortcut(2))
        XCTAssertNil(updatedTheme)
    }

    func testIconFooterShowsCurrentStateOrRelaunchPrompt() {
        let controller = SettingsViewController(preferences: .default)
        controller.loadViewIfNeeded()

        let currentTheme = PrimaryAppIconRelaunchController.shared.currentTheme()
        XCTAssertEqual(
            controller.testingIconFooterMessage(),
            "Using \(controller.testingIconDisplayName(for: currentTheme))"
        )
        XCTAssertFalse(controller.testingIconFooterShowsRelaunchButton())

        let alternateTheme = BuiltInTheme.catalog
            .map(\.theme)
            .first { $0.supportsPrimaryAppIcon && $0 != currentTheme }
        XCTAssertNotNil(alternateTheme)

        controller.testingSelectIconTheme(alternateTheme ?? currentTheme)

        XCTAssertEqual(controller.testingIconFooterMessage(), "to apply the selected icon.")
        XCTAssertTrue(controller.testingIconFooterShowsRelaunchButton())
    }

    func testShortcutsPageIncludesSettingsTabShortcuts() {
        let controller = SettingsViewController(preferences: .default)
        controller.loadViewIfNeeded()

        let labels = allLabels(in: controller.view).map(\.stringValue)

        XCTAssertTrue(labels.contains("Theme tab"))
        XCTAssertTrue(labels.contains("Shortcuts tab"))
        XCTAssertTrue(labels.contains("Icon tab"))
        XCTAssertTrue(labels.contains("About tab"))
    }

    func testPreferencesTemporarilyDisableTranslucentSurface() {
        XCTAssertFalse(AppPreferences.default.usesTranslucentSurface)
        XCTAssertFalse(
            AppPreferences(
                rowHeight: 36,
                panelWidth: 400,
                hoverHighlightsEnabled: true,
                animationPreset: .balanced,
                snapPadding: 32,
                theme: .theme1,
                fontStyle: .system,
                fontSize: LayoutMetrics.defaultFontSize,
                cornerRadius: 10,
                blurEnabled: true,
                windowOpacity: 0.67,
                globalHotkey: .defaultToggle
            ).usesTranslucentSurface
        )
    }

    func testBuiltInThemeCatalogIsSingleSourceOfTruthForOrderAndIconSupport() {
        XCTAssertEqual(
            BuiltInTheme.allCases,
            [.theme1, .theme2, .theme3, .theme4, .theme5, .theme6, .theme7, .theme8]
        )
        XCTAssertEqual(BuiltInTheme.catalog.map(\.theme), BuiltInTheme.allCases)
        XCTAssertTrue(BuiltInTheme.theme1.supportsPrimaryAppIcon)
        XCTAssertTrue(BuiltInTheme.theme5.supportsPrimaryAppIcon)
        XCTAssertTrue(BuiltInTheme.theme6.supportsPrimaryAppIcon)
        XCTAssertTrue(BuiltInTheme.theme7.supportsPrimaryAppIcon)
        XCTAssertTrue(BuiltInTheme.theme8.supportsPrimaryAppIcon)
    }

    func testBuiltInThemeNearestUsesCatalogColors() {
        XCTAssertEqual(BuiltInTheme.nearest(to: BuiltInTheme.theme6.color), .theme6)
        XCTAssertEqual(BuiltInTheme.nearest(to: BuiltInTheme.theme7.color), .theme7)
        XCTAssertEqual(BuiltInTheme.nearest(to: BuiltInTheme.theme5.color), .theme5)
    }

    func testTextSelectionOverlayUsesForegroundAtFifteenPercentOpacity() {
        let preferences = AppPreferences.default
        guard
            let overlay = preferences.selectionOverlayColor.usingColorSpace(.deviceRGB),
            let foreground = preferences.palette.foreground.usingColorSpace(.deviceRGB)
        else {
            XCTFail("Expected RGB colors for selection overlay regression")
            return
        }

        XCTAssertEqual(overlay.redComponent, foreground.redComponent, accuracy: 0.001)
        XCTAssertEqual(overlay.greenComponent, foreground.greenComponent, accuracy: 0.001)
        XCTAssertEqual(overlay.blueComponent, foreground.blueComponent, accuracy: 0.001)
        XCTAssertEqual(overlay.alphaComponent, 0.15, accuracy: 0.001)
    }

    func testTextVerticalOffsetTablesPreserveCurrentDefaults() {
        XCTAssertEqual(LayoutMetrics.manualTextVerticalOffset(fontStyle: .system, fontSize: 14), -0.5)
        XCTAssertEqual(LayoutMetrics.manualTextVerticalOffset(fontStyle: .serif, fontSize: 12), -2.0)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .system, fontSize: 12), 1.5)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .rounded, fontSize: 15), 2.0)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .monospaced, fontSize: 16), 1.5)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .serif, fontSize: 14), 2.5)
    }

    func testUpdatingPreferencesBeforeViewLoadsDoesNotCrash() {
        let controller = SettingsViewController(preferences: .default)
        let updatedPreferences = AppPreferences(
            rowHeight: 40,
            panelWidth: 440,
            hoverHighlightsEnabled: false,
            animationPreset: .relaxed,
            snapPadding: 32,
            theme: .theme2,
            fontStyle: .rounded,
            fontSize: 15,
            cornerRadius: 16
        )

        controller.updatePreferences(updatedPreferences)
        controller.loadViewIfNeeded()

        XCTAssertNotNil(controller.view)
    }

    func testGlobalHotkeyDisplayStringIncludesStoredAnsiCharacterKeys() {
        let hotkey = GlobalHotkey(
            keyCode: UInt16(kVK_ANSI_K),
            command: false,
            option: true,
            control: false,
            shift: false
        )

        XCTAssertEqual(hotkey.displayString, "⌥ K")
    }

    func testCompositedTranslucentSurfaceOpacityTracksConfiguredOpacityStops() {
        let stops = [0.67, 0.78, 0.89, 1.0].map { opacity in
            AppPreferences(
                rowHeight: 36,
                panelWidth: 400,
                hoverHighlightsEnabled: true,
                animationPreset: .balanced,
                snapPadding: 32,
                theme: .theme1,
                fontStyle: .system,
                fontSize: LayoutMetrics.defaultFontSize,
                cornerRadius: 10,
                blurEnabled: true,
                windowOpacity: opacity,
                globalHotkey: .defaultToggle
            ).compositedTranslucentSurfaceOpacity
        }

        XCTAssertTrue(stops[0] < stops[1])
        XCTAssertTrue(stops[1] < stops[2])
        XCTAssertTrue(stops[2] < stops[3])
        XCTAssertGreaterThan(stops[0], 0.70)
        XCTAssertLessThan(stops[3], 1.0)
    }

    private func allLabels(in view: NSView) -> [NSTextField] {
        let childLabels = view.subviews.flatMap(allLabels(in:))
        if let label = view as? NSTextField {
            return [label] + childLabels
        }
        return childLabels
    }
}

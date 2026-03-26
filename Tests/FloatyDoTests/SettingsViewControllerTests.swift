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
            ["Theme 1", "Theme 2", "Theme 3", "Theme 4", "Theme 5"]
        )
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

        XCTAssertEqual(controller.testingIconFooterMessage(), "FloatyDo to apply the selected icon.")
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
            [.theme1, .theme2, .theme3, .theme4, .nasaOrange, .barbie, .matcha, .theme5]
        )
        XCTAssertEqual(BuiltInTheme.catalog.map(\.theme), BuiltInTheme.allCases)
        XCTAssertTrue(BuiltInTheme.theme1.supportsPrimaryAppIcon)
        XCTAssertTrue(BuiltInTheme.theme5.supportsPrimaryAppIcon)
        XCTAssertFalse(BuiltInTheme.barbie.supportsPrimaryAppIcon)
        XCTAssertFalse(BuiltInTheme.matcha.supportsPrimaryAppIcon)
        XCTAssertFalse(BuiltInTheme.nasaOrange.supportsPrimaryAppIcon)
    }

    func testBuiltInThemeNearestUsesCatalogColors() {
        XCTAssertEqual(BuiltInTheme.nearest(to: BuiltInTheme.barbie.color), .barbie)
        XCTAssertEqual(BuiltInTheme.nearest(to: BuiltInTheme.matcha.color), .matcha)
        XCTAssertEqual(BuiltInTheme.nearest(to: BuiltInTheme.nasaOrange.color), .nasaOrange)
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

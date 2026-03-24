import AppKit
import Carbon.HIToolbox
import XCTest
@testable import FloatyDoLib

@MainActor
final class SettingsViewControllerTests: XCTestCase {
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
}

import AppKit
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
        XCTAssertEqual(LayoutMetrics.manualTextVerticalOffset(fontStyle: .system, fontSize: 14), 0)
        XCTAssertEqual(LayoutMetrics.manualTextVerticalOffset(fontStyle: .serif, fontSize: 12), 0)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .system, fontSize: 12), 1)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .rounded, fontSize: 15), 1)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .monospaced, fontSize: 16), 0)
        XCTAssertEqual(LayoutMetrics.displayTextVerticalOffset(fontStyle: .serif, fontSize: 14), 0)
    }

    func testUpdatingPreferencesBeforeViewLoadsDoesNotCrash() {
        let controller = SettingsViewController(preferences: .default)
        let updatedPreferences = AppPreferences(
            rowHeight: 40,
            panelWidth: 440,
            hoverHighlightsEnabled: false,
            animationPreset: .relaxed,
            snapPadding: 32,
            themeColor: ThemeColor(red: 0.15, green: 0.42, blue: 0.67, alpha: 1),
            fontStyle: .rounded,
            fontSize: 15,
            cornerRadius: 16
        )

        controller.updatePreferences(updatedPreferences)
        controller.loadViewIfNeeded()

        XCTAssertNotNil(controller.view)
    }
}

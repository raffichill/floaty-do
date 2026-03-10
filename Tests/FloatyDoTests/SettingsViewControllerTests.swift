import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
final class SettingsViewControllerTests: XCTestCase {
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

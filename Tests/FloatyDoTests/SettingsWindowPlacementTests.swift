import AppKit
import XCTest
@testable import FloatyDoLib

final class SettingsWindowPlacementTests: XCTestCase {
    func testSmallViewportFallsBackToCenteredPresentation() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1200, height: 760)
        let parentFrame = NSRect(x: 840, y: 420, width: 340, height: 220)
        let settingsSize = NSSize(width: 680, height: 560)

        let origin = SettingsWindowPlacement.origin(
            for: settingsSize,
            parentFrame: parentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 260, accuracy: 0.5)
        XCTAssertEqual(origin.y, 100, accuracy: 0.5)
    }

    func testTopLeftParentPlacesSettingsToTheRightAndTopAligned() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let parentFrame = NSRect(x: 24, y: 845, width: 340, height: 220)
        let settingsSize = NSSize(width: 680, height: 560)

        let origin = SettingsWindowPlacement.origin(
            for: settingsSize,
            parentFrame: parentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, parentFrame.maxX + SettingsWindowPlacement.companionGap, accuracy: 0.5)
        XCTAssertEqual(origin.y, parentFrame.maxY - settingsSize.height, accuracy: 0.5)
    }

    func testBottomRightParentPlacesSettingsToTheLeftAndBottomAligned() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let parentFrame = NSRect(x: 1364, y: 24, width: 340, height: 220)
        let settingsSize = NSSize(width: 680, height: 560)

        let origin = SettingsWindowPlacement.origin(
            for: settingsSize,
            parentFrame: parentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, parentFrame.minX - SettingsWindowPlacement.companionGap - settingsSize.width, accuracy: 0.5)
        XCTAssertEqual(origin.y, parentFrame.minY, accuracy: 0.5)
    }

    func testSideChoiceUsesAvailableHorizontalSpaceInsteadOfMidpoint() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1728, height: 1117)
        let parentFrame = NSRect(x: 640, y: 620, width: 340, height: 220)
        let settingsSize = NSSize(width: 680, height: 560)

        let origin = SettingsWindowPlacement.origin(
            for: settingsSize,
            parentFrame: parentFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, parentFrame.maxX + SettingsWindowPlacement.companionGap, accuracy: 0.5)
        XCTAssertEqual(origin.y, parentFrame.maxY - settingsSize.height, accuracy: 0.5)
    }
}

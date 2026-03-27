import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testSettingsWindowRemainsVisibleAfterResigningKey() throws {
        let controller = SettingsWindowController(preferences: .default)
        controller.present(attachedTo: nil)

        guard let window = controller.window else {
            return XCTFail("Expected settings window")
        }

        controller.windowDidResignKey(
            Notification(name: NSWindow.didResignKeyNotification, object: window)
        )

        XCTAssertTrue(window.isVisible)
        window.close()
    }
}

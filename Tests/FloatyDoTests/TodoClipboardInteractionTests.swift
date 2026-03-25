import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
final class TodoClipboardInteractionTests: TodoInteractionTestCase {
    func testMultilinePasteBelowSelectedTaskInsertsRows() {
        let store = seededStore(active: ["A", "B"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        _ = controller.testingAttachWindow()
        controller.testingSelectTask(at: 0)

        controller.testingPasteText("One\nTwo\nThree")

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskItem("Three"))
        XCTAssertEqual(snapshot.visibleTaskSequence, ["A", "One", "Two", "Three", "B", "<draft>"])
    }

    func testCopyWithoutHighlightedTextCopiesSelectedRowAndShowsToast() {
        let store = seededStore(active: ["Alpha", "Beta"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        _ = controller.testingAttachWindow()
        controller.testingSelectTask(at: 1)

        controller.testingCopySelection()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Beta")
        XCTAssertEqual(controller.testingCopyToastMessage(), "Copied row")
    }
}

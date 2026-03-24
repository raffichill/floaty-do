import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
final class TodoOverflowAndArchiveTests: TodoInteractionTestCase {
    func testArchiveKeyboardNavigationDoesNotResizeWindowFrame() {
        let store = seededStore(
            active: ["A", "B"],
            archived: ["Archived 1", "Archived 2", "Archived 3", "Archived 4"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 350, height: 260))
        controller.testingSelectArchive(at: 0)

        let initialSize = window.frame.size
        XCTAssertTrue(controller.moveDown())
        XCTAssertTrue(controller.moveDown())

        XCTAssertEqual(window.frame.width, initialSize.width, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, initialSize.height, accuracy: 0.5)
    }

    func testArchivePermanentDeleteDoesNotResizeWindowFrame() {
        let store = seededStore(
            active: ["A", "B"],
            archived: ["Archived 1", "Archived 2", "Archived 3"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 350, height: 260))
        controller.testingSelectArchive(at: 1)

        let initialSize = window.frame.size
        controller.testingDeleteSelected()

        XCTAssertEqual(window.frame.width, initialSize.width, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, initialSize.height, accuracy: 0.5)
    }

    func testArchiveKeyboardRestoreDoesNotResizeWindowFrame() {
        let store = seededStore(
            active: ["A", "B"],
            archived: ["Archived 1", "Archived 2", "Archived 3"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 350, height: 260))
        controller.testingSelectArchive(at: 1)

        let initialSize = window.frame.size
        controller.testingCompleteSelected()
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))

        XCTAssertEqual(window.frame.width, initialSize.width, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, initialSize.height, accuracy: 0.5)
    }

    func testArchiveRestoreIsDisabledWhenTaskListIsFull() {
        let store = seededStore(
            active: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"],
            archived: ["Archived"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectArchive(at: 0)

        XCTAssertFalse(controller.testingCanRestoreArchiveSelection())

        controller.testingRestoreArchiveSelection()

        XCTAssertEqual(store.items.count, TodoStore.maxItems)
        XCTAssertEqual(store.archivedItems.map(\.text), ["Archived"])
    }

    func testArchiveKeyboardNavigationKeepsContextVisibleWhenOverflowing() {
        let store = seededStore(
            active: [],
            archived: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSetViewSize(NSSize(width: 400, height: 240))
        controller.testingSelectArchive(at: 0)

        for _ in 0..<6 {
            XCTAssertTrue(controller.moveDown())
        }

        guard let selectedFrame = controller.testingFrameForSelectedRow() else {
            return XCTFail("Expected a selected archive row frame")
        }

        let buffer = CGFloat(store.preferences.rowHeight) * 1.0
        let originY = controller.testingListScrollOriginY()
        let visibleHeight = controller.testingListViewportHeight()

        XCTAssertGreaterThan(controller.testingListDocumentHeight(), visibleHeight)
        XCTAssertGreaterThanOrEqual(selectedFrame.minY - originY, buffer - 0.5)
        XCTAssertLessThanOrEqual(selectedFrame.maxY - originY, visibleHeight - buffer + 0.5)
    }

    func testTaskKeyboardNavigationKeepsContextVisibleWhenOverflowing() {
        let store = seededStore(
            active: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSetViewSize(NSSize(width: 400, height: 240))
        controller.testingSelectTask(at: 0)

        for _ in 0..<6 {
            XCTAssertTrue(controller.moveDown())
        }

        guard let selectedFrame = controller.testingFrameForSelectedRow() else {
            return XCTFail("Expected a selected task row frame")
        }

        let buffer = CGFloat(store.preferences.rowHeight) * 1.0
        let originY = controller.testingListScrollOriginY()
        let visibleHeight = controller.testingListViewportHeight()

        XCTAssertGreaterThan(controller.testingListDocumentHeight(), visibleHeight)
        XCTAssertGreaterThanOrEqual(selectedFrame.minY - originY, buffer - 0.5)
        XCTAssertLessThanOrEqual(selectedFrame.maxY - originY, visibleHeight - buffer + 0.5)
    }

    func testArchiveKeyboardNavigationToLastItemScrollsToBottomEdge() {
        let store = seededStore(
            active: [],
            archived: ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSetViewSize(NSSize(width: 400, height: 240))
        controller.testingSelectArchive(at: 0)

        for _ in 0..<(store.archivedItems.count - 1) {
            XCTAssertTrue(controller.moveDown())
        }

        let expectedBottomOffset = controller.testingListDocumentHeight() - controller.testingListViewportHeight()
        XCTAssertEqual(controller.testingListScrollOriginY(), expectedBottomOffset, accuracy: 0.5)
    }
}

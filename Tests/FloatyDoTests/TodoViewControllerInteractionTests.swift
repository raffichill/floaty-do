import XCTest
import AppKit
@testable import FloatyDoLib

@MainActor
final class TodoViewControllerInteractionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "floatydo.items")
        UserDefaults.standard.removeObject(forKey: "floatydo.archived")
        UserDefaults.standard.removeObject(forKey: "floatydo.preferences")
    }

    func testReturnOnFirstItemInsertsDraftDirectlyBelow() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 0)

        controller.submitRow()

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskDraft)
        XCTAssertEqual(snapshot.draftInsertionIndex, 1)
        XCTAssertEqual(snapshot.visibleTaskSequence, ["A", "<draft>", "B", "C"])
    }

    func testUpArrowFromFirstItemCreatesDraftAboveFirstItem() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 0)

        XCTAssertTrue(controller.moveUp())

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskDraft)
        XCTAssertEqual(snapshot.draftInsertionIndex, 0)
        XCTAssertEqual(snapshot.visibleTaskSequence, ["<draft>", "A", "B", "C"])
    }

    func testExplicitEmptyDraftPlacementSurvivesGenericRefresh() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 0)
        _ = controller.moveUp()

        controller.testingRefresh()

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskDraft)
        XCTAssertEqual(snapshot.draftInsertionIndex, 0)
        XCTAssertEqual(snapshot.visibleTaskSequence, ["<draft>", "A", "B", "C"])
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

        let buffer = CGFloat(store.preferences.rowHeight) * 1.5
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

    func testRecordedUserWidthSurvivesRefreshResize() {
        let store = seededStore(active: ["A"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()

        controller.recordUserResizedWindowSize(NSSize(width: 520, height: 320))
        let resizedTarget = controller.testingResolvedTargetWindowSize(
            fullWidth: 400,
            fullHeight: 240,
            minSize: .zero
        )
        XCTAssertEqual(resizedTarget.width, 520, accuracy: 0.5)
        XCTAssertEqual(resizedTarget.height, 320, accuracy: 0.5)

        controller.testingRefresh()
        let refreshedTarget = controller.testingResolvedTargetWindowSize(
            fullWidth: 400,
            fullHeight: 240,
            minSize: .zero
        )
        XCTAssertEqual(refreshedTarget.width, 520, accuracy: 0.5)
        XCTAssertEqual(refreshedTarget.height, 320, accuracy: 0.5)
    }

    private func seededStore(active items: [String], archived: [String] = []) -> TodoStore {
        let store = TodoStore()
        let activeItems = items.map(TodoItem.init(text:))
        let archivedItems = archived.map { text -> TodoItem in
            var item = TodoItem(text: text)
            item.isDone = true
            return item
        }
        store.restoreState(items: activeItems, archivedItems: archivedItems, preferences: .default)
        return store
    }
}

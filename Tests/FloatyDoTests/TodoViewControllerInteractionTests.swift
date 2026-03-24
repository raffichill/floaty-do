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

    func testManualResizeFloorDoesNotBlockStructuralGrowth() {
        let store = seededStore(active: ["A"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()

        controller.recordUserResizedWindowSize(NSSize(width: 420, height: 200))
        let grownTarget = controller.testingResolvedTargetWindowSize(
            fullWidth: 420,
            fullHeight: 320,
            minSize: .zero
        )

        XCTAssertEqual(grownTarget.width, 420, accuracy: 0.5)
        XCTAssertEqual(grownTarget.height, 320, accuracy: 0.5)
    }

    func testTaskStructuralHeightIgnoresRecordedUserHeightFloor() {
        let store = seededStore(active: ["A"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()

        controller.recordUserResizedWindowSize(NSSize(width: 420, height: 320))

        let ordinaryTarget = controller.testingResolvedTargetWindowSize(
            fullWidth: 420,
            fullHeight: 240,
            minSize: .zero
        )
        let structuralTarget = controller.testingResolvedTargetWindowSize(
            fullWidth: 420,
            fullHeight: 240,
            minSize: .zero,
            fitTaskStructuralContent: true
        )

        XCTAssertEqual(ordinaryTarget.height, 320, accuracy: 0.5)
        XCTAssertEqual(structuralTarget.height, 240, accuracy: 0.5)
    }

    func testActivatingDraftAddsOneMoreVisibleRowOfRunway() {
        let store = seededStore(active: ["A", "B"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 1)

        XCTAssertEqual(controller.testingVisibleRowCount(), 5)

        controller.submitRow()

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskDraft)
        XCTAssertEqual(snapshot.draftInsertionIndex, 2)
        XCTAssertEqual(controller.testingVisibleRowCount(), 6)
    }

    func testDraftRunwayCapsAtTenVisibleRows() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F", "G"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 6)

        controller.submitRow()

        XCTAssertEqual(controller.testingVisibleRowCount(), TodoStore.maxItems)
    }

    func testCollapsingFreshDraftRemovesExtraRunwayRow() {
        let store = seededStore(active: ["A", "B"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 1)

        controller.submitRow()
        XCTAssertEqual(controller.testingVisibleRowCount(), 6)

        XCTAssertTrue(controller.moveUp())

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskItem("B"))
        XCTAssertEqual(controller.testingVisibleRowCount(), 5)
    }

    func testSubmitRowGrowsRealWindowFrameForStructuralDraftRunway() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 2)

        let initialHeight = window.frame.height
        controller.submitRow()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        XCTAssertEqual(controller.testingVisibleRowCount(), 7)
        XCTAssertGreaterThan(window.frame.height, initialHeight + 20)
    }

    func testMoveDownIntoBottomDraftGrowsRealWindowFrameForStructuralDraftRunway() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 2)

        let initialHeight = window.frame.height
        XCTAssertTrue(controller.moveDown())

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskDraft)
        XCTAssertGreaterThan(window.frame.height, initialHeight + 20)
    }

    func testRepeatedReturnDrivenRowCreationKeepsGrowingRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 2)

        let initialHeight = window.frame.height

        controller.submitRow()
        let afterFirstReturn = window.frame.height

        controller.testingTypeIntoCurrentEditor("asd")
        controller.submitRow()
        let afterSecondReturn = window.frame.height

        controller.testingTypeIntoCurrentEditor("asd")
        controller.submitRow()
        let afterThirdReturn = window.frame.height

        XCTAssertGreaterThan(afterFirstReturn, initialHeight + 20)
        XCTAssertGreaterThan(afterSecondReturn, afterFirstReturn + 20)
        XCTAssertGreaterThan(afterThirdReturn, afterSecondReturn + 20)
    }

    func testCollapsingFreshDraftShrinksRealWindowFrameImmediately() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 2)

        controller.submitRow()
        let grownHeight = window.frame.height

        XCTAssertTrue(controller.moveUp())

        let collapsedHeight = window.frame.height
        XCTAssertLessThan(collapsedHeight, grownHeight - 20)
    }

    func testDeleteSelectedTaskShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 5)

        let initialHeight = window.frame.height
        controller.testingDeleteSelected()

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
    }

    func testDeleteSelectedTaskRangeShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F", "G"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTaskRange([5, 6])

        let initialHeight = window.frame.height
        controller.testingDeleteSelected()

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
    }

    func testCompleteSelectedTaskShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 5)

        let initialHeight = window.frame.height
        controller.testingCompleteSelected()
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
    }

    func testCompleteSelectedTaskRangeShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F", "G"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTaskRange([5, 6])

        let initialHeight = window.frame.height
        controller.testingCompleteSelected()
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
    }

    func testSwitchingTabsPreservesWindowHeight() {
        let store = seededStore(
            active: ["A", "B", "C", "D", "E", "F", "G"],
            archived: ["Archived 1", "Archived 2"]
        )
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()

        let tasksHeight = window.frame.height
        controller.testingShowArchiveTab()
        let archiveHeight = window.frame.height
        controller.testingShowTasksTab()
        let tasksHeightAgain = window.frame.height

        XCTAssertEqual(archiveHeight, tasksHeight, accuracy: 0.5)
        XCTAssertEqual(tasksHeightAgain, tasksHeight, accuracy: 0.5)
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

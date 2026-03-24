import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
final class TodoDraftNavigationTests: TodoInteractionTestCase {
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

    func testActivatingDraftDoesNotAddVisibleRunwayUntilItBecomesATask() {
        let store = seededStore(active: ["A", "B"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 1)

        XCTAssertEqual(controller.testingVisibleRowCount(), 5)

        controller.submitRow()

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskDraft)
        XCTAssertEqual(snapshot.draftInsertionIndex, 2)
        XCTAssertEqual(controller.testingVisibleRowCount(), 5)

        controller.testingTypeIntoCurrentEditor("C")
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

    func testCollapsingFreshDraftWithoutTypingLeavesVisibleRowCountUnchanged() {
        let store = seededStore(active: ["A", "B"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 1)

        controller.submitRow()
        XCTAssertEqual(controller.testingVisibleRowCount(), 5)

        XCTAssertTrue(controller.moveUp())

        let snapshot = controller.testingSnapshot()
        XCTAssertEqual(snapshot.selected, .taskItem("B"))
        XCTAssertEqual(controller.testingVisibleRowCount(), 5)
    }

    func testSubmitRowDoesNotGrowRealWindowFrameUntilDraftBecomesTask() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 2)

        let initialHeight = window.frame.height
        controller.submitRow()

        XCTAssertEqual(controller.testingVisibleRowCount(), 6)
        XCTAssertEqual(window.frame.height, initialHeight, accuracy: 0.5)

        controller.testingTypeIntoCurrentEditor("D")

        XCTAssertEqual(controller.testingVisibleRowCount(), 7)
        XCTAssertGreaterThan(window.frame.height, initialHeight + 20)
    }

    func testMoveDownIntoBottomDraftDoesNotGrowRealWindowFrameUntilTyping() {
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
        XCTAssertEqual(window.frame.height, initialHeight, accuracy: 0.5)

        controller.testingTypeIntoCurrentEditor("D")
        XCTAssertGreaterThan(window.frame.height, initialHeight + 20)
    }

    func testMoveDownFromDefaultBottomDraftStaysOnDraftAndProvidesBoundaryFeedback() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 2)

        XCTAssertTrue(controller.moveDown())
        let beforeSnapshot = controller.testingSnapshot()

        XCTAssertTrue(controller.moveDown())

        let afterSnapshot = controller.testingSnapshot()
        XCTAssertEqual(afterSnapshot.selected, .taskDraft)
        XCTAssertEqual(afterSnapshot.draftInsertionIndex, store.items.count)
        XCTAssertEqual(afterSnapshot, beforeSnapshot)
        XCTAssertEqual(controller.testingLastBoundaryShakeRowID(), .taskDraft)
    }

    func testReturnFromDefaultBottomDraftStaysOnDraftAndProvidesBoundaryFeedback() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        controller.testingSelectTask(at: 2)

        XCTAssertTrue(controller.moveDown())
        let beforeSnapshot = controller.testingSnapshot()

        controller.submitRow()

        let afterSnapshot = controller.testingSnapshot()
        XCTAssertEqual(afterSnapshot.selected, .taskDraft)
        XCTAssertEqual(afterSnapshot.draftInsertionIndex, store.items.count)
        XCTAssertEqual(afterSnapshot, beforeSnapshot)
        XCTAssertEqual(controller.testingLastBoundaryShakeRowID(), .taskDraft)
    }

    func testRepeatedReturnDrivenRowCreationOnlyGrowsAfterTypingIntoDraft() {
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
        let afterFirstType = window.frame.height

        controller.submitRow()
        let afterSecondReturn = window.frame.height
        controller.testingTypeIntoCurrentEditor("asd")
        let afterSecondType = window.frame.height

        controller.submitRow()
        let afterThirdReturn = window.frame.height
        controller.testingTypeIntoCurrentEditor("asd")
        let afterThirdType = window.frame.height

        XCTAssertEqual(afterFirstReturn, initialHeight, accuracy: 0.5)
        XCTAssertGreaterThan(afterFirstType, afterFirstReturn + 20)
        XCTAssertEqual(afterSecondReturn, afterFirstType, accuracy: 0.5)
        XCTAssertGreaterThan(afterSecondType, afterSecondReturn + 20)
        XCTAssertEqual(afterThirdReturn, afterSecondType, accuracy: 0.5)
        XCTAssertGreaterThan(afterThirdType, afterThirdReturn + 20)
    }

    func testCollapsingFreshDraftWithoutTypingDoesNotChangeRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 2)

        controller.submitRow()
        let draftHeight = window.frame.height

        XCTAssertTrue(controller.moveUp())

        let collapsedHeight = window.frame.height
        XCTAssertEqual(collapsedHeight, draftHeight, accuracy: 0.5)
    }
}

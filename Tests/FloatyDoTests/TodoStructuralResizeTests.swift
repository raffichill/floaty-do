import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
final class TodoStructuralResizeTests: TodoInteractionTestCase {
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
            fitActiveTaskRows: true
        )

        XCTAssertEqual(ordinaryTarget.height, 320, accuracy: 0.5)
        XCTAssertEqual(structuralTarget.height, 240, accuracy: 0.5)
    }

    func testCollapsingDraftCreatedByDeletingTaskTextShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 5)

        let initialHeight = window.frame.height
        controller.testingTypeIntoCurrentEditor("")
        let convertedHeight = window.frame.height

        XCTAssertEqual(controller.testingSnapshot().selected, .taskDraft)
        XCTAssertLessThan(convertedHeight, initialHeight - 20)

        XCTAssertTrue(controller.moveUp())

        let collapsedHeight = window.frame.height
        XCTAssertEqual(collapsedHeight, convertedHeight, accuracy: 0.5)
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

    func testCompleteSelectedTaskViaCheckboxShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 5)

        let initialHeight = window.frame.height
        controller.testingCompleteSelectedViaCheckbox()
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
}

import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
final class TodoStructuralResizeTests: TodoInteractionTestCase {
    func testResetWindowSizeRestoresDefaultWidth() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 520, height: 300))

        controller.recordUserResizedWindowSize(window.frame.size)
        controller.resetWindowSize()

        XCTAssertEqual(window.frame.width, CGFloat(store.preferences.panelWidth), accuracy: 0.5)
    }

    func testNarrowManualWidthSurvivesDeleteAndCompletionResizes() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 350, height: 300))

        controller.recordUserResizedWindowSize(window.frame.size)
        controller.testingSelectTask(at: 5)

        let narrowWidth = window.frame.width
        controller.testingDeleteSelected()
        XCTAssertEqual(window.frame.width, narrowWidth, accuracy: 0.5)

        let completionController = TodoViewController(store: seededStore(active: ["A", "B", "C", "D", "E", "F"]))
        completionController.testingLoadView()
        let completionWindow = completionController.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 350, height: 300))

        completionController.recordUserResizedWindowSize(completionWindow.frame.size)
        completionController.testingSelectTask(at: 5)

        let completionWidth = completionWindow.frame.width
        completionController.testingCompleteSelected()
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertEqual(completionWindow.frame.width, completionWidth, accuracy: 0.5)
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

        let initialWidth = window.frame.width
        let initialHeight = window.frame.height
        controller.testingTypeIntoCurrentEditor("")
        let convertedHeight = window.frame.height

        XCTAssertEqual(controller.testingSnapshot().selected, .taskDraft)
        XCTAssertLessThan(convertedHeight, initialHeight - 20)
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)

        XCTAssertTrue(controller.moveUp())

        let collapsedHeight = window.frame.height
        XCTAssertEqual(collapsedHeight, convertedHeight, accuracy: 0.5)
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
    }

    func testDeleteSelectedTaskShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 5)

        let initialWidth = window.frame.width
        let initialHeight = window.frame.height
        controller.testingDeleteSelected()

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
    }

    func testDeleteSelectedTaskRangeShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F", "G"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTaskRange([5, 6])

        let initialWidth = window.frame.width
        let initialHeight = window.frame.height
        controller.testingDeleteSelected()

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
    }

    func testCompleteSelectedTaskShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 5)

        let initialWidth = window.frame.width
        let initialHeight = window.frame.height
        controller.testingCompleteSelected()
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
    }

    func testCompleteSelectedTaskViaCheckboxShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTask(at: 5)

        let initialWidth = window.frame.width
        let initialHeight = window.frame.height
        controller.testingCompleteSelectedViaCheckbox()
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
    }

    func testCompleteSelectedTaskRangeShrinksRealWindowFrame() {
        let store = seededStore(active: ["A", "B", "C", "D", "E", "F", "G"])
        let controller = TodoViewController(store: store)
        controller.testingLoadView()
        let window = controller.testingAttachWindow(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        controller.resetWindowSize()
        controller.testingSelectTaskRange([5, 6])

        let initialWidth = window.frame.width
        let initialHeight = window.frame.height
        controller.testingCompleteSelected()
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))

        XCTAssertLessThan(window.frame.height, initialHeight - 20)
        XCTAssertEqual(window.frame.width, initialWidth, accuracy: 0.5)
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

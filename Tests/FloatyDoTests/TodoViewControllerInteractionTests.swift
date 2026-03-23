import XCTest
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
        let store = seededStore(["A", "B", "C"])
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
        let store = seededStore(["A", "B", "C"])
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
        let store = seededStore(["A", "B", "C"])
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

    private func seededStore(_ items: [String]) -> TodoStore {
        let store = TodoStore()
        items.forEach { store.add($0) }
        return store
    }
}

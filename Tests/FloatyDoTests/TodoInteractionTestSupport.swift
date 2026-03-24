import AppKit
import XCTest
@testable import FloatyDoLib

@MainActor
class TodoInteractionTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "floatydo.items")
        UserDefaults.standard.removeObject(forKey: "floatydo.archived")
        UserDefaults.standard.removeObject(forKey: "floatydo.preferences")
    }

    func seededStore(active items: [String], archived: [String] = []) -> TodoStore {
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

import XCTest
@testable import FloatyDoLib

final class TodoStoreTests: XCTestCase {

    // Use a fresh store for each test (clear UserDefaults state)
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "floatydo.items")
        UserDefaults.standard.removeObject(forKey: "floatydo.archived")
        UserDefaults.standard.removeObject(forKey: "floatydo.preferences")
        UserDefaults.standard.removeObject(forKey: "floatydo.completedTodoCount")
        UserDefaults.standard.removeObject(forKey: "floatydo.hasRequestedRatingPrompt")
    }

    // MARK: - Basic add/archive/restore

    func testAddItem() {
        let store = TodoStore()
        store.add("Buy milk")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].text, "Buy milk")
        XCTAssertFalse(store.items[0].isDone)
    }

    func testAddTrimsWhitespace() {
        let store = TodoStore()
        store.add("  hello  ")
        XCTAssertEqual(store.items[0].text, "hello")
    }

    func testAddEmptyStringIsRejected() {
        let store = TodoStore()
        store.add("")
        store.add("   ")
        XCTAssertEqual(store.items.count, 0)
    }

    func testAddRespectsMaxItems() {
        let store = TodoStore()
        for i in 0..<TodoStore.maxItems {
            store.add("Item \(i)")
        }
        XCTAssertEqual(store.items.count, TodoStore.maxItems)
        store.add("One more")
        XCTAssertEqual(store.items.count, TodoStore.maxItems, "Should not exceed maxItems")
    }

    func testInsertItemAtSpecificIndex() {
        let store = TodoStore()
        store.add("A")
        store.add("C")

        let inserted = store.insert("B", at: 1)

        XCTAssertNotNil(inserted)
        XCTAssertEqual(store.items.map(\.text), ["A", "B", "C"])
    }

    func testInsertClampsOutOfBoundsIndex() {
        let store = TodoStore()
        store.add("A")
        store.add("B")

        _ = store.insert("C", at: 99)
        XCTAssertEqual(store.items.map(\.text), ["A", "B", "C"])

        _ = store.insert("Start", at: -10)
        XCTAssertEqual(store.items.map(\.text), ["Start", "A", "B", "C"])
    }

    func testInitPrunesWhitespaceOnlyPersistedItems() throws {
        let storedItems = [TodoItem(text: "Keep"), TodoItem(text: "   ")]
        let storedArchivedItems = [TodoItem(text: "\n\t"), TodoItem(text: "Archived")]
        let encoder = JSONEncoder()
        UserDefaults.standard.set(try encoder.encode(storedItems), forKey: "floatydo.items")
        UserDefaults.standard.set(try encoder.encode(storedArchivedItems), forKey: "floatydo.archived")

        let store = TodoStore()

        XCTAssertEqual(store.items.map(\.text), ["Keep"])
        XCTAssertEqual(store.archivedItems.map(\.text), ["Archived"])
    }

    // MARK: - Archive

    func testArchiveMovesItemFromItemsToArchived() {
        let store = TodoStore()
        store.add("Task A")
        store.add("Task B")
        store.add("Task C")
        let itemB = store.items[1]

        store.archive(itemB)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.map(\.text), ["Task A", "Task C"])
        XCTAssertEqual(store.archivedItems.count, 1)
        XCTAssertEqual(store.archivedItems[0].text, "Task B")
        XCTAssertTrue(store.archivedItems[0].isDone)
    }

    func testArchiveFirstItem() {
        let store = TodoStore()
        store.add("First")
        store.add("Second")
        store.add("Third")
        let first = store.items[0]

        store.archive(first)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.map(\.text), ["Second", "Third"])
        XCTAssertEqual(store.archivedItems.count, 1)
        XCTAssertEqual(store.archivedItems[0].text, "First")
    }

    func testArchiveLastItem() {
        let store = TodoStore()
        store.add("First")
        store.add("Second")
        store.add("Third")
        let last = store.items[2]

        store.archive(last)

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items.map(\.text), ["First", "Second"])
        XCTAssertEqual(store.archivedItems[0].text, "Third")
    }

    func testArchiveOnlyItem() {
        let store = TodoStore()
        store.add("Solo")
        let solo = store.items[0]

        store.archive(solo)

        XCTAssertEqual(store.items.count, 0)
        XCTAssertEqual(store.archivedItems.count, 1)
        XCTAssertEqual(store.archivedItems[0].text, "Solo")
    }

    func testArchiveNonexistentItemIsNoOp() {
        let store = TodoStore()
        store.add("Exists")
        let fake = TodoItem(text: "Fake")

        store.archive(fake)

        XCTAssertEqual(store.items.count, 1, "Original item should still be there")
        XCTAssertEqual(store.archivedItems.count, 0, "Nothing should be archived")
    }

    func testArchiveAlreadyArchivedItemIsNoOp() {
        let store = TodoStore()
        store.add("Task")
        let item = store.items[0]

        store.archive(item)
        XCTAssertEqual(store.items.count, 0)
        XCTAssertEqual(store.archivedItems.count, 1)

        // Try archiving again with the same item reference
        store.archive(item)
        XCTAssertEqual(store.items.count, 0, "Should still be 0")
        XCTAssertEqual(store.archivedItems.count, 1, "Should still be 1 — no duplicate")
    }

    // MARK: - Sequential archiving (simulates rapid cmd+return)

    func testArchiveSequentialItems() {
        let store = TodoStore()
        store.add("A")
        store.add("B")
        store.add("C")
        store.add("D")

        // Archive first item, then check state
        let a = store.items[0]
        store.archive(a)
        XCTAssertEqual(store.items.map(\.text), ["B", "C", "D"])

        // Archive what's now at index 0 (was "B")
        let b = store.items[0]
        store.archive(b)
        XCTAssertEqual(store.items.map(\.text), ["C", "D"])

        // Archive at index 1 (D)
        let d = store.items[1]
        store.archive(d)
        XCTAssertEqual(store.items.map(\.text), ["C"])

        // Archive last
        let c = store.items[0]
        store.archive(c)
        XCTAssertEqual(store.items.count, 0)
        XCTAssertEqual(store.archivedItems.count, 4)
    }

    func testArchiveMiddleItemPreservesOrder() {
        let store = TodoStore()
        for i in 0..<5 {
            store.add("Item \(i)")
        }

        // Archive index 2 ("Item 2")
        let item2 = store.items[2]
        store.archive(item2)

        XCTAssertEqual(store.items.map(\.text), ["Item 0", "Item 1", "Item 3", "Item 4"])
        XCTAssertEqual(store.archivedItems.map(\.text), ["Item 2"])
    }

    func testRatingPromptBecomesPendingAfterTenCompletedTodos() {
        let store = TodoStore()
        for index in 0..<10 {
            store.add("Item \(index)")
        }

        for _ in 0..<9 {
            store.archive(store.items[0])
            XCTAssertFalse(store.consumePendingRatingPromptRequest())
        }

        store.archive(store.items[0])

        XCTAssertTrue(store.consumePendingRatingPromptRequest())
        XCTAssertFalse(store.consumePendingRatingPromptRequest())
    }

    func testRatingPromptStatePersistsAcrossStoreInstances() {
        let store = TodoStore()
        for index in 0..<10 {
            store.add("Item \(index)")
        }
        for _ in 0..<10 {
            store.archive(store.items[0])
        }

        let reloadedStore = TodoStore()

        XCTAssertTrue(reloadedStore.consumePendingRatingPromptRequest())
        XCTAssertFalse(reloadedStore.consumePendingRatingPromptRequest())
    }

    // MARK: - Restore

    func testRestore() {
        let store = TodoStore()
        store.add("Task")
        let item = store.items[0]
        store.archive(item)
        XCTAssertEqual(store.items.count, 0)

        store.restore(store.archivedItems[0])
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].text, "Task")
        XCTAssertFalse(store.items[0].isDone)
        XCTAssertEqual(store.archivedItems.count, 0)
    }

    func testRestoreRespectsMaxItems() {
        let store = TodoStore()
        store.add("Archived")
        let archivedItem = store.items[0]
        store.archive(archivedItem)
        let archivedID = store.archivedItems[0].id

        for i in 0..<TodoStore.maxItems {
            store.add("Item \(i)")
        }

        store.restore(id: archivedID)

        XCTAssertEqual(store.items.count, TodoStore.maxItems)
        XCTAssertEqual(store.archivedItems.count, 1)
        XCTAssertEqual(store.archivedItems[0].text, "Archived")
    }

    // MARK: - Delete

    func testDelete() {
        let store = TodoStore()
        store.add("A")
        store.add("B")
        store.add("C")

        store.delete(store.items[1])
        XCTAssertEqual(store.items.map(\.text), ["A", "C"])
    }

    func testDeleteArchived() {
        let store = TodoStore()
        store.add("A")
        let item = store.items[0]
        store.archive(item)

        store.deleteArchived(store.archivedItems[0])
        XCTAssertEqual(store.archivedItems.count, 0)
    }

    func testUpdateTextByID() {
        let store = TodoStore()
        store.add("Original")

        let itemID = store.items[0].id
        store.updateText(for: itemID, to: "Updated")

        XCTAssertEqual(store.items[0].text, "Updated")
    }

    func testMoveItemToEarlierIndex() {
        let store = TodoStore()
        store.add("A")
        store.add("B")
        store.add("C")

        store.moveItem(id: store.items[2].id, to: 0)

        XCTAssertEqual(store.items.map(\.text), ["C", "A", "B"])
    }

    func testMoveItemToLaterIndex() {
        let store = TodoStore()
        store.add("A")
        store.add("B")
        store.add("C")
        store.add("D")

        store.moveItem(id: store.items[0].id, to: 2)

        XCTAssertEqual(store.items.map(\.text), ["B", "C", "A", "D"])
    }

    func testReorderItemsByIDs() {
        let store = TodoStore()
        store.add("A")
        store.add("B")
        store.add("C")

        let reorderedIDs = [store.items[2].id, store.items[0].id, store.items[1].id]
        store.reorderItems(by: reorderedIDs)

        XCTAssertEqual(store.items.map(\.text), ["C", "A", "B"])
    }

    // MARK: - Simulate cmd+return completion flow

    /// This simulates exactly what the view controller does on cmd+return:
    /// 1. Captures item reference at selectedIndex
    /// 2. (animation plays)
    /// 3. Calls store.archive(item)
    /// 4. Adjusts selectedIndex
    /// 5. Rebuilds rows based on new store state
    func testCmdReturnCompletionFlow_firstItem() {
        let store = TodoStore()
        store.add("Task 1")
        store.add("Task 2")
        store.add("Task 3")

        let selectedIndex = 0
        let item = store.items[selectedIndex]

        // Simulate archive
        store.archive(item)

        // Simulate selectedIndex adjustment
        var newSelectedIndex: Int
        if selectedIndex < store.items.count {
            newSelectedIndex = selectedIndex
        } else {
            newSelectedIndex = store.items.count
        }

        // Simulate rowCount = min(items.count + 3, maxItems)
        let rowCount = min(store.items.count + 3, TodoStore.maxItems)

        XCTAssertEqual(store.items.map(\.text), ["Task 2", "Task 3"])
        XCTAssertEqual(newSelectedIndex, 0)
        XCTAssertEqual(rowCount, 5)
    }

    func testCmdReturnCompletionFlow_lastItem() {
        let store = TodoStore()
        store.add("Task 1")
        store.add("Task 2")
        store.add("Task 3")

        let selectedIndex = 2
        let item = store.items[selectedIndex]

        store.archive(item)

        var newSelectedIndex: Int
        if selectedIndex < store.items.count {
            newSelectedIndex = selectedIndex
        } else {
            newSelectedIndex = store.items.count // input row
        }

        let rowCount = min(store.items.count + 3, TodoStore.maxItems)

        XCTAssertEqual(store.items.map(\.text), ["Task 1", "Task 2"])
        XCTAssertEqual(newSelectedIndex, 2, "Should land on input row (items.count)")
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(rowCount, 5)
    }

    func testCmdReturnCompletionFlow_onlyItem() {
        let store = TodoStore()
        store.add("Solo task")

        let selectedIndex = 0
        let item = store.items[selectedIndex]

        store.archive(item)

        var newSelectedIndex: Int
        if selectedIndex < store.items.count {
            newSelectedIndex = selectedIndex
        } else {
            newSelectedIndex = store.items.count
        }

        let rowCount = min(store.items.count + 3, TodoStore.maxItems)

        XCTAssertEqual(store.items.count, 0)
        XCTAssertEqual(newSelectedIndex, 0, "Should land on input row (index 0)")
        XCTAssertEqual(rowCount, 3, "Empty list should show 3 rows")
    }

    /// Simulates completing items rapidly at index 0 each time (like the list shifts up)
    func testRapidCompletionAtIndex0() {
        let store = TodoStore()
        store.add("A")
        store.add("B")
        store.add("C")
        store.add("D")
        store.add("E")

        for expectedRemaining in stride(from: 4, through: 0, by: -1) {
            let item = store.items[0]
            store.archive(item)
            XCTAssertEqual(store.items.count, expectedRemaining,
                           "After archiving, should have \(expectedRemaining) items")

            let rowCount = min(store.items.count + 3, TodoStore.maxItems)
            XCTAssertGreaterThanOrEqual(rowCount, 3, "Should always show at least 3 rows")
        }

        XCTAssertEqual(store.archivedItems.count, 5)
        XCTAssertEqual(store.archivedItems.map(\.text), ["E", "D", "C", "B", "A"])
    }

    // MARK: - Edge case: stale item reference

    /// The animation captures an item reference before archive. If the user somehow
    /// modifies the list during the animation, the stale reference might not match.
    func testArchiveWithStaleReference() {
        let store = TodoStore()
        store.add("Original")
        let capturedItem = store.items[0]

        // Simulate user editing the text during animation
        store.updateText(for: capturedItem.id, to: "Modified")

        // The captured item still has the original UUID, so archive should work
        store.archive(capturedItem)
        XCTAssertEqual(store.items.count, 0, "Should find item by ID, not text")
        XCTAssertEqual(store.archivedItems.count, 1)
        // The archived version should have the modified text (since items[0] was modified in place)
        XCTAssertEqual(store.archivedItems[0].text, "Modified")
    }

    // MARK: - rowCount calculation

    func testRowCountCalculation() {
        // rowCount = min(items.count + 3, maxItems)
        let testCases: [(itemCount: Int, expected: Int)] = [
            (0, 3),
            (1, 4),
            (2, 5),
            (3, 6),
            (5, 8),
            (7, 10),
            (8, 10),  // capped at maxItems
            (9, 10),
            (10, 10),
        ]

        for tc in testCases {
            let rowCount = min(tc.itemCount + 3, TodoStore.maxItems)
            XCTAssertEqual(rowCount, tc.expected,
                           "With \(tc.itemCount) items, rowCount should be \(tc.expected)")
        }
    }

    /// After archiving, rowCount decreases but the window never shrinks.
    /// This means there's empty space at the bottom. Verify the row count is correct.
    func testRowCountAfterArchive() {
        let store = TodoStore()
        for i in 0..<7 {
            store.add("Item \(i)")
        }
        // Initial rowCount = min(7+3, 10) = 10
        XCTAssertEqual(min(store.items.count + 3, TodoStore.maxItems), 10)

        store.archive(store.items[0])
        // After: items=6, rowCount = min(6+3, 10) = 9
        XCTAssertEqual(store.items.count, 6)
        XCTAssertEqual(min(store.items.count + 3, TodoStore.maxItems), 9)

        store.archive(store.items[0])
        // After: items=5, rowCount = min(5+3, 10) = 8
        XCTAssertEqual(store.items.count, 5)
        XCTAssertEqual(min(store.items.count + 3, TodoStore.maxItems), 8)
    }

    // MARK: - Persistence

    func testPersistence() {
        let store1 = TodoStore()
        store1.add("Persistent task")
        store1.archive(store1.items[0])

        // Create a new store — should load from UserDefaults
        let store2 = TodoStore()
        XCTAssertEqual(store2.items.count, 0)
        XCTAssertEqual(store2.archivedItems.count, 1)
        XCTAssertEqual(store2.archivedItems[0].text, "Persistent task")
    }

    func testPreferencesPersistence() {
        let store1 = TodoStore()
        let updatedPreferences = AppPreferences(
            rowHeight: 44,
            panelWidth: 460,
            hoverHighlightsEnabled: false,
            animationPreset: .snappy,
            snapPadding: 32,
            theme: .theme6,
            fontStyle: .rounded,
            fontSize: 16,
            cornerRadius: 18,
            blurEnabled: false,
            globalHotkey: GlobalHotkey(
                keyCode: 18,
                command: true,
                option: false,
                control: false,
                shift: true
            )
        )
        store1.updatePreferences(updatedPreferences)

        let store2 = TodoStore()
        XCTAssertEqual(store2.preferences, updatedPreferences)
    }

    func testPreferencesClampToDiscreteFontSizeAndVisibleRowRadius() {
        let store = TodoStore()
        let updatedPreferences = AppPreferences(
            rowHeight: 36,
            panelWidth: 400,
            hoverHighlightsEnabled: true,
            animationPreset: .balanced,
            snapPadding: 40,
            theme: .theme1,
            fontStyle: .system,
            fontSize: 13.6,
            cornerRadius: 99
        )

        store.updatePreferences(updatedPreferences)

        XCTAssertEqual(store.preferences.fontSize, 14)
        XCTAssertEqual(store.preferences.cornerRadius, 16)
        XCTAssertEqual(store.preferences.snapPadding, 40)
    }

    func testPreferencesClampWindowOpacityAndIgnoreLegacyGlassFields() throws {
        let store = TodoStore()
        let payload: [String: Any] = [
            "rowHeight": 36.0,
            "panelWidth": 400.0,
            "hoverHighlightsEnabled": true,
            "animationPreset": "balanced",
            "snapPadding": 40.0,
            "themeColor": ["red": 0.0784313725, "green": 0.0784313725, "blue": 0.1215686275, "alpha": 1.0],
            "fontStyle": "system",
            "fontSize": 14.0,
            "cornerRadius": 10.0,
            "blurEnabled": false,
            "windowOpacity": 0.2,
            "blurMaterial": "popover",
            "glassEnabled": true
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let updatedPreferences = try JSONDecoder().decode(AppPreferences.self, from: data)

        store.updatePreferences(updatedPreferences)

        XCTAssertEqual(store.preferences.windowOpacity, 0.3)
        XCTAssertFalse(store.preferences.blurEnabled)
        XCTAssertEqual(store.preferences.theme, .theme1)
    }

    func testLegacyPreferencesDecodeUsesNewFieldDefaults() throws {
        let legacyPreferences: [String: Any] = [
            "rowHeight": 42.0,
            "panelWidth": 430.0,
            "hoverHighlightsEnabled": false,
            "animationPreset": "relaxed",
            "snapPadding": 18.0
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyPreferences)
        UserDefaults.standard.set(data, forKey: "floatydo.preferences")

        let store = TodoStore()

        XCTAssertEqual(store.preferences.rowHeight, 42.0)
        XCTAssertEqual(store.preferences.panelWidth, 430.0)
        XCTAssertFalse(store.preferences.hoverHighlightsEnabled)
        XCTAssertEqual(store.preferences.animationPreset, .relaxed)
        XCTAssertEqual(store.preferences.snapPadding, 32.0)
        XCTAssertEqual(store.preferences.theme, .theme1)
        XCTAssertEqual(store.preferences.fontStyle, .system)
        XCTAssertEqual(store.preferences.fontSize, 14.0)
        XCTAssertEqual(store.preferences.cornerRadius, 10.0)
        XCTAssertFalse(store.preferences.blurEnabled)
        XCTAssertEqual(store.preferences.windowOpacity, 1.0)
        XCTAssertEqual(store.preferences.globalHotkey, .defaultToggle)
    }

    func testRestoreStateReplacesItemsArchiveAndPreferences() {
        let store = TodoStore()
        store.add("Old")
        store.archive(store.items[0])

        let restoredItems = [TodoItem(text: "A"), TodoItem(text: "B")]
        let restoredArchive = [TodoItem(text: "Archived")]
        let restoredPreferences = AppPreferences(
            rowHeight: 40,
            panelWidth: 420,
            hoverHighlightsEnabled: false,
            animationPreset: .snappy,
            snapPadding: 48,
            theme: .theme4,
            fontStyle: .rounded,
            fontSize: 15,
            cornerRadius: 14
        )

        store.restoreState(
            items: restoredItems,
            archivedItems: restoredArchive,
            preferences: restoredPreferences
        )

        XCTAssertEqual(store.items, restoredItems)
        XCTAssertEqual(store.archivedItems, restoredArchive)
        XCTAssertEqual(store.preferences, restoredPreferences)
    }

    func testRestoreStateClampsPreferences() {
        let store = TodoStore()
        let oversizedPreferences = AppPreferences(
            rowHeight: 36,
            panelWidth: 420,
            hoverHighlightsEnabled: true,
            animationPreset: .balanced,
            snapPadding: 12,
            theme: .theme1,
            fontStyle: .system,
            fontSize: 14.4,
            cornerRadius: 99
        )

        store.restoreState(items: [], archivedItems: [], preferences: oversizedPreferences)

        XCTAssertEqual(store.preferences.snapPadding, 32)
        XCTAssertEqual(store.preferences.fontSize, 14)
        XCTAssertEqual(store.preferences.cornerRadius, 16)
        XCTAssertEqual(store.preferences.windowOpacity, 1.0)
    }
}

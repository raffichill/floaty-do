import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.floatydo", category: "TodoStore")

public struct TodoItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var text: String
    public var isDone: Bool

    public init(text: String) {
        self.id = UUID()
        self.text = text
        self.isDone = false
    }
}

public final class TodoStore: ObservableObject {
    private static let key = "floatydo.items"
    private static let archiveKey = "floatydo.archived"
    private static let preferencesKey = "floatydo.preferences"
    public static let maxItems = 10

    @Published public private(set) var items: [TodoItem] = [] {
        didSet { save() }
    }

    @Published public private(set) var archivedItems: [TodoItem] = [] {
        didSet { saveArchive() }
    }

    @Published public private(set) var preferences: AppPreferences = .default {
        didSet { savePreferences() }
    }

    public init() {
        load()
        loadArchive()
        loadPreferences()
        migrateCompletedItems()
        pruneWhitespaceOnlyItems()
    }

    public func add(_ text: String) {
        _ = insert(text, at: items.count)
    }

    @discardableResult
    public func insert(_ text: String, at index: Int) -> TodoItem? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, items.count < Self.maxItems else {
            logger.warning("add REJECTED: text=\"\(text)\", items.count=\(self.items.count)")
            return nil
        }
        let item = TodoItem(text: trimmed)
        let insertionIndex = max(0, min(index, items.count))
        items.insert(item, at: insertionIndex)
        logger.debug("insert: \"\(trimmed)\", at=\(insertionIndex), items.count=\(self.items.count)")
        return item
    }

    public func updateText(for id: UUID, to text: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].text = text
    }

    public func archive(_ item: TodoItem) {
        archive(id: item.id)
    }

    public func archive(id: UUID) {
        logger.debug("archive CALLED: id=\(id), items.count=\(self.items.count)")
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            logger.error("archive FAILED: item not found in items! id=\(id)")
            logger.error("  current items: \(self.items.map { "\($0.text) (\($0.id))" })")
            return
        }
        var archived = items.remove(at: idx)
        archived.isDone = true
        archivedItems.insert(archived, at: 0)
        logger.debug("archive DONE: removed at idx=\(idx), items.count=\(self.items.count), archived.count=\(self.archivedItems.count)")
    }

    public func restore(_ item: TodoItem) {
        restore(id: item.id)
    }

    public func restore(id: UUID) {
        guard items.count < Self.maxItems else { return }
        guard let idx = archivedItems.firstIndex(where: { $0.id == id }) else { return }
        var restored = archivedItems.remove(at: idx)
        restored.isDone = false
        items.append(restored)
        logger.debug("restore: \"\(restored.text)\", items.count=\(self.items.count)")
    }

    public func delete(_ item: TodoItem) {
        deleteItem(id: item.id)
    }

    public func deleteItem(id: UUID) {
        logger.debug("delete id=\(id), items before=\(self.items.count)")
        items.removeAll { $0.id == id }
        logger.debug("delete done: items after=\(self.items.count)")
    }

    public func deleteArchived(_ item: TodoItem) {
        deleteArchived(id: item.id)
    }

    public func deleteArchived(id: UUID) {
        archivedItems.removeAll { $0.id == id }
    }

    public func moveItem(id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let clampedDestination = max(0, min(destinationIndex, items.count - 1))
        guard sourceIndex != clampedDestination else { return }
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: clampedDestination)
    }

    public func reorderItems(by ids: [UUID]) {
        guard ids.count == items.count else { return }
        let currentItemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let reordered = ids.compactMap { currentItemsByID[$0] }
        guard reordered.count == items.count else { return }
        items = reordered
    }

    public func updatePreferences(_ newPreferences: AppPreferences) {
        let clampedRowHeight = min(max(newPreferences.rowHeight, LayoutMetrics.minRowHeight), LayoutMetrics.maxRowHeight)
        let clampedPanelWidth = min(max(newPreferences.panelWidth, LayoutMetrics.minPanelWidth), LayoutMetrics.maxPanelWidth)
        let clampedCornerRadius = min(
            max(newPreferences.cornerRadius, LayoutMetrics.minCornerRadius),
            LayoutMetrics.maximumCornerRadius(forRowHeight: clampedRowHeight)
        )
        let clamped = AppPreferences(
            rowHeight: clampedRowHeight,
            panelWidth: clampedPanelWidth,
            hoverHighlightsEnabled: newPreferences.hoverHighlightsEnabled,
            animationPreset: newPreferences.animationPreset,
            snapPadding: max(0, newPreferences.snapPadding),
            themeColor: newPreferences.themeColor.clamped(),
            fontStyle: newPreferences.fontStyle,
            fontSize: LayoutMetrics.nearestFontSizeOption(to: newPreferences.fontSize),
            cornerRadius: clampedCornerRadius
        )
        preferences = clamped
    }

    // Move any already-completed items into the archive on first launch
    private func migrateCompletedItems() {
        let completed = items.filter { $0.isDone }
        guard !completed.isEmpty else { return }
        items.removeAll { $0.isDone }
        archivedItems.insert(contentsOf: completed, at: 0)
    }

    private func pruneWhitespaceOnlyItems() {
        items.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        archivedItems.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func saveArchive() {
        if let data = try? JSONEncoder().encode(archivedItems) {
            UserDefaults.standard.set(data, forKey: Self.archiveKey)
        }
    }

    private func savePreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.preferencesKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data)
        else { return }
        items = decoded
    }

    private func loadArchive() {
        guard let data = UserDefaults.standard.data(forKey: Self.archiveKey),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data)
        else { return }
        archivedItems = decoded
    }

    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
              let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return }
        preferences = decoded
    }
}

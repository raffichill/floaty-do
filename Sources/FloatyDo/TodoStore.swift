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
    public static let maxItems = 10

    @Published public var items: [TodoItem] = [] {
        didSet { save() }
    }

    @Published public var archivedItems: [TodoItem] = [] {
        didSet { saveArchive() }
    }

    public init() {
        load()
        loadArchive()
        migrateCompletedItems()
    }

    public func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, items.count < Self.maxItems else {
            logger.warning("add REJECTED: text=\"\(text)\", items.count=\(self.items.count)")
            return
        }
        items.append(TodoItem(text: trimmed))
        logger.debug("add: \"\(trimmed)\", items.count=\(self.items.count)")
    }

    public func archive(_ item: TodoItem) {
        logger.debug("archive CALLED: item=\"\(item.text)\" id=\(item.id), items.count=\(self.items.count)")
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else {
            logger.error("archive FAILED: item not found in items! id=\(item.id), text=\"\(item.text)\"")
            logger.error("  current items: \(self.items.map { "\($0.text) (\($0.id))" })")
            return
        }
        var archived = items.remove(at: idx)
        archived.isDone = true
        archivedItems.insert(archived, at: 0)
        logger.debug("archive DONE: removed at idx=\(idx), items.count=\(self.items.count), archived.count=\(self.archivedItems.count)")
    }

    public func restore(_ item: TodoItem) {
        guard let idx = archivedItems.firstIndex(where: { $0.id == item.id }) else { return }
        var restored = archivedItems.remove(at: idx)
        restored.isDone = false
        items.append(restored)
        logger.debug("restore: \"\(restored.text)\", items.count=\(self.items.count)")
    }

    public func delete(_ item: TodoItem) {
        logger.debug("delete: \"\(item.text)\", items before=\(self.items.count)")
        items.removeAll { $0.id == item.id }
        logger.debug("delete done: items after=\(self.items.count)")
    }

    public func deleteArchived(_ item: TodoItem) {
        archivedItems.removeAll { $0.id == item.id }
    }

    // Move any already-completed items into the archive on first launch
    private func migrateCompletedItems() {
        let completed = items.filter { $0.isDone }
        guard !completed.isEmpty else { return }
        items.removeAll { $0.isDone }
        archivedItems.insert(contentsOf: completed, at: 0)
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
}

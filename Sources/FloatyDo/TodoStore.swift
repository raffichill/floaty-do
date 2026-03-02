import Foundation
import Combine

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.isDone = false
    }
}

final class TodoStore: ObservableObject {
    private static let key = "floatydo.items"
    private static let archiveKey = "floatydo.archived"
    static let maxItems = 10

    @Published var items: [TodoItem] = [] {
        didSet { save() }
    }

    @Published var archivedItems: [TodoItem] = [] {
        didSet { saveArchive() }
    }

    init() {
        load()
        loadArchive()
        migrateCompletedItems()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, items.count < Self.maxItems else { return }
        items.append(TodoItem(text: trimmed))
    }

    func archive(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var archived = items.remove(at: idx)
        archived.isDone = true
        archivedItems.insert(archived, at: 0)
    }

    func restore(_ item: TodoItem) {
        guard let idx = archivedItems.firstIndex(where: { $0.id == item.id }) else { return }
        var restored = archivedItems.remove(at: idx)
        restored.isDone = false
        items.append(restored)
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
    }

    func deleteArchived(_ item: TodoItem) {
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

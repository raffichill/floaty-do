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
    static let maxItems = 10

    @Published var items: [TodoItem] = [] {
        didSet { save() }
    }

    init() { load() }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, items.count < Self.maxItems else { return }
        items.append(TodoItem(text: trimmed))
    }

    func toggle(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isDone.toggle()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data)
        else { return }
        items = decoded
    }
}

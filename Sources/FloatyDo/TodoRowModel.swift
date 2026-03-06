import Foundation

enum TodoRowID: Hashable {
    case taskItem(UUID)
    case archiveItem(UUID)
    case taskInput
    case taskFiller(Int)
    case archiveFiller(Int)
}

enum TodoRowKind: Equatable {
    case taskItem(TodoItem)
    case archiveItem(TodoItem)
    case taskInput
    case filler
}

struct TodoRowModel: Equatable {
    let id: TodoRowID
    let kind: TodoRowKind
    let text: String
    let isDone: Bool
    let isEditable: Bool
    let isSelectable: Bool
    let canComplete: Bool
    let canDrag: Bool
    let circleOpacity: Double
    let textOpacity: Double
    let showsStrikethrough: Bool

    var itemID: UUID? {
        switch kind {
        case .taskItem(let item), .archiveItem(let item):
            return item.id
        case .taskInput, .filler:
            return nil
        }
    }
}

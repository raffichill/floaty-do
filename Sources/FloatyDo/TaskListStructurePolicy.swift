import Foundation

struct TaskDraftState: Equatable {
    var insertionIndex: Int
    var text: String
    var isStructuralDraft = false

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedText.isEmpty
    }
}

enum TaskListHeightResizeMode: Equatable {
    case respectUserFloor
    case fitActiveTaskRows(animated: Bool)

    var usesStructuralFit: Bool {
        if case .fitActiveTaskRows = self {
            return true
        }
        return false
    }

    var shouldAnimateWindowResize: Bool {
        switch self {
        case .respectUserFloor:
            return true
        case .fitActiveTaskRows(let animated):
            return animated
        }
    }
}

enum TaskListStructurePolicy {
    static let minimumVisibleRows = 5
    static let runwayRows = 3

    static func targetVisibleTaskRowCount(activeTaskCount: Int) -> Int {
        max(minimumVisibleRows, min(activeTaskCount + runwayRows, TodoStore.maxItems))
    }

    static func shouldCollapseEmptyDraft(
        _ draft: TaskDraftState,
        defaultInsertionIndex: Int
    ) -> Bool {
        draft.isStructuralDraft || draft.insertionIndex != defaultInsertionIndex
    }

    static func isTerminalBottomDraft(
        _ draft: TaskDraftState,
        defaultInsertionIndex: Int
    ) -> Bool {
        draft.isEmpty && draft.insertionIndex == defaultInsertionIndex
    }
}

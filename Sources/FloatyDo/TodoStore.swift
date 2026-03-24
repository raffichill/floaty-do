import Foundation
import Combine

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
    private enum SaveDomain {
        case items
        case archive
        case preferences
    }

    private static let key = "floatydo.items"
    private static let archiveKey = "floatydo.archived"
    private static let preferencesKey = "floatydo.preferences"
    private static let minimumSnapPadding = 32.0
    public static let maxItems = 10
    private static let textSaveDebounceInterval: TimeInterval = 0.18

    @Published public private(set) var items: [TodoItem] = []

    @Published public private(set) var archivedItems: [TodoItem] = []

    @Published public private(set) var preferences: AppPreferences = .default

    private var pendingItemSaveWorkItem: DispatchWorkItem?
    private var pendingArchiveSaveWorkItem: DispatchWorkItem?
    private var pendingPreferencesSaveWorkItem: DispatchWorkItem?

    public init() {
        load()
        loadArchive()
        loadPreferences()
        migrateCompletedItems()
        pruneWhitespaceOnlyItems()
    }

    deinit {
        flushPendingSaves()
    }

    public func add(_ text: String) {
        _ = insert(text, at: items.count)
    }

    @discardableResult
    public func insert(_ text: String, at index: Int) -> TodoItem? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, items.count < Self.maxItems else { return nil }
        let item = TodoItem(text: trimmed)
        let insertionIndex = max(0, min(index, items.count))
        items.insert(item, at: insertionIndex)
        persistItemsImmediately()
        return item
    }

    public func updateText(for id: UUID, to text: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].text = text
        scheduleItemsSave()
    }

    public func archive(_ item: TodoItem) {
        archive(id: item.id)
    }

    public func archive(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var archived = items.remove(at: idx)
        archived.isDone = true
        archivedItems.insert(archived, at: 0)
        cancelScheduledSave(for: .items)
        persistItemsImmediately()
        persistArchiveImmediately()
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
        persistArchiveImmediately()
        persistItemsImmediately()
    }

    public func delete(_ item: TodoItem) {
        deleteItem(id: item.id)
    }

    public func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        cancelScheduledSave(for: .items)
        persistItemsImmediately()
    }

    public func deleteArchived(_ item: TodoItem) {
        deleteArchived(id: item.id)
    }

    public func deleteArchived(id: UUID) {
        archivedItems.removeAll { $0.id == id }
        persistArchiveImmediately()
    }

    public func moveItem(id: UUID, to destinationIndex: Int) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let clampedDestination = max(0, min(destinationIndex, items.count - 1))
        guard sourceIndex != clampedDestination else { return }
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: clampedDestination)
        persistItemsImmediately()
    }

    public func reorderItems(by ids: [UUID]) {
        guard ids.count == items.count else { return }
        let currentItemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let reordered = ids.compactMap { currentItemsByID[$0] }
        guard reordered.count == items.count else { return }
        items = reordered
        persistItemsImmediately()
    }

    public func updatePreferences(_ newPreferences: AppPreferences) {
        preferences = clampedPreferences(from: newPreferences)
        persistPreferencesImmediately()
    }

    public func restoreState(
        items: [TodoItem],
        archivedItems: [TodoItem],
        preferences: AppPreferences
    ) {
        cancelScheduledSave(for: .items)
        cancelScheduledSave(for: .archive)
        cancelScheduledSave(for: .preferences)

        self.items = items
        self.archivedItems = archivedItems
        self.preferences = clampedPreferences(from: preferences)

        saveItems()
        saveArchive()
        savePreferences()
    }

    public func flushPendingSaves() {
        pendingItemSaveWorkItem?.cancel()
        pendingItemSaveWorkItem = nil
        pendingArchiveSaveWorkItem?.cancel()
        pendingArchiveSaveWorkItem = nil
        pendingPreferencesSaveWorkItem?.cancel()
        pendingPreferencesSaveWorkItem = nil

        saveItems()
        saveArchive()
        savePreferences()
    }

    // Move any already-completed items into the archive on first launch
    private func migrateCompletedItems() {
        let completed = items.filter { $0.isDone }
        guard !completed.isEmpty else { return }
        items.removeAll { $0.isDone }
        archivedItems.insert(contentsOf: completed, at: 0)
        persistItemsImmediately()
        persistArchiveImmediately()
    }

    private func pruneWhitespaceOnlyItems() {
        let originalItemsCount = items.count
        let originalArchivedCount = archivedItems.count
        items.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        archivedItems.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if items.count != originalItemsCount {
            persistItemsImmediately()
        }
        if archivedItems.count != originalArchivedCount {
            persistArchiveImmediately()
        }
    }

    private func clampedPreferences(from newPreferences: AppPreferences) -> AppPreferences {
        let clampedRowHeight = min(max(newPreferences.rowHeight, LayoutMetrics.minRowHeight), LayoutMetrics.maxRowHeight)
        let clampedPanelWidth = min(max(newPreferences.panelWidth, LayoutMetrics.minPanelWidth), LayoutMetrics.maxPanelWidth)
        let clampedCornerRadius = min(
            max(newPreferences.cornerRadius, LayoutMetrics.minCornerRadius),
            LayoutMetrics.maximumCornerRadius(forRowHeight: clampedRowHeight)
        )
        let blurEnabled = newPreferences.blurEnabled
        let globalHotkey = newPreferences.globalHotkey.normalized
        return AppPreferences(
            rowHeight: clampedRowHeight,
            panelWidth: clampedPanelWidth,
            hoverHighlightsEnabled: newPreferences.hoverHighlightsEnabled,
            animationPreset: newPreferences.animationPreset,
            snapPadding: max(Self.minimumSnapPadding, newPreferences.snapPadding),
            theme: newPreferences.theme,
            fontStyle: newPreferences.fontStyle,
            fontSize: LayoutMetrics.nearestFontSizeOption(to: newPreferences.fontSize),
            cornerRadius: clampedCornerRadius,
            blurEnabled: blurEnabled,
            windowOpacity: min(max(newPreferences.windowOpacity, LayoutMetrics.minWindowOpacity), 1.0),
            globalHotkey: globalHotkey
        )
    }

    private func scheduleItemsSave() {
        scheduleSave(for: .items, delay: Self.textSaveDebounceInterval)
    }

    private func persistItemsImmediately() {
        cancelScheduledSave(for: .items)
        saveItems()
    }

    private func persistArchiveImmediately() {
        cancelScheduledSave(for: .archive)
        saveArchive()
    }

    private func persistPreferencesImmediately() {
        cancelScheduledSave(for: .preferences)
        savePreferences()
    }

    private func scheduleSave(for domain: SaveDomain, delay: TimeInterval) {
        cancelScheduledSave(for: domain)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            switch domain {
            case .items:
                self.saveItems()
                self.pendingItemSaveWorkItem = nil
            case .archive:
                self.saveArchive()
                self.pendingArchiveSaveWorkItem = nil
            case .preferences:
                self.savePreferences()
                self.pendingPreferencesSaveWorkItem = nil
            }
        }

        switch domain {
        case .items:
            pendingItemSaveWorkItem = workItem
        case .archive:
            pendingArchiveSaveWorkItem = workItem
        case .preferences:
            pendingPreferencesSaveWorkItem = workItem
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelScheduledSave(for domain: SaveDomain) {
        switch domain {
        case .items:
            pendingItemSaveWorkItem?.cancel()
            pendingItemSaveWorkItem = nil
        case .archive:
            pendingArchiveSaveWorkItem?.cancel()
            pendingArchiveSaveWorkItem = nil
        case .preferences:
            pendingPreferencesSaveWorkItem?.cancel()
            pendingPreferencesSaveWorkItem = nil
        }
    }

    private func saveItems() {
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
        preferences = clampedPreferences(from: decoded)
    }
}

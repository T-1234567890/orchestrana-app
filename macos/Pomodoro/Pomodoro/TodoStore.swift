import Foundation
import Combine
import SwiftUI

/// TodoStore manages the app's primary task data.
/// This is the source of truth for all tasks, whether synced with Reminders or not.
@MainActor
final class TodoStore: ObservableObject {
    @Published var items: [TodoItem] = []
    @Published private(set) var pendingItems: [TodoItem] = []
    @Published private(set) var completedItems: [TodoItem] = []
    
    private let storageKey = "com.pomodoro.todoItems"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private weak var planningStore: PlanningStore?
    
    init() {
        loadItems()
    }

    func attachPlanningStore(_ store: PlanningStore) {
        planningStore = store
        planningStore?.syncTasks(items)
    }
    
    // MARK: - CRUD Operations
    
    func addItem(_ item: TodoItem) {
        items.append(item)
        saveItems()
        rebuildDerivedState()
        planningStore?.upsertFromTask(item)
    }
    
    func updateItem(_ item: TodoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            saveItems()
            rebuildDerivedState()
            planningStore?.upsertFromTask(item)
        }
    }
    
    func deleteItem(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
        rebuildDerivedState()
        planningStore?.removeTaskPlan(for: item.id)
    }
    
    func deleteItems(at offsets: IndexSet) {
        let removedIDs: [UUID] = offsets.map { items[$0].id }
        items.remove(atOffsets: offsets)
        saveItems()
        rebuildDerivedState()
        for id in removedIDs {
            planningStore?.removeTaskPlan(for: id)
        }
    }
    
    func toggleCompletion(_ item: TodoItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updatedItem = items[index]
            updatedItem.markComplete(!updatedItem.isCompleted)
            items[index] = updatedItem
            saveItems()
            rebuildDerivedState()
            planningStore?.upsertFromTask(updatedItem)
        }
    }

    func setCompletion(itemID: UUID, isCompleted: Bool) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        var updatedItem = items[index]
        guard updatedItem.isCompleted != isCompleted else { return }
        updatedItem.markComplete(isCompleted)
        items[index] = updatedItem
        saveItems()
        rebuildDerivedState()
        planningStore?.upsertFromTask(updatedItem)
    }

    func setLocation(itemID: UUID, locationID: UUID?) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].locationID = locationID
        items[index].modifiedAt = Date()
        saveItems()
        rebuildDerivedState()
        planningStore?.upsertFromTask(items[index])
    }

    func addSubtask(to itemID: UUID, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        items[index].subtasks.append(TodoSubtask(title: trimmedTitle))
        items[index].modifiedAt = Date()
        saveItems()
        rebuildDerivedState()
        planningStore?.upsertFromTask(items[index])
    }

    func toggleSubtask(taskID: UUID, subtaskID: UUID) {
        guard let itemIndex = items.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = items[itemIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            return
        }

        items[itemIndex].subtasks[subtaskIndex].completed.toggle()
        items[itemIndex].modifiedAt = Date()
        saveItems()
        rebuildDerivedState()
        planningStore?.upsertFromTask(items[itemIndex])
    }

    func deleteSubtask(taskID: UUID, subtaskID: UUID) {
        guard let itemIndex = items.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        items[itemIndex].subtasks.removeAll { $0.id == subtaskID }
        items[itemIndex].modifiedAt = Date()
        saveItems()
        rebuildDerivedState()
        planningStore?.upsertFromTask(items[itemIndex])
    }
    
    var itemsWithRemindersSync: [TodoItem] {
        items.filter { $0.reminderIdentifier != nil }
    }
    
    // MARK: - Persistence
    
    private func saveItems() {
        if let encoded = try? encoder.encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadItems() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode([TodoItem].self, from: data) {
            items = decoded
            rebuildDerivedState()
            planningStore?.syncTasks(items)
        } else {
            rebuildDerivedState()
        }
    }

    private func rebuildDerivedState() {
        pendingItems = items.filter { !$0.isCompleted }
        completedItems = items
            .filter { $0.isCompleted }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }
    
    // MARK: - Reminders Integration
    
    /// Link a TodoItem to an Apple Reminders identifier
    func linkToReminder(itemId: UUID, remindersId: String) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].reminderIdentifier = remindersId
            items[index].syncStatus = .synced
            saveItems()
            rebuildDerivedState()
        }
    }
    
    /// Unlink a TodoItem from Apple Reminders
    func unlinkFromReminder(itemId: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].reminderIdentifier = nil
            items[index].syncStatus = .local
            saveItems()
            rebuildDerivedState()
        }
    }
    
    func linkToCalendarEvent(itemId: UUID, eventId: String) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].calendarEventIdentifier = eventId
            items[index].syncStatus = .synced
            saveItems()
            rebuildDerivedState()
            planningStore?.upsertFromTask(items[index])
        }
    }
    
    func unlinkFromCalendarEvent(itemId: UUID) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].calendarEventIdentifier = nil
            items[index].syncStatus = .local
            saveItems()
            rebuildDerivedState()
            planningStore?.upsertFromTask(items[index])
        }
    }
}

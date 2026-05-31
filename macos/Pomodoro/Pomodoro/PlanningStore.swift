import Foundation
import Combine
import EventKit
import SwiftUI

/// Single source of truth for tasks and scheduled items.
@MainActor
final class PlanningStore: ObservableObject {
    @Published private(set) var items: [PlanningItem] = []
    
    private let storageKey = "com.pomodoro.planningItems"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let eventStore = SharedEventStore.shared.eventStore
    
    init() {
        load()
    }
    
    // MARK: - CRUD (local tasks)
    
    func addTask(title: String, notes: String?, startDate: Date?, endDate: Date?) {
        let item = PlanningItem(
            title: title,
            notes: notes,
            startDate: startDate,
            endDate: endDate,
            isTask: true,
            isCalendarEvent: startDate != nil,
            completed: false,
            source: .local
        )
        items.append(item)
        save()
    }

    @discardableResult
    func addLocalEvent(title: String, notes: String?, startDate: Date, endDate: Date, locationID: UUID? = nil) -> PlanningItem {
        let item = PlanningItem(
            title: title,
            notes: notes,
            startDate: startDate,
            endDate: endDate,
            isTask: false,
            isCalendarEvent: true,
            completed: false,
            source: .local,
            locationID: locationID
        )
        items.append(item)
        save()
        return item
    }

    @discardableResult
    func duplicateLocalEvent(_ item: PlanningItem) -> PlanningItem? {
        guard item.source == .local,
              item.isCalendarEvent,
              !item.isTask,
              let startDate = item.startDate else {
            return nil
        }
        let endDate = item.endDate ?? startDate.addingTimeInterval(60 * 60)
        let duplicate = PlanningItem(
            title: "\(item.title) Copy",
            notes: item.notes,
            startDate: startDate,
            endDate: endDate,
            isTask: false,
            isCalendarEvent: true,
            completed: item.completed,
            source: .local,
            hasTaskMode: item.hasTaskMode,
            eventTasks: item.eventTasks,
            locationID: item.locationID
        )
        items.append(duplicate)
        save()
        return duplicate
    }

    func moveEvent(_ item: PlanningItem, to targetDate: Date) {
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              let startDate = items[index].startDate else {
            return
        }
        let duration = (items[index].endDate ?? startDate).timeIntervalSince(startDate)
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: startDate)
        var newStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day], from: targetDate)) ?? targetDate
        if let hour = components.hour, let minute = components.minute, let second = components.second {
            newStart = Calendar.current.date(bySettingHour: hour, minute: minute, second: second, of: newStart) ?? newStart
        }
        items[index].startDate = newStart
        items[index].endDate = newStart.addingTimeInterval(duration)
        save()
    }

    @discardableResult
    func upsertCalendarEventSnapshot(_ event: EKEvent) -> PlanningItem? {
        guard let identifier = event.eventIdentifier else { return nil }
        if let index = items.firstIndex(where: { $0.calendarEventIdentifier == identifier }) {
            items[index].title = event.title ?? "Untitled"
            items[index].notes = event.notes
            items[index].startDate = event.startDate
            items[index].endDate = event.endDate
            items[index].isCalendarEvent = true
            items[index].isTask = false
            items[index].source = .calendar
            items[index].calendarEventIdentifier = identifier
            save()
            return items[index]
        }

        let snapshot = PlanningItem(
            title: event.title ?? "Untitled",
            notes: event.notes,
            startDate: event.startDate,
            endDate: event.endDate,
            isTask: false,
            isCalendarEvent: true,
            completed: false,
            source: .calendar,
            calendarEventIdentifier: identifier
        )
        items.append(snapshot)
        save()
        return snapshot
    }

    func upsertFromTask(_ task: TodoItem) {
        guard let due = task.dueDate else {
            removeTaskPlan(for: task.id)
            return
        }
        let startDate = task.hasDueTime ? due : Calendar.current.startOfDay(for: due)
        let endDate = task.hasDueTime
        ? startDate.addingTimeInterval(Double((task.durationMinutes ?? 30) * 60))
        : startDate
        if let idx = items.firstIndex(where: { $0.sourceType == .task && $0.sourceID == task.id.uuidString }) {
            items[idx].title = task.title
            items[idx].notes = task.notes
            items[idx].startDate = startDate
            items[idx].endDate = endDate
            items[idx].isTask = true
            items[idx].isCalendarEvent = false
            items[idx].completed = task.isCompleted
            items[idx].source = .local
            items[idx].sourceType = .task
            items[idx].sourceID = task.id.uuidString
            items[idx].linkedCalendarEventId = task.linkedCalendarEventId ?? task.calendarEventIdentifier
            items[idx].locationID = task.locationID
        } else {
            let newItem = PlanningItem(
                title: task.title,
                notes: task.notes,
                startDate: startDate,
                endDate: endDate,
                isTask: true,
                isCalendarEvent: false,
                completed: task.isCompleted,
                source: .local,
                sourceType: .task,
                sourceID: task.id.uuidString,
                linkedCalendarEventId: task.linkedCalendarEventId ?? task.calendarEventIdentifier,
                locationID: task.locationID
            )
            items.append(newItem)
        }
        ClientLog.debug("[PlanningStore] upsertFromTask -> total items: \(items.count)")
        save()
    }

    func setLocation(itemID: UUID, locationID: UUID?) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].locationID = locationID
        save()
    }

    func linkToGoogleCalendarEvent(itemID: UUID, googleID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let wrappedID = GoogleSyncIdentifierPrefix.calendar + googleID
        items[index].sourceID = wrappedID
        items[index].calendarEventIdentifier = wrappedID
        items[index].linkedCalendarEventId = wrappedID
        save()
    }

    func removeTaskPlan(for id: UUID) {
        let before = items.count
        items.removeAll { $0.sourceType == .task && $0.sourceID == id.uuidString }
        if items.count != before {
            ClientLog.debug("[PlanningStore] removed task plan")
        }
        save()
    }

    func upsertFromReminder(identifier: String, title: String, notes: String?, dueDate: Date) {
        let endDate = dueDate.addingTimeInterval(30 * 60)
        if let idx = items.firstIndex(where: { $0.sourceType == .reminder && $0.sourceID == identifier }) {
            items[idx].title = title
            items[idx].notes = notes
            items[idx].startDate = dueDate
            items[idx].endDate = endDate
            items[idx].sourceType = .reminder
            items[idx].sourceID = identifier
        } else {
            let newItem = PlanningItem(
                title: title,
                notes: notes,
                startDate: dueDate,
                endDate: endDate,
                isTask: false,
                isCalendarEvent: false,
                completed: false,
                source: .reminders,
                sourceType: .reminder,
                sourceID: identifier,
                reminderIdentifier: identifier
            )
            items.append(newItem)
        }
        ClientLog.debug("[PlanningStore] upsertFromReminder -> total items: \(items.count)")
        save()
    }

    func syncTasks(_ tasks: [TodoItem]) {
        for task in tasks {
            if task.dueDate != nil {
                upsertFromTask(task)
            } else {
                removeTaskPlan(for: task.id)
            }
        }
    }
    
    func updateTask(_ item: PlanningItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
    }

    func setEventTaskMode(for eventID: UUID, enabled: Bool) {
        guard let index = items.firstIndex(where: { $0.id == eventID }) else { return }
        items[index].hasTaskMode = enabled
        if !enabled {
            items[index].eventTasks = []
        }
        save()
    }

    func addEventTask(
        to eventID: UUID,
        title: String,
        source: PlanningItem.EventTask.Source
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = items.firstIndex(where: { $0.id == eventID }) else { return }
        items[index].hasTaskMode = true
        items[index].eventTasks.append(.init(title: trimmedTitle, source: source))
        save()
    }

    func toggleEventTaskCompletion(eventID: UUID, taskID: UUID) {
        guard let eventIndex = items.firstIndex(where: { $0.id == eventID }),
              let taskIndex = items[eventIndex].eventTasks.firstIndex(where: { $0.id == taskID }) else { return }
        items[eventIndex].eventTasks[taskIndex].isCompleted.toggle()
        save()
    }

    func updateEventTaskTitle(eventID: UUID, taskID: UUID, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let eventIndex = items.firstIndex(where: { $0.id == eventID }),
              let taskIndex = items[eventIndex].eventTasks.firstIndex(where: { $0.id == taskID }) else { return }
        items[eventIndex].eventTasks[taskIndex].title = trimmedTitle
        save()
    }

    func replaceEventTasks(eventID: UUID, tasks: [PlanningItem.EventTask]) {
        guard let index = items.firstIndex(where: { $0.id == eventID }) else { return }
        items[index].hasTaskMode = true
        items[index].eventTasks = tasks
        save()
    }

    func deleteEventTask(eventID: UUID, taskID: UUID) {
        guard let eventIndex = items.firstIndex(where: { $0.id == eventID }) else { return }
        items[eventIndex].eventTasks.removeAll { $0.id == taskID }
        save()
    }
    
    func deleteTask(_ item: PlanningItem) {
        items.removeAll { $0.id == item.id }
        save()
    }
    
    func toggleComplete(_ item: PlanningItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].completed.toggle()
        save()
    }
    
    // MARK: - Queries
    
    var activeTasks: [PlanningItem] {
        items.filter { $0.isTask && !$0.completed }
    }
    
    var completedTasks: [PlanningItem] {
        items.filter { $0.isTask && $0.completed }
    }
    
    func items(on day: Date) -> [PlanningItem] {
        let cal = Calendar.current
        return items.filter { item in
            guard let start = item.startDate else { return false }
            return cal.isDate(start, inSameDayAs: day)
        }
    }

    var localEvents: [PlanningItem] {
        items
            .filter { $0.source == .local && $0.isCalendarEvent && !$0.isTask }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    var googleSyncedEvents: [PlanningItem] {
        items
            .filter { $0.isCalendarEvent && !$0.isTask && $0.isGoogleSynced }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    func localEvents(on day: Date) -> [PlanningItem] {
        let cal = Calendar.current
        return localEvents.filter { item in
            guard let start = item.startDate else { return false }
            return cal.isDate(start, inSameDayAs: day)
        }
    }
    
    // MARK: - Calendar import
    
    func importEvents(start: Date, end: Date) {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: eventStore.calendars(for: .event))
        let ekEvents = eventStore.events(matching: predicate)
        mergeCalendarEvents(ekEvents)
    }
    
    private func mergeCalendarEvents(_ events: [EKEvent]) {
        var mutable = items
        for event in events {
            let identifier = event.eventIdentifier
            if let idx = mutable.firstIndex(where: { $0.calendarEventIdentifier == identifier }) {
                mutable[idx].title = event.title
                mutable[idx].startDate = event.startDate
                mutable[idx].endDate = event.endDate
                mutable[idx].isCalendarEvent = true
                mutable[idx].isTask = false
                mutable[idx].source = .calendar
            } else {
                let newItem = PlanningItem(
                    title: event.title ?? "Untitled",
                    notes: event.notes,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isTask: false,
                    isCalendarEvent: true,
                    completed: false,
                    source: .calendar,
                    calendarEventIdentifier: identifier
                )
                mutable.append(newItem)
            }
        }
        items = mutable
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode([PlanningItem].self, from: data) {
            items = decoded
        }
    }
}

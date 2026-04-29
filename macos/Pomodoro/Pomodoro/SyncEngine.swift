import Foundation
import EventKit

/// Centralized sync engine for tasks, reminders, and calendar events.
/// - External ID rules:
///   - Tasks use pomodoroapp://task/<UUID>
///   - Calendar events use pomodoroapp://event/<UUID>
///   - External IDs are stored inside `notes` and are the sole matching key.
/// - Conflict resolution: lastModified wins (remote vs. local).
@MainActor
final class SyncEngine {
    private let eventStore: EKEventStore
    private let permissionsManager: PermissionsManager
    private weak var todoStore: TodoStore?
    private let syncLoopProtectionWindow: TimeInterval = 2
    
    init(permissionsManager: PermissionsManager, todoStore: TodoStore? = nil, eventStore: EKEventStore? = nil) {
        self.permissionsManager = permissionsManager
        self.todoStore = todoStore
        self.eventStore = eventStore ?? SharedEventStore.shared.eventStore
    }
    
    func attachTodoStore(_ store: TodoStore) {
        todoStore = store
    }
    
    func syncAll() async throws {
        try await syncTasksWithReminders()
        try await syncCalendarEvents()
    }
    
    func syncTasksWithReminders() async throws {
        let start = Date()
        ClientLog.debug("[SyncEngine] Reminders sync-all start")
        try await ensureRemindersAccess()
        guard let store = todoStore else { return }
        let calendar = try reminderCalendar()
        var failureMessages: [String] = []
        
        do {
            try await reverseSyncReminders(in: calendar, store: store)
        } catch {
            let message = "Reverse sync failed: \(error.localizedDescription)"
            ClientLog.debugError("[SyncEngine][Reminders] Reverse sync failed", error)
            failureMessages.append(message)
        }

        for item in store.items {
            guard item.durationMinutes == nil else { continue }
            do {
                _ = try await syncReminder(for: item, calendar: calendar)
            } catch {
                let message = "Failed to sync task: \(error.localizedDescription)"
                ClientLog.debugError("[SyncEngine][Reminders] Failed to sync task", error)
                failureMessages.append(message)
            }
        }

        let duration = Date().timeIntervalSince(start)
        ClientLog.debug("[SyncEngine] Reminders sync-all end. failed: \(failureMessages.count) duration: \(String(format: "%.2f", duration))s")

        if let firstFailure = failureMessages.first {
            throw SyncError.partialReminderSyncFailed(firstFailure)
        }
    }

    func syncReminder(for item: TodoItem) async throws -> String {
        let calendar = try reminderCalendar()
        return try await syncReminder(for: item, calendar: calendar)
    }

    func testReminderCreation() async {
        ClientLog.debug("[SyncEngine][RemindersTest] Starting test reminder creation")

        do {
            try await ensureRemindersAccess()
            let calendar = try reminderCalendar()
            ClientLog.debug("[SyncEngine][RemindersTest] Reminder calendar resolved")

            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = "Pomodoro Test Reminder"
            reminder.notes = "EventKit connectivity test"
            reminder.calendar = calendar
            reminder.priority = 0

            do {
                try eventStore.save(reminder, commit: true)
                ClientLog.debug("[SyncEngine][RemindersTest] Test reminder created successfully")
            } catch {
                ClientLog.debugError("[SyncEngine][RemindersTest] Test reminder failed", error)
            }
        } catch {
            ClientLog.debugError("[SyncEngine][RemindersTest] Setup failed", error)
        }
    }

    private func syncReminder(for item: TodoItem, calendar: EKCalendar) async throws -> String {
        let start = Date()
        ClientLog.debug("[SyncEngine][Reminders] Sync start for task")
        try await ensureRemindersAccess()
        guard !shouldSkipLoopProtectedImport(for: item) else {
            ClientLog.debug("[SyncEngine][Reminders] Skipping outbound sync due to loop protection")
            return item.reminderIdentifier ?? ""
        }

        let existing = existingReminder(for: item)
        let reminder = existing ?? EKReminder(eventStore: eventStore)

        ClientLog.debug("[SyncEngine][Reminders] \(existing == nil ? "Creating" : "Updating") reminder")

        reminder.calendar = calendar
        applyReminderFields(to: reminder, from: item)

        do {
            try eventStore.save(reminder, commit: true)
            ClientLog.debug("[SyncEngine][Reminders] save result: success")
            markTaskSynced(itemId: item.id, reminderIdentifier: reminder.calendarItemIdentifier)
            let duration = Date().timeIntervalSince(start)
            ClientLog.debug("[SyncEngine][Reminders] sync end in \(String(format: "%.2f", duration))s")
            return reminder.calendarItemIdentifier
        } catch {
            ClientLog.debugError("[SyncEngine][Reminders] save result: failed", error)
            throw SyncError.reminderSaveFailed(item.title, error.localizedDescription)
        }
    }
    
    func syncCalendarEvents() async throws {
        let start = Date()
        ClientLog.debug("[SyncEngine] Calendar sync start")
        
        try await ensureCalendarAccess()
        guard let store = todoStore else { return }

        let rangeStart = Calendar.current.startOfDay(for: Date())
        let rangeEnd = Calendar.current.date(byAdding: .day, value: 7, to: rangeStart) ?? rangeStart
        let events = fetchEvents(from: rangeStart, end: rangeEnd)
        var stats = SyncStats(read: events.count, written: 0, skipped: 0)

        try reverseSyncCalendarEvents(events, store: store)
        try handleDeletedCalendarEvents(events, store: store)

        let busyBlocks = calendarBlocks(from: events)
        let tasksToSchedule = store.items.filter {
            $0.syncToCalendar && $0.calendarEventIdentifier == nil && ($0.durationMinutes ?? 25) >= 25
        }
        let schedulePlan = buildSchedulePlan(for: tasksToSchedule, busyBlocks: busyBlocks, rangeStart: rangeStart, rangeEnd: rangeEnd)
        applySchedulePlan(schedulePlan, store: store)

        let refreshedEvents = fetchEvents(from: rangeStart, end: rangeEnd)
        var eventMapByIdentifier: [String: EKEvent] = [:]
        var eventMapByExternalId: [String: EKEvent] = [:]
        for event in refreshedEvents {
            if let identifier = event.eventIdentifier {
                eventMapByIdentifier[identifier] = event
            }
            if let parsed = ExternalID.parse(from: event.notes),
               parsed.externalId.hasPrefix(ExternalID.taskPrefix) {
                eventMapByExternalId[parsed.externalId] = event
            }
        }

        for item in store.items where item.syncToCalendar {
            var task = item
            if task.externalId.isEmpty {
                task.externalId = ExternalID.taskId(for: task.id)
                store.updateItem(task)
            }

            guard let scheduledStart = task.dueDate else {
                continue
            }

            let existing = task.calendarEventIdentifier.flatMap { eventMapByIdentifier[$0] } ?? eventMapByExternalId[task.externalId]
            if let existing {
                let remoteModified = existing.lastModifiedDate ?? existing.creationDate ?? .distantPast
                if remoteModified > task.lastModified {
                    var updated = task
                    updated.title = existing.title
                    updated.notes = ExternalID.parse(from: existing.notes)?.cleanNotes
                    updated.dueDate = existing.startDate ?? scheduledStart
                    updated.hasDueTime = !(existing.isAllDay)
                    updated.durationMinutes = eventDurationMinutes(for: existing, fallback: task.durationMinutes)
                    updated.calendarEventIdentifier = existing.eventIdentifier
                    updated.linkedCalendarEventId = existing.eventIdentifier
                    updated.lastModified = remoteModified
                    store.updateItem(updated)
                    ClientLog.debug("[SyncEngine][Calendar] Imported newer calendar event")
                } else {
                    try updateEvent(existing, with: task, externalId: task.externalId)
                    var updated = task
                    updated.calendarEventIdentifier = existing.eventIdentifier
                    updated.linkedCalendarEventId = existing.eventIdentifier
                    updated.lastModified = Date()
                    store.updateItem(updated)
                    ClientLog.debug("[SyncEngine][Calendar] Updated calendar event")
                }
                stats.written += 1
            } else {
                let eventId = try createEvent(from: task, externalId: task.externalId)
                var updated = task
                updated.calendarEventIdentifier = eventId
                updated.linkedCalendarEventId = eventId
                updated.lastModified = Date()
                store.updateItem(updated)
                ClientLog.debug("[SyncEngine][Calendar] Created calendar event")
                stats.written += 1
            }
        }

        let duration = Date().timeIntervalSince(start)
        ClientLog.debug("[SyncEngine] Calendar sync end. read: \(stats.read) written: \(stats.written) skipped: \(stats.skipped) duration: \(String(format: "%.2f", duration))s")
    }
    
    func deleteReminder(for item: TodoItem) async throws {
        guard let reminderIdentifier = item.reminderIdentifier else { return }
        try await ensureRemindersAccess()
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder else { return }
        try eventStore.remove(reminder, commit: true)
    }
    
    // MARK: - Permissions
    
    private func ensureRemindersAccess() async throws {
        if permissionsManager.isRemindersAuthorized { return }
        await permissionsManager.requestRemindersPermission()
        if !permissionsManager.isRemindersAuthorized {
            throw SyncError.notAuthorized
        }
    }
    
    private func ensureCalendarAccess() async throws {
        if permissionsManager.isCalendarAuthorized { return }
        await permissionsManager.requestCalendarPermission()
        if !permissionsManager.isCalendarAuthorized {
            throw SyncError.notAuthorized
        }
    }
    
    // MARK: - Reminders Helpers

    private func reminderComponents(from item: TodoItem) -> DateComponents? {
        guard let due = item.dueDate else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
        if item.hasDueTime {
            let time = Calendar.current.dateComponents([.hour, .minute], from: due)
            components.hour = time.hour
            components.minute = time.minute
        }
        return components
    }
    
    private func fetchAllReminders() async -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func fetchReminders(in calendar: EKCalendar) async -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
    
    private func createReminder(from item: TodoItem) throws -> String {
        let reminder = EKReminder(eventStore: eventStore)
        applyReminderFields(to: reminder, from: item)
        reminder.calendar = try reminderCalendar()
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }
    
    private func updateReminder(_ reminder: EKReminder, with item: TodoItem) throws {
        if reminder.calendar == nil {
            reminder.calendar = try reminderCalendar()
        }
        applyReminderFields(to: reminder, from: item)
        try eventStore.save(reminder, commit: true)
    }

    private func applyReminderFields(to reminder: EKReminder, from item: TodoItem) {
        reminder.title = item.title
        reminder.notes = reminderNotes(from: item)
        reminder.isCompleted = item.isCompleted
        reminder.dueDateComponents = reminderComponents(from: item)
        reminder.priority = 0
    }

    private func reminderCalendar() throws -> EKCalendar {
        ClientLog.debug("[SyncEngine][Reminders] selecting default reminders calendar")
        if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
            return defaultCalendar
        }
        ClientLog.debug("[SyncEngine][Reminders] no default reminders calendar available")
        throw SyncError.noReminderCalendar
    }

    private func reminderNotes(from item: TodoItem) -> String {
        item.notes ?? ""
    }

    private func existingReminder(for item: TodoItem) -> EKReminder? {
        guard let reminderIdentifier = item.reminderIdentifier else { return nil }
        return eventStore.calendarItem(withIdentifier: reminderIdentifier) as? EKReminder
    }

    private func reverseSyncReminders(in calendar: EKCalendar, store: TodoStore) async throws {
        ClientLog.debug("[SyncEngine][Reminders] Reverse sync start")
        let reminders = await fetchReminders(in: calendar)
        ClientLog.debug("[SyncEngine][Reminders] Reverse sync fetched \(reminders.count) reminders")

        for reminder in reminders {
            let reminderTitle = reminder.title ?? "Untitled Reminder"
            ClientLog.debug("[SyncEngine][Reminders] Importing reminder")

            if let local = store.items.first(where: { $0.reminderIdentifier == reminder.calendarItemIdentifier }) {
                if shouldSkipLoopProtectedImport(for: local) {
                    ClientLog.debug("[SyncEngine][Reminders] Skipping import due to loop protection")
                    continue
                }

                var updated = local
                updated.title = reminderTitle
                updated.notes = cleanedReminderNotes(reminder.notes)
                updated.isCompleted = reminder.isCompleted
                updated.dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                updated.hasDueTime = reminder.dueDateComponents?.hasTimeComponents ?? false
                updated.lastModified = reminder.lastModifiedDate ?? reminder.creationDate ?? Date()
                updated.reminderIdentifier = reminder.calendarItemIdentifier
                updated.lastSyncedAt = Date()
                updated.syncStatus = .synced
                store.updateItem(updated)
                ClientLog.debug("[SyncEngine][Reminders] Updated local task from reminder")
            } else {
                let newTask = TodoItem(
                    title: reminderTitle,
                    notes: cleanedReminderNotes(reminder.notes),
                    isCompleted: reminder.isCompleted,
                    dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                    hasDueTime: reminder.dueDateComponents?.hasTimeComponents ?? false,
                    reminderIdentifier: reminder.calendarItemIdentifier,
                    lastSyncedAt: Date(),
                    syncStatus: .synced
                )
                store.addItem(newTask)
                ClientLog.debug("[SyncEngine][Reminders] Created local task from reminder")
            }
        }
    }

    private func cleanedReminderNotes(_ notes: String?) -> String? {
        guard let notes, !notes.isEmpty else { return nil }
        return notes
    }

    private func shouldSkipLoopProtectedImport(for item: TodoItem) -> Bool {
        guard let lastSyncedAt = item.lastSyncedAt else { return false }
        return Date().timeIntervalSince(lastSyncedAt) < syncLoopProtectionWindow
    }

    private func markTaskSynced(itemId: UUID, reminderIdentifier: String) {
        guard let store = todoStore,
              let existing = store.items.first(where: { $0.id == itemId }) else {
            return
        }
        var updated = existing
        updated.reminderIdentifier = reminderIdentifier
        updated.lastSyncedAt = Date()
        updated.lastModified = Date()
        updated.syncStatus = .synced
        store.updateItem(updated)
    }
    
    // MARK: - Calendar Helpers
    
    private func fetchEvents(from start: Date, end: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    private func calendarBlocks(from events: [EKEvent]) -> [CalendarBlock] {
        events.compactMap { event in
            guard let start = event.startDate, let end = event.endDate, end > start else { return nil }
            return CalendarBlock(start: start, end: end, title: event.title ?? "Busy")
        }
    }

    private func freeSlots(from busyBlocks: [CalendarBlock], rangeStart: Date, rangeEnd: Date) -> [FreeTimeSlot] {
        guard rangeEnd > rangeStart else { return [] }
        let minimumDuration: TimeInterval = 25 * 60
        let sortedBlocks = busyBlocks.sorted { $0.start < $1.start }
        var cursor = rangeStart
        var slots: [FreeTimeSlot] = []

        for block in sortedBlocks {
            if block.end <= cursor { continue }
            if block.start > cursor {
                let candidateEnd = min(block.start, rangeEnd)
                if candidateEnd.timeIntervalSince(cursor) >= minimumDuration {
                    slots.append(FreeTimeSlot(start: cursor, end: candidateEnd))
                }
            }
            cursor = max(cursor, block.end)
            if cursor >= rangeEnd { break }
        }

        if rangeEnd.timeIntervalSince(cursor) >= minimumDuration {
            slots.append(FreeTimeSlot(start: cursor, end: rangeEnd))
        }
        return slots
    }

    private func buildSchedulePlan(
        for tasks: [TodoItem],
        busyBlocks: [CalendarBlock],
        rangeStart: Date,
        rangeEnd: Date
    ) -> SchedulingPlan {
        var availableSlots = freeSlots(from: busyBlocks, rangeStart: rangeStart, rangeEnd: rangeEnd)
        let sortedTasks = tasks.sorted { lhs, rhs in
            let lhsPriority = lhs.priority.rawValue
            let rhsPriority = rhs.priority.rawValue
            if lhsPriority != rhsPriority {
                return lhsPriority > rhsPriority
            }
            let lhsDeadline = schedulingDeadline(for: lhs) ?? .distantFuture
            let rhsDeadline = schedulingDeadline(for: rhs) ?? .distantFuture
            return lhsDeadline < rhsDeadline
        }

        var entries: [SchedulingPlan.Entry] = []

        for task in sortedTasks {
            let durationMinutes = max(25, task.durationMinutes ?? 25)
            let duration = TimeInterval(durationMinutes * 60)
            let deadline = schedulingDeadline(for: task) ?? rangeEnd

            for index in availableSlots.indices {
                let slot = availableSlots[index]
                let proposedStart = max(slot.start, rangeStart)
                let proposedEnd = proposedStart.addingTimeInterval(duration)
                guard proposedEnd <= slot.end, proposedEnd <= deadline else { continue }

                let pomodoros = max(1, Int(ceil(Double(durationMinutes) / 25.0)))
                entries.append(
                    SchedulingPlan.Entry(
                        taskTitle: task.title,
                        taskId: task.id.uuidString,
                        start: proposedStart,
                        end: proposedEnd,
                        pomodoros: pomodoros
                    )
                )

                if proposedEnd < slot.end {
                    availableSlots[index] = FreeTimeSlot(start: proposedEnd, end: slot.end)
                } else {
                    availableSlots.remove(at: index)
                }
                break
            }
        }

        return SchedulingPlan(schedule: entries)
    }

    private func applySchedulePlan(_ plan: SchedulingPlan, store: TodoStore) {
        for entry in plan.schedule {
            guard let taskID = UUID(uuidString: entry.taskId),
                  let existing = store.items.first(where: { $0.id == taskID }) else {
                continue
            }

            var updated = existing
            updated.dueDate = entry.start
            updated.hasDueTime = true
            updated.durationMinutes = max(existing.durationMinutes ?? 25, Int(entry.end.timeIntervalSince(entry.start) / 60))
            updated.lastModified = Date()
            store.updateItem(updated)
            ClientLog.debug("[SyncEngine][Calendar] Scheduled task")
        }
    }

    private func reverseSyncCalendarEvents(_ events: [EKEvent], store: TodoStore) throws {
        for event in events {
            guard let parsed = ExternalID.parse(from: event.notes),
                  parsed.externalId.hasPrefix(ExternalID.taskPrefix) else {
                continue
            }

            let eventIdentifier = event.eventIdentifier
            let remoteModified = event.lastModifiedDate ?? event.creationDate ?? .distantPast
            if let local = store.items.first(where: {
                $0.calendarEventIdentifier == eventIdentifier || $0.externalId == parsed.externalId
            }) {
                guard remoteModified > local.lastModified else { continue }

                var updated = local
                updated.title = event.title
                updated.notes = parsed.cleanNotes
                updated.dueDate = event.startDate
                updated.hasDueTime = !event.isAllDay
                updated.durationMinutes = eventDurationMinutes(for: event, fallback: local.durationMinutes)
                updated.calendarEventIdentifier = eventIdentifier
                updated.linkedCalendarEventId = eventIdentifier
                updated.syncToCalendar = true
                updated.lastModified = remoteModified
                store.updateItem(updated)
                ClientLog.debug("[SyncEngine][Calendar] Imported event change")
            } else if let taskId = uuid(from: parsed.externalId, expectedPrefix: ExternalID.taskPrefix) {
                let newTask = TodoItem(
                    id: taskId,
                    externalId: parsed.externalId,
                    title: event.title,
                    notes: parsed.cleanNotes,
                    isCompleted: false,
                    dueDate: event.startDate,
                    hasDueTime: !event.isAllDay,
                    durationMinutes: eventDurationMinutes(for: event, fallback: nil),
                    syncToCalendar: true,
                    linkedCalendarEventId: eventIdentifier,
                    calendarEventIdentifier: eventIdentifier,
                    syncStatus: .synced
                )
                store.addItem(newTask)
                ClientLog.debug("[SyncEngine][Calendar] Created local task from calendar event")
            }
        }
    }

    private func handleDeletedCalendarEvents(_ events: [EKEvent], store: TodoStore) throws {
        let existingIdentifiers = Set(events.compactMap(\.eventIdentifier))
        for item in store.items where item.syncToCalendar && item.calendarEventIdentifier != nil {
            guard let identifier = item.calendarEventIdentifier,
                  !existingIdentifiers.contains(identifier) else {
                continue
            }

            var updated = item
            updated.dueDate = nil
            updated.hasDueTime = false
            updated.calendarEventIdentifier = nil
            updated.linkedCalendarEventId = nil
            updated.syncToCalendar = false
            updated.lastModified = Date()
            store.updateItem(updated)
            ClientLog.debug("[SyncEngine][Calendar] Event deleted remotely, task unscheduled")
        }
    }

    private func schedulingDeadline(for item: TodoItem) -> Date? {
        guard let dueDate = item.dueDate else { return nil }
        if item.hasDueTime {
            return dueDate
        }
        return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: dueDate))
    }

    private func eventDurationMinutes(for event: EKEvent, fallback: Int?) -> Int? {
        guard let start = event.startDate, let end = event.endDate else { return fallback }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return max(25, minutes)
    }
    
    private func createEvent(from item: TodoItem, externalId: String) throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.title = item.title
        event.notes = combinedNotes(from: item.notes, tags: item.tags, externalId: externalId)
        if let due = item.dueDate {
            if item.hasDueTime {
                event.isAllDay = false
                event.startDate = due
                let durationMinutes = item.durationMinutes ?? 30
                event.endDate = due.addingTimeInterval(Double(durationMinutes * 60))
            } else {
                let start = Calendar.current.startOfDay(for: due)
                event.isAllDay = true
                event.startDate = start
                event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: start)
            }
        }
        event.calendar = eventStore.defaultCalendarForNewEvents
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }
    
    private func updateEvent(_ event: EKEvent, with item: TodoItem, externalId: String) throws {
        event.title = item.title
        event.notes = combinedNotes(from: item.notes, tags: item.tags, externalId: externalId)
        if let due = item.dueDate {
            if item.hasDueTime {
                event.isAllDay = false
                event.startDate = due
                let durationMinutes = item.durationMinutes ?? 30
                event.endDate = due.addingTimeInterval(Double(durationMinutes * 60))
            } else {
                let start = Calendar.current.startOfDay(for: due)
                event.isAllDay = true
                event.startDate = start
                event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: start)
            }
        }
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
    
    // MARK: - Shared Helpers
    
    private func combinedNotes(from userNotes: String?, tags: [String], externalId: String) -> String {
        var baseNotes: String?
        if let notes = userNotes, !notes.isEmpty {
            baseNotes = notes
        }
        if !tags.isEmpty {
            let tagLine = "Tags: \(tags.joined(separator: ", "))"
            if var existing = baseNotes, !existing.isEmpty {
                existing.append("\n\(tagLine)")
                baseNotes = existing
            } else {
                baseNotes = tagLine
            }
        }
        return ExternalID.upsert(in: baseNotes, externalId: externalId)
    }
    
    private func uuid(from externalId: String, expectedPrefix: String) -> UUID? {
        guard externalId.hasPrefix(expectedPrefix) else { return nil }
        let suffix = externalId.replacingOccurrences(of: expectedPrefix, with: "")
        return UUID(uuidString: suffix)
    }
    
    // MARK: - Types

    private struct SyncStats {
        var read = 0
        var written = 0
        var skipped = 0
    }

    struct CalendarBlock: Equatable {
        let start: Date
        let end: Date
        let title: String
    }

    struct FreeTimeSlot: Equatable {
        let start: Date
        let end: Date
    }

    struct SchedulingPlan: Codable, Equatable {
        struct Entry: Codable, Equatable {
            let taskTitle: String
            let taskId: String
            let start: Date
            let end: Date
            let pomodoros: Int
        }

        let schedule: [Entry]
    }
    
    enum SyncError: LocalizedError {
        case notAuthorized
        case noReminderCalendar
        case reminderSaveFailed(String, String)
        case partialReminderSyncFailed(String)
        case noCalendarAvailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Calendar or Reminders access not authorized."
            case .noReminderCalendar:
                return "No default reminders calendar is available."
            case let .reminderSaveFailed(title, message):
                return "Reminder save failed for '\(title)': \(message)"
            case let .partialReminderSyncFailed(message):
                return message
            case .noCalendarAvailable:
                return "No default calendar is available."
            }
        }
    }
}

private extension DateComponents {
    var hasTimeComponents: Bool {
        hour != nil || minute != nil || second != nil
    }
}

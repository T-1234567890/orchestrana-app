import Foundation
import Combine
import EventKit

/// CalendarManager handles EventKit Calendar integration for time-based events.
/// Calendar is a separate feature from Todo/Reminders.
@MainActor
final class CalendarManager: ObservableObject {
    private let eventStore = SharedEventStore.shared.eventStore
    private let permissionsManager: PermissionsManager
    
    @Published var events: [EKEvent] = []
    @Published var aiFreeSlots: [AIService.FreeSlot] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    init(permissionsManager: PermissionsManager) {
        self.permissionsManager = permissionsManager
    }
    
    // MARK: - Access Check
    
    var isAuthorized: Bool {
        permissionsManager.isCalendarAuthorized
    }
    
    // MARK: - Event Fetching
    
    /// Fetch events for a date range.
    /// Safety: this is a READ-ONLY refresh for Calendar UI; it must not create or modify tasks.
    func fetchEvents(from startDate: Date, to endDate: Date) async {
        guard isAuthorized else {
            events = []
            error = nil
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        
        let fetchedEvents = eventStore.events(matching: predicate)
        events = fetchedEvents.sorted { $0.startDate < $1.startDate }
        error = nil
    }

    func readEvents(from startDate: Date, to endDate: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func updateAIFreeSlots(_ slots: [AIService.FreeSlot]) {
        aiFreeSlots = slots.sorted { $0.start < $1.start }
    }
    
    /// Fetch events for today
    func fetchTodayEvents() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? Date()
        
        await fetchEvents(from: startOfDay, to: endOfDay)
    }
    
    /// Fetch events for a specific day (alias for fetchTodayEvents when using arbitrary date)
    func fetchDayEvents(for date: Date) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        await fetchEvents(from: startOfDay, to: endOfDay)
    }
    
    /// Fetch events for current week (starting at user's locale week start)
    func fetchWeekEvents() async {
        let calendar = Calendar.current
        let today = Date()
        
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else {
            return
        }
        
        await fetchEvents(from: startOfWeek, to: endOfWeek)
    }
    
    /// Fetch events for the week containing the given date
    func fetchWeekEvents(containing date: Date) async {
        let calendar = Calendar.current
        guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)),
              let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else {
            return
        }
        await fetchEvents(from: startOfWeek, to: endOfWeek)
    }
    
    /// Fetch events for the month containing the given date
    func fetchMonthEvents(containing date: Date) async {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            return
        }
        await fetchEvents(from: startOfMonth, to: endOfMonth)
    }
    
    // MARK: - Event Creation
    
    /// Create a new calendar event
    func createEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) async throws {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
    
    /// Delete multiple events atomically. Fails if any event is not editable.
    func deleteEvents(with identifiers: [String]) async throws {
        guard isAuthorized else { throw CalendarError.notAuthorized }
        let events = identifiers.compactMap { eventStore.event(withIdentifier: $0) }
        if events.count != identifiers.count {
            throw CalendarError.notEditable // missing or inaccessible events
        }
        guard events.allSatisfy({ $0.calendar.allowsContentModifications }) else {
            throw CalendarError.notEditable
        }
        for event in events {
            try eventStore.remove(event, span: .thisEvent, commit: false)
        }
        try eventStore.commit()
    }
    
    /// Move events to a target date (preserves time-of-day and duration). Fails if any event is not editable.
    func moveEvents(with identifiers: [String], to targetDate: Date) async throws {
        guard isAuthorized else { throw CalendarError.notAuthorized }
        let events = identifiers.compactMap { eventStore.event(withIdentifier: $0) }
        if events.count != identifiers.count {
            throw CalendarError.notEditable
        }
        guard events.allSatisfy({ $0.calendar.allowsContentModifications }) else {
            throw CalendarError.notEditable
        }
        
        let calendar = Calendar.current
        for event in events {
            guard let start = event.startDate else { continue }
            let end = event.endDate ?? start
            let duration = end.timeIntervalSince(start)
            
            let components = calendar.dateComponents([.hour, .minute, .second], from: start)
            var combined = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: targetDate)) ?? targetDate
            if let hours = components.hour, let minutes = components.minute, let seconds = components.second {
                combined = calendar.date(bySettingHour: hours, minute: minutes, second: seconds, of: combined) ?? combined
            }
            event.startDate = combined
            event.endDate = combined.addingTimeInterval(duration)
            try eventStore.save(event, span: .thisEvent, commit: false)
        }
        try eventStore.commit()
    }
    
    // MARK: - Error Types
    
    enum CalendarError: LocalizedError {
        case notAuthorized
        case failedToCreate
        case notEditable
        
        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return NSLocalizedString("calendar.error.not_authorized", comment: "Calendar permission is missing")
            case .failedToCreate:
                return NSLocalizedString("calendar.error.create_failed", comment: "Calendar event could not be created")
            case .notEditable:
                return NSLocalizedString("calendar.error.not_editable", comment: "Calendar event cannot be edited")
            }
        }
    }
}

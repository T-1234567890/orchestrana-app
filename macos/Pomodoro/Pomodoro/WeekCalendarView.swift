import SwiftUI
import EventKit

/// Horizontal week view with selectable day columns.
struct WeekCalendarView: View {
    let days: [Date]
    let events: [EKEvent]
    let localEvents: [PlanningItem]
    let tasks: [TodoItem]
    let onSelectLocalEvent: (PlanningItem) -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    @State private var selectedDay: Date?
    
    private let columnSpacing: CGFloat = 10
    private let columnWidth: CGFloat = 180
    
    var body: some View {
        // Outer vertical scroll prevents bottom clipping when content grows tall.
        ScrollView {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(days, id: \.self) { day in
                        let dayEvents = eventsForDay(day)
                        let dayLocalEvents = localEventsForDay(day)
                        let dayTasks = tasksForDay(day)
                        DayColumnView(
                            date: day,
                            events: dayEvents,
                            localEvents: dayLocalEvents,
                            tasks: dayTasks,
                            isSelected: isSameDay(day, selectedDay),
                            onSelect: { selectedDay = day },
                            onSelectLocalEvent: onSelectLocalEvent
                        )
                        .environmentObject(localizationManager)
                        .frame(minWidth: columnWidth, maxWidth: columnWidth, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if selectedDay == nil {
                selectedDay = days.first
            }
        }
    }
    
    private func eventsForDay(_ day: Date) -> [EKEvent] {
        let cal = Calendar.current
        return events
            .filter { cal.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }
    
    private func tasksForDay(_ day: Date) -> [TodoItem] {
        let cal = Calendar.current
        return tasks
            .filter { task in
                guard let due = task.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: day)
            }
            .sorted { lhs, rhs in
                guard let l = lhs.dueDate, let r = rhs.dueDate else { return false }
                return l < r
            }
    }

    private func localEventsForDay(_ day: Date) -> [PlanningItem] {
        let cal = Calendar.current
        return localEvents
            .filter { item in
                guard let start = item.startDate else { return false }
                return cal.isDate(start, inSameDayAs: day)
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }
    
    private func isSameDay(_ lhs: Date, _ rhs: Date?) -> Bool {
        guard let rhs else { return false }
        return Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }
}

private struct DayColumnView: View {
    let date: Date
    let events: [EKEvent]
    let localEvents: [PlanningItem]
    let tasks: [TodoItem]
    let isSelected: Bool
    let onSelect: () -> Void
    let onSelectLocalEvent: (PlanningItem) -> Void
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d"
        return df
    }()
    
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        df.locale = .autoupdatingCurrent
        return df
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayLabelString(date))
                        .font(.subheadline)
                    Text(dayNumberString(date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            if events.isEmpty && localEvents.isEmpty && tasks.isEmpty {
                Text(localizationManager.text("calendar.no_events"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events, id: \.eventIdentifier) { event in
                        EventCard(event: event)
                    }
                    ForEach(localEvents) { event in
                        LocalEventCard(event: event, onSelect: {
                            onSelectLocalEvent(event)
                        })
                    }
                    ForEach(tasks, id: \.id) { task in
                        TaskCard(task: task)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private struct LocalEventCard: View {
        let event: PlanningItem
        let onSelect: () -> Void
        @EnvironmentObject private var localizationManager: LocalizationManager

        var body: some View {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(timeRange)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(7)
            }
            .buttonStyle(.plain)
        }

        private var timeRange: String {
            guard let start = event.startDate else {
                return localizationManager.text("calendar.no_due_time")
            }
            DayColumnView.timeFormatter.locale = localizationManager.effectiveLocale
            let formatter = DayColumnView.timeFormatter
            guard let end = event.endDate else {
                return formatter.string(from: start)
            }
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035))
    }
    
    private func dayNumberString(_ date: Date) -> String {
        Self.weekdayFormatter.locale = localizationManager.effectiveLocale
        return Self.weekdayFormatter.string(from: date)
    }

    private func dayLabelString(_ date: Date) -> String {
        Self.dayFormatter.locale = localizationManager.effectiveLocale
        return Self.dayFormatter.string(from: date)
    }
    
    private struct EventCard: View {
        let event: EKEvent
        @EnvironmentObject private var localizationManager: LocalizationManager
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? localizationManager.text("common.untitled"))
                    .font(.subheadline)
                    .lineLimit(1)
                Text(timeRange(event))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(cgColor: event.calendar.cgColor).opacity(0.12))
            .cornerRadius(7)
        }
        
        private func timeRange(_ event: EKEvent) -> String {
            if event.isAllDay {
                return localizationManager.text("calendar.all_day")
            }
            DayColumnView.timeFormatter.locale = localizationManager.effectiveLocale
            let formatter = DayColumnView.timeFormatter
            return "\(formatter.string(from: event.startDate)) – \(formatter.string(from: event.endDate))"
        }
    }
    
    private struct TaskCard: View {
        let task: TodoItem
        @EnvironmentObject private var localizationManager: LocalizationManager
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let due = task.dueDate {
                    if task.hasDueTime {
                        Text(timeRange(from: due, duration: task.durationMinutes))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(localizationManager.text("calendar.all_day"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(localizationManager.text("calendar.no_due_time"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(7)
        }
        
        private func timeRange(from start: Date, duration: Int?) -> String {
            DayColumnView.timeFormatter.locale = localizationManager.effectiveLocale
            let formatter = DayColumnView.timeFormatter
            let end = start.addingTimeInterval(Double((duration ?? 30) * 60))
            return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
}

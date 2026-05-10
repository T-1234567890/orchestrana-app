import SwiftUI
import EventKit

/// Day view for the calendar showing a vertical timeline with hour rows.
/// Displays events positioned by their start time in a 24-hour format.
struct CalendarDayView: View {
    let date: Date
    let events: [EKEvent]
    @EnvironmentObject private var localizationManager: LocalizationManager
    
    var body: some View {
        if events.isEmpty {
            emptyState
        } else {
            timelineContent
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(localizationManager.text("calendar.no_events_today"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }
    
    private var timelineContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 8) {
                        Text(hourLabel(hour))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            let hourEvents = eventsForHour(hour)
                            
                            if hourEvents.isEmpty {
                                Text(" ")
                                    .font(.caption2)
                            } else {
                                ForEach(hourEvents, id: \.eventIdentifier) { event in
                                    eventChip(event)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    
                    Divider()
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private func eventsForHour(_ hour: Int) -> [EKEvent] {
        let calendar = Calendar.current
        return events.filter {
            calendar.component(.hour, from: $0.startDate) == hour
        }
    }
    
    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? Date()
        Self.hourFormatter.locale = localizationManager.effectiveLocale
        return Self.hourFormatter.string(from: date)
    }
    
    @ViewBuilder
    private func eventChip(_ event: EKEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? localizationManager.text("common.untitled"))
                    .font(.caption)
                    .fontWeight(.medium)
                
                if !event.isAllDay {
                    Text(formatEventTime(event))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(cgColor: event.calendar.cgColor).opacity(0.15))
        .cornerRadius(6)
    }
    
    private func formatEventTime(_ event: EKEvent) -> String {
        Self.timeFormatter.locale = localizationManager.effectiveLocale
        let start = Self.timeFormatter.string(from: event.startDate)
        let end = Self.timeFormatter.string(from: event.endDate)
        return "\(start) - \(end)"
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
}

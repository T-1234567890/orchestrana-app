import Foundation

/// Unified planning item for tasks and calendar events.
struct PlanningItem: Identifiable, Codable, Equatable {
    struct EventTask: Identifiable, Codable, Equatable {
        enum Source: String, Codable {
            case ai
            case manual
        }

        let id: UUID
        var title: String
        var isCompleted: Bool
        var createdAt: Date
        var source: Source

        init(
            id: UUID = UUID(),
            title: String,
            isCompleted: Bool = false,
            createdAt: Date = Date(),
            source: Source
        ) {
            self.id = id
            self.title = title
            self.isCompleted = isCompleted
            self.createdAt = createdAt
            self.source = source
        }
    }

    enum SourceType: String, Codable {
        case task
        case reminder
    }
    
    enum Source: String, Codable {
        case local
        case calendar
        case reminders
    }
    
    let id: UUID
    var title: String
    var notes: String?
    var startDate: Date?
    var endDate: Date?
    var isTask: Bool
    var isCalendarEvent: Bool
    var completed: Bool
    var source: Source
    var sourceType: SourceType?
    var sourceID: String?
    var reminderIdentifier: String?
    var calendarEventIdentifier: String?
    var linkedCalendarEventId: String?
    var hasTaskMode: Bool
    var eventTasks: [EventTask]
    
    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isTask: Bool = true,
        isCalendarEvent: Bool = false,
        completed: Bool = false,
        source: Source = .local,
        sourceType: SourceType? = nil,
        sourceID: String? = nil,
        reminderIdentifier: String? = nil,
        calendarEventIdentifier: String? = nil,
        linkedCalendarEventId: String? = nil,
        hasTaskMode: Bool = false,
        eventTasks: [EventTask] = []
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.isTask = isTask
        self.isCalendarEvent = isCalendarEvent
        self.completed = completed
        self.source = source
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.reminderIdentifier = reminderIdentifier
        self.calendarEventIdentifier = calendarEventIdentifier
        self.linkedCalendarEventId = linkedCalendarEventId
        self.hasTaskMode = hasTaskMode
        self.eventTasks = eventTasks
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case startDate
        case endDate
        case isTask
        case isCalendarEvent
        case completed
        case source
        case sourceType
        case sourceID
        case reminderIdentifier
        case calendarEventIdentifier
        case linkedCalendarEventId
        case hasTaskMode
        case eventTasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        isTask = try container.decodeIfPresent(Bool.self, forKey: .isTask) ?? true
        isCalendarEvent = try container.decodeIfPresent(Bool.self, forKey: .isCalendarEvent) ?? false
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .local
        sourceType = try container.decodeIfPresent(SourceType.self, forKey: .sourceType)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
        reminderIdentifier = try container.decodeIfPresent(String.self, forKey: .reminderIdentifier)
        calendarEventIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        linkedCalendarEventId = try container.decodeIfPresent(String.self, forKey: .linkedCalendarEventId)
        hasTaskMode = try container.decodeIfPresent(Bool.self, forKey: .hasTaskMode) ?? false
        eventTasks = try container.decodeIfPresent([EventTask].self, forKey: .eventTasks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(isTask, forKey: .isTask)
        try container.encode(isCalendarEvent, forKey: .isCalendarEvent)
        try container.encode(completed, forKey: .completed)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(sourceType, forKey: .sourceType)
        try container.encodeIfPresent(sourceID, forKey: .sourceID)
        try container.encodeIfPresent(reminderIdentifier, forKey: .reminderIdentifier)
        try container.encodeIfPresent(calendarEventIdentifier, forKey: .calendarEventIdentifier)
        try container.encodeIfPresent(linkedCalendarEventId, forKey: .linkedCalendarEventId)
        try container.encode(hasTaskMode, forKey: .hasTaskMode)
        if !eventTasks.isEmpty {
            try container.encode(eventTasks, forKey: .eventTasks)
        }
    }
}

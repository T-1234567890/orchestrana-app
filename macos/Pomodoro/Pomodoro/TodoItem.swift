import Foundation

enum DeveloperDemoMode {
    static let googleVideoDemoModeKey = "googleVideoDemoMode"
    private static let baselineActiveKey = "googleVideoDemoMode.baselineActive"
    private static let baselineTaskIDsKey = "googleVideoDemoMode.baselineTaskIDs"
    private static let baselinePlanningItemIDsKey = "googleVideoDemoMode.baselinePlanningItemIDs"
    private static let baselineSystemEventIDsKey = "googleVideoDemoMode.baselineSystemEventIDs"

    static func isGoogleVideoDemoModeEnabled(tier: FeatureGate.Tier, storedValue: Bool) -> Bool {
        tier == .developer && storedValue
    }

    static func recordBaseline(
        tasks: [TodoItem],
        planningItems: [PlanningItem],
        systemEventIDs: [String]
    ) {
        let defaults = UserDefaults.standard
        defaults.set(tasks.map { $0.id.uuidString }, forKey: baselineTaskIDsKey)
        defaults.set(planningItems.map { $0.googleSyncIdentifier ?? $0.id.uuidString }, forKey: baselinePlanningItemIDsKey)
        defaults.set(systemEventIDs, forKey: baselineSystemEventIDsKey)
        defaults.set(true, forKey: baselineActiveKey)
    }

    static func clearBaseline() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: baselineActiveKey)
        defaults.removeObject(forKey: baselineTaskIDsKey)
        defaults.removeObject(forKey: baselinePlanningItemIDsKey)
        defaults.removeObject(forKey: baselineSystemEventIDsKey)
    }

    static var hasBaseline: Bool {
        UserDefaults.standard.bool(forKey: baselineActiveKey)
    }

    static func visibleTasks(_ items: [TodoItem], tier: FeatureGate.Tier, storedValue: Bool) -> [TodoItem] {
        guard isGoogleVideoDemoModeEnabled(tier: tier, storedValue: storedValue) else {
            return items
        }
        let baselineIDs = stringSet(forKey: baselineTaskIDsKey)
        return items.filter { !baselineIDs.contains($0.id.uuidString) }
    }

    static func isTaskVisible(_ item: TodoItem, tier: FeatureGate.Tier, storedValue: Bool) -> Bool {
        guard isGoogleVideoDemoModeEnabled(tier: tier, storedValue: storedValue) else {
            return true
        }
        return !stringSet(forKey: baselineTaskIDsKey).contains(item.id.uuidString)
    }

    static func visiblePlanningItems(_ items: [PlanningItem], tier: FeatureGate.Tier, storedValue: Bool) -> [PlanningItem] {
        guard isGoogleVideoDemoModeEnabled(tier: tier, storedValue: storedValue) else {
            return items
        }
        let baselineIDs = stringSet(forKey: baselinePlanningItemIDsKey)
        return items.filter { !baselineIDs.contains(planningItemIdentity($0)) }
    }

    static func isSystemEventVisible(identifier: String?, tier: FeatureGate.Tier, storedValue: Bool) -> Bool {
        guard isGoogleVideoDemoModeEnabled(tier: tier, storedValue: storedValue),
              let identifier else {
            return true
        }
        return !stringSet(forKey: baselineSystemEventIDsKey).contains(identifier)
    }

    private static func planningItemIdentity(_ item: PlanningItem) -> String {
        item.googleSyncIdentifier ?? item.id.uuidString
    }

    private static func stringSet(forKey key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
}

enum GoogleSyncIdentifierPrefix {
    static let task = "google-task:"
    static let calendar = "google-calendar:"
}

struct TodoSubtask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var completed: Bool

    init(id: UUID = UUID(), title: String, completed: Bool = false) {
        self.id = id
        self.title = title
        self.completed = completed
    }
}

/// Primary task data model for the app.
/// Represents both internal todos and synced Apple Reminders.
struct TodoItem: Identifiable, Codable, Equatable {
    enum AIOrigin: String, Codable {
        case planning
        case breakdown
        case calendarSchedule
    }

    let id: UUID
    /// External identifier used for all cross-system sync. Format: pomodoroapp://task/<UUID>
    var externalId: String
    var title: String
    var descriptionMarkdown: String?
    var isCompleted: Bool
    var dueDate: Date?
    /// Indicates whether the stored `dueDate` has a user-selected time component.
    /// When false we treat the due date as date-only (all-day) to reduce friction.
    var hasDueTime: Bool
    var durationMinutes: Int?
    var priority: Priority
    var subtasks: [TodoSubtask]
    var createdAt: Date
    var modifiedAt: Date
    var tags: [String]
    /// User-controlled calendar sync flag. Only when true will we write to Calendar.
    var syncToCalendar: Bool
    /// Identifier of the Calendar event created for this task (if any).
    var linkedCalendarEventId: String?
    
    /// Optional identifiers for system sync mirrors
    var reminderIdentifier: String?
    var calendarEventIdentifier: String?
    var lastSyncedAt: Date?
    var aiOrigin: AIOrigin?
    var aiOrder: Int?
    var pomodoroPresetID: String?
    var plannedPomodoroCount: Int?
    var locationID: UUID?
    
    enum SyncStatus: String, Codable {
        case local
        case synced
        case conflict
    }
    
    var syncStatus: SyncStatus
    
    enum CodingKeys: String, CodingKey {
        case id, externalId, title, notes, descriptionMarkdown, isCompleted, dueDate, hasDueTime, durationMinutes, priority, subtasks, createdAt, modifiedAt, tags, syncToCalendar, linkedCalendarEventId, reminderIdentifier, calendarEventIdentifier, lastSyncedAt, syncStatus, aiOrigin, aiOrder, pomodoroPresetID, plannedPomodoroCount, locationID
    }
    
    enum Priority: Int, Codable, CaseIterable {
        case none = 0
        case low = 1
        case medium = 2
        case high = 3
        
        var displayName: String {
            switch self {
            case .none: return LocalizationManager.shared.text("priority.none")
            case .low: return LocalizationManager.shared.text("priority.low")
            case .medium: return LocalizationManager.shared.text("priority.medium")
            case .high: return LocalizationManager.shared.text("priority.high")
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        externalId: String? = nil,
        title: String,
        notes: String? = nil,
        descriptionMarkdown: String? = nil,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        durationMinutes: Int? = nil,
        priority: Priority = .none,
        subtasks: [TodoSubtask] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        tags: [String] = [],
        syncToCalendar: Bool = false,
        linkedCalendarEventId: String? = nil,
        reminderIdentifier: String? = nil,
        calendarEventIdentifier: String? = nil,
        lastSyncedAt: Date? = nil,
        aiOrigin: AIOrigin? = nil,
        aiOrder: Int? = nil,
        pomodoroPresetID: String? = nil,
        plannedPomodoroCount: Int? = nil,
        locationID: UUID? = nil,
        syncStatus: SyncStatus = .local
    ) {
        self.id = id
        self.externalId = externalId ?? ExternalID.taskId(for: id)
        self.title = title
        self.descriptionMarkdown = descriptionMarkdown ?? notes
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.durationMinutes = durationMinutes
        self.priority = priority
        self.subtasks = subtasks
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.tags = tags
        self.syncToCalendar = syncToCalendar
        self.linkedCalendarEventId = linkedCalendarEventId
        self.reminderIdentifier = reminderIdentifier
        self.calendarEventIdentifier = calendarEventIdentifier
        self.lastSyncedAt = lastSyncedAt
        self.aiOrigin = aiOrigin
        self.aiOrder = aiOrder
        self.pomodoroPresetID = pomodoroPresetID
        self.plannedPomodoroCount = plannedPomodoroCount
        self.locationID = locationID
        self.syncStatus = syncStatus
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        if let external = try container.decodeIfPresent(String.self, forKey: .externalId) {
            externalId = external
        } else {
            externalId = ExternalID.taskId(for: id)
        }
        title = try container.decode(String.self, forKey: .title)
        descriptionMarkdown =
            try container.decodeIfPresent(String.self, forKey: .descriptionMarkdown)
            ?? container.decodeIfPresent(String.self, forKey: .notes)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        hasDueTime = try container.decodeIfPresent(Bool.self, forKey: .hasDueTime) ?? (dueDate != nil)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        subtasks = try container.decodeIfPresent([TodoSubtask].self, forKey: .subtasks) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        syncToCalendar = try container.decodeIfPresent(Bool.self, forKey: .syncToCalendar) ?? false
        linkedCalendarEventId = try container.decodeIfPresent(String.self, forKey: .linkedCalendarEventId)
        reminderIdentifier = try container.decodeIfPresent(String.self, forKey: .reminderIdentifier)
        calendarEventIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        aiOrigin = try container.decodeIfPresent(AIOrigin.self, forKey: .aiOrigin)
        aiOrder = try container.decodeIfPresent(Int.self, forKey: .aiOrder)
        pomodoroPresetID = try container.decodeIfPresent(String.self, forKey: .pomodoroPresetID)
        plannedPomodoroCount = try container.decodeIfPresent(Int.self, forKey: .plannedPomodoroCount)
        locationID = try container.decodeIfPresent(UUID.self, forKey: .locationID)
        syncStatus = try container.decodeIfPresent(SyncStatus.self, forKey: .syncStatus) ?? .local
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(externalId, forKey: .externalId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(descriptionMarkdown, forKey: .descriptionMarkdown)
        try container.encodeIfPresent(descriptionMarkdown, forKey: .notes)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(hasDueTime, forKey: .hasDueTime)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
        try container.encode(priority, forKey: .priority)
        if !subtasks.isEmpty {
            try container.encode(subtasks, forKey: .subtasks)
        }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        if !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
        try container.encode(syncToCalendar, forKey: .syncToCalendar)
        try container.encodeIfPresent(linkedCalendarEventId, forKey: .linkedCalendarEventId)
        try container.encodeIfPresent(reminderIdentifier, forKey: .reminderIdentifier)
        try container.encodeIfPresent(calendarEventIdentifier, forKey: .calendarEventIdentifier)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try container.encodeIfPresent(aiOrigin, forKey: .aiOrigin)
        try container.encodeIfPresent(aiOrder, forKey: .aiOrder)
        try container.encodeIfPresent(pomodoroPresetID, forKey: .pomodoroPresetID)
        try container.encodeIfPresent(plannedPomodoroCount, forKey: .plannedPomodoroCount)
        try container.encodeIfPresent(locationID, forKey: .locationID)
        try container.encode(syncStatus, forKey: .syncStatus)
    }
    
    mutating func markComplete(_ completed: Bool) {
        isCompleted = completed
        modifiedAt = Date()
    }
    
    mutating func update(title: String? = nil, notes: String? = nil, dueDate: Date? = nil, priority: Priority? = nil) {
        if let title = title { self.title = title }
        if let notes = notes { self.descriptionMarkdown = notes }
        if let dueDate = dueDate { self.dueDate = dueDate }
        if let priority = priority { self.priority = priority }
        modifiedAt = Date()
    }

    var notes: String? {
        get { descriptionMarkdown }
        set { descriptionMarkdown = newValue }
    }

    var pomodoroEstimate: Int? {
        get {
            guard let durationMinutes else { return nil }
            return max(1, Int(ceil(Double(durationMinutes) / 25.0)))
        }
        set {
            durationMinutes = newValue.map { max(1, $0) * 25 }
        }
    }

    /// Convenience alias to align with sync field naming.
    var lastModified: Date {
        get { modifiedAt }
        set { modifiedAt = newValue }
    }

    var isGoogleSynced: Bool {
        reminderIdentifier?.hasPrefix(GoogleSyncIdentifierPrefix.task) == true
            || calendarEventIdentifier?.hasPrefix(GoogleSyncIdentifierPrefix.calendar) == true
            || linkedCalendarEventId?.hasPrefix(GoogleSyncIdentifierPrefix.calendar) == true
    }
}

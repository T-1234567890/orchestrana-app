import Foundation
import FirebaseFunctions
import FirebaseAuth
import EventKit
import CryptoKit

@MainActor
final class AIService {
    private static let proDeepAnalysisModel = "google/gemini-flash-3"

    struct TaskBreakdownRequest: Encodable {
        let task: String
        let deadline: String
        let estimatedHours: Int
    }

    struct TaskPlanningRequest: Encodable {
        struct PresetPayload: Encodable {
            let id: String
            let workMinutes: Int
            let shortBreakMinutes: Int
        }

        let tasks: [String]
        let deadline: String
        let estimatedHours: Int
        let pomodoroPresets: [PresetPayload]
    }

    struct AIPlanningResponse: Decodable {
        struct Subtask: Decodable {
            let title: String
            let pomodoros: Int
            let pomodoroPreset: String?
        }

        let taskTitle: String
        let subtasks: [Subtask]
        let estimatedPomodoros: Int
    }

    typealias TaskBreakdownResponse = AIPlanningResponse
    typealias TaskPlanningResponse = AIPlanningResponse

    struct TaskDescriptionResponse: Decodable {
        let description: String
    }

    struct TaskDraftResponse: Equatable {
        let title: String
        let description: String
        let subtasks: [String]
        let estimatedPomodoros: Int?
        let priority: TodoItem.Priority?
        let tags: [String]
        let focusStyle: String?
    }

    struct EventTaskSuggestionResponse: Equatable {
        let tasks: [String]
    }

    struct FreeSlot: Codable, Equatable {
        let start: Date
        let end: Date
    }

    struct AIScheduleResponse: Codable {
        struct Metadata: Codable {
            let generationPath: String
            let reliability: Double
        }

        let success: Bool
        let schedule: [ScheduleBlock]
        let freeSlots: [FreeSlot]
        let metadata: Metadata?

        init(
            success: Bool,
            schedule: [ScheduleBlock],
            freeSlots: [FreeSlot] = [],
            metadata: Metadata? = nil
        ) {
            self.success = success
            self.schedule = schedule
            self.freeSlots = freeSlots
            self.metadata = metadata
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
            schedule = try container.decodeIfPresent([ScheduleBlock].self, forKey: .schedule) ?? []
            freeSlots = try container.decodeIfPresent([FreeSlot].self, forKey: .freeSlots) ?? []
            metadata = try container.decodeIfPresent(Metadata.self, forKey: .metadata)
        }
    }

    struct ScheduleBlock: Codable {
        let taskId: String
        let taskTitle: String
        let eventId: String
        let start: Date
        let end: Date
        let pomodoros: Int
        let pomodoroPreset: String?
        let calendarWritable: Bool

        init(
            taskId: String,
            taskTitle: String,
            eventId: String = "",
            start: Date,
            end: Date,
            pomodoros: Int,
            pomodoroPreset: String? = nil,
            calendarWritable: Bool = true
        ) {
            self.taskId = taskId
            self.taskTitle = taskTitle
            self.eventId = eventId
            self.start = start
            self.end = end
            self.pomodoros = pomodoros
            self.pomodoroPreset = pomodoroPreset
            self.calendarWritable = calendarWritable
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            taskId = try container.decode(String.self, forKey: .taskId)
            taskTitle = try container.decode(String.self, forKey: .taskTitle)
            eventId = try container.decodeIfPresent(String.self, forKey: .eventId) ?? ""
            start = try container.decode(Date.self, forKey: .start)
            end = try container.decode(Date.self, forKey: .end)
            pomodoros = try container.decodeIfPresent(Int.self, forKey: .pomodoros) ?? 1
            pomodoroPreset = try container.decodeIfPresent(String.self, forKey: .pomodoroPreset)
            calendarWritable = try container.decodeIfPresent(Bool.self, forKey: .calendarWritable) ?? true
        }
    }

    struct SchedulingPreferences {
        let pomodoroLength: Int
        let breakLength: Int
        let workingHoursStart: String
        let workingHoursEnd: String

        init(
            pomodoroLength: Int? = nil,
            breakLength: Int? = nil,
            workingHoursStart: String = "08:00",
            workingHoursEnd: String = "22:00"
        ) {
            let fallbackPreset = Preset.shortestBuiltIn
            self.pomodoroLength = pomodoroLength ?? max(1, fallbackPreset.durationConfig.workDuration / 60)
            self.breakLength = breakLength ?? max(0, fallbackPreset.durationConfig.shortBreakDuration / 60)
            self.workingHoursStart = workingHoursStart
            self.workingHoursEnd = workingHoursEnd
        }
    }

    private struct CalendarRescheduleRequest: Encodable {
        struct TaskPayload: Encodable {
            let id: String
            let title: String
            let estimatedPomodoros: Int
            let priority: Int
            let deadline: String?
        }

        struct CalendarEventPayload: Encodable {
            let eventId: String
            let title: String
            let start: Date
            let end: Date
            let calendarWritable: Bool
            let isSubscribed: Bool
            let subscribed: Bool
            let readOnly: Bool
            let calendarReadOnly: Bool
        }

        struct PreferencesPayload: Encodable {
            struct PresetPayload: Encodable {
                let id: String
                let workMinutes: Int
                let shortBreakMinutes: Int
            }

            let pomodoroLength: Int
            let breakLength: Int
            let workingHoursStart: String
            let workingHoursEnd: String
            let pomodoroPresets: [PresetPayload]
        }

        let uid: String?
        let tasks: [TaskPayload]
        let calendarEvents: [CalendarEventPayload]
        let freeSlots: [FreeSlot]
        let preferences: PreferencesPayload
        let preferredDayEnd: Date?
        /// When set to "today" the cloud function clamps scheduling to today only.
        let rescheduleScope: String?
    }

    enum AIServiceError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "AI planning returned an invalid response."
            }
        }
    }

    static let shared = AIService()

    private let functions: Functions
    private let aiProxyClient: AIProxyClient
    private let insightsCache: AIInsightCacheStore

    private init(functions: Functions? = nil) {
        self.aiProxyClient = AIProxyClient()
        self.insightsCache = .shared
        if let functions {
            self.functions = functions
        } else {
            self.functions = Functions.functions(region: "us-central1")
        }
    }

    func taskBreakdown(task: String, deadline: String, estimatedHours: Int) async throws -> TaskBreakdownResponse {
        let request = TaskBreakdownRequest(
            task: task,
            deadline: deadline,
            estimatedHours: estimatedHours
        )
        let callable = functions.httpsCallable("taskBreakdown")
        let payload: [String: Any] = [
            "task": request.task,
            "deadline": request.deadline,
            "estimatedHours": request.estimatedHours
        ]

        print("[AIService] Calling callable taskBreakdown in us-central1 for task: \(task)")
        let result = try await callable.call(payload)
        print("[AIService] taskBreakdown response received")
        return try decodeAIPlanningResponse(from: result.data)
    }

    func taskPlanning(tasks: [String], deadline: String, estimatedHours: Int) async throws -> TaskPlanningResponse {
        let request = TaskPlanningRequest(
            tasks: tasks,
            deadline: deadline,
            estimatedHours: estimatedHours,
            pomodoroPresets: Self.schedulerPresetPayloads
        )
        let callable = functions.httpsCallable("taskPlanning")
        let payload: [String: Any] = [
            "tasks": request.tasks,
            "deadline": request.deadline,
            "estimatedHours": request.estimatedHours,
            "pomodoroPresets": request.pomodoroPresets.map { [
                "id": $0.id,
                "workMinutes": $0.workMinutes,
                "shortBreakMinutes": $0.shortBreakMinutes
            ] }
        ]

        print("[AIService] Calling callable taskPlanning in us-central1 for \(tasks.count) tasks")
        let result = try await callable.call(payload)
        print("[AIService] taskPlanning response received")
        return try decodeAIPlanningResponse(from: result.data)
    }

    func generateTaskDescription(title: String, notes: String?) async throws -> TaskDescriptionResponse {
        let callable = functions.httpsCallable("generateTaskDescription")
        let payload: [String: Any] = [
            "title": title,
            "notes": notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ]

        print("[AIService] Calling callable generateTaskDescription in us-central1 for title: \(title)")
        let result = try await callable.call(payload)
        print("[AIService] generateTaskDescription response received")
        return try decodeTaskDescriptionResponse(from: result.data)
    }

    func draftTask(
        idea: String,
        existingTitle: String? = nil,
        existingDescription: String? = nil
    ) async throws -> TaskDraftResponse {
        let trimmedIdea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = existingTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = existingDescription?.trimmingCharacters(in: .whitespacesAndNewlines)

        let prompt = """
        You are drafting a structured task for a Pomodoro productivity app.
        Return strict JSON only. No markdown fences. No commentary.

        Required JSON shape:
        {
          "title": "short task title",
          "description": "2-5 sentence markdown-friendly task description",
          "subtasks": ["step 1", "step 2"],
          "estimatedPomodoros": 1,
          "priority": "none|low|medium|high",
          "tags": ["tag-a", "tag-b"],
          "focusStyle": "deep work | admin | creative | planning | communication"
        }

        Rules:
        - Keep the title concise and actionable.
        - Description should clarify scope and outcome, not add filler.
        - Provide 0 to 6 subtasks only when they help.
        - estimatedPomodoros must be an integer from 1 to 12.
        - tags must be short lowercase phrases when present.
        - focusStyle should be one short label if relevant, otherwise an empty string.

        User input:
        {
          "idea": \(Self.jsonStringLiteral(trimmedIdea)),
          "existingTitle": \(Self.jsonStringLiteral(trimmedTitle ?? "")),
          "existingDescription": \(Self.jsonStringLiteral(trimmedDescription ?? ""))
        }
        """

        let response: AIProxyClient.ProxyResponse = try await aiProxyClient.sendPrompt(
            .init(
                prompt: prompt,
                modelFamily: "deepseek",
                featureType: "quick_chat",
                temperature: 0.2,
                maxOutputTokens: 260,
                metadata: [
                    "insight_kind": "task_draft"
                ]
            )
        )

        return try decodeTaskDraftResponse(from: response.outputText)
    }

    func generateEventTasks(eventTitle: String, description: String?) async throws -> EventTaskSuggestionResponse {
        let trimmedTitle = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let prompt = """
        You are generating actionable task suggestions for a calendar event in a productivity app.
        Return strict JSON only. No markdown fences. No commentary.

        Required JSON shape:
        {
          "tasks": [
            { "title": "..." },
            { "title": "..." }
          ]
        }

        Rules:
        - Generate 3 to 7 tasks.
        - Each task title must be short, concrete, and actionable.
        - Avoid duplicates and vague items.
        - Base the tasks only on the event title and optional description.

        User input:
        {
          "eventTitle": \(Self.jsonStringLiteral(trimmedTitle)),
          "description": \(Self.jsonStringLiteral(trimmedDescription))
        }
        """

        let response: AIProxyClient.ProxyResponse = try await aiProxyClient.sendPrompt(
            .init(
                prompt: prompt,
                modelFamily: "deepseek",
                featureType: "quick_chat",
                temperature: 0.2,
                maxOutputTokens: 220,
                metadata: [
                    "insight_kind": "event_task_generation"
                ]
            )
        )

        return try decodeEventTaskSuggestionResponse(from: response.outputText)
    }

    func calendarReschedule(
        tasks: [TodoItem],
        events: [EKEvent],
        freeSlots: [FreeSlot],
        preferences: SchedulingPreferences? = nil,
        preferredDayEnd: Date? = nil
    ) async throws -> AIScheduleResponse {
        let effectivePreferences = preferences ?? SchedulingPreferences()
        let uid = Auth.auth().currentUser?.uid
        let requestBody = CalendarRescheduleRequest(
            uid: uid,
            tasks: tasks.map { task in
                CalendarRescheduleRequest.TaskPayload(
                    id: task.id.uuidString,
                    title: task.title,
                    estimatedPomodoros: task.pomodoroEstimate ?? 1,
                    priority: max(1, task.priority.rawValue),
                    deadline: task.dueDate?.ISO8601Format()
                )
            },
            calendarEvents: events.compactMap { event in
                guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
                let isSubscribed = event.calendar.type == .subscription
                let calendarWritable = event.calendar.allowsContentModifications && !isSubscribed
                return CalendarRescheduleRequest.CalendarEventPayload(
                    eventId: event.eventIdentifier ?? "",
                    title: event.title ?? "Busy",
                    start: startDate,
                    end: endDate,
                    calendarWritable: calendarWritable,
                    isSubscribed: isSubscribed,
                    subscribed: isSubscribed,
                    readOnly: !calendarWritable,
                    calendarReadOnly: !calendarWritable
                )
            },
            freeSlots: freeSlots,
            preferences: CalendarRescheduleRequest.PreferencesPayload(
                pomodoroLength: effectivePreferences.pomodoroLength,
                breakLength: effectivePreferences.breakLength,
                workingHoursStart: effectivePreferences.workingHoursStart,
                workingHoursEnd: effectivePreferences.workingHoursEnd,
                pomodoroPresets: Self.schedulerPresetPreferencePayloads
            ),
            preferredDayEnd: preferredDayEnd,
            rescheduleScope: "today"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(requestBody)
        if let requestString = String(data: body, encoding: .utf8) {
            print("[AIService] generateCalendarSchedule payload: \(requestString)")
        }

        let jsonObject = try JSONSerialization.jsonObject(with: body)
        guard let payload = jsonObject as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        let callable = functions.httpsCallable("generateCalendarSchedule")
        callable.timeoutInterval = 60
        print("[AIService] Calling callable generateCalendarSchedule in us-central1")
        let result = try await callable.call(payload)
        if let data = result.data as? [String: Any] {
            print("[AIService] callable response: \(data)")
        }

        return try decodeCalendarScheduleResponse(from: result.data)
    }

    private func decodeAIPlanningResponse(from data: Any) throws -> AIPlanningResponse {
        let rawObject: Any
        if let dictionary = data as? [String: Any],
           let nested = dictionary["data"] {
            rawObject = nested
        } else {
            rawObject = data
        }

        guard JSONSerialization.isValidJSONObject(rawObject) else {
            throw AIServiceError.invalidResponse
        }

        let responseData = try JSONSerialization.data(withJSONObject: rawObject)
        return try JSONDecoder().decode(AIPlanningResponse.self, from: responseData)
    }

    private func decodeCalendarScheduleResponse(from data: Any) throws -> AIScheduleResponse {
        let rawObject: Any
        if let dictionary = data as? [String: Any],
           let nested = dictionary["data"] {
            rawObject = nested
        } else {
            rawObject = data
        }

        guard JSONSerialization.isValidJSONObject(rawObject) else {
            throw AIServiceError.invalidResponse
        }

        let responseData = try JSONSerialization.data(withJSONObject: rawObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
            if let date = fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }

        if let envelope = try? decoder.decode(CalendarScheduleEnvelope.self, from: responseData) {
            return envelope.data
        }
        return try decoder.decode(AIScheduleResponse.self, from: responseData)
    }

    private func decodeTaskDescriptionResponse(from data: Any) throws -> TaskDescriptionResponse {
        let rawObject: Any
        if let dictionary = data as? [String: Any],
           let nested = dictionary["data"] {
            rawObject = nested
        } else {
            rawObject = data
        }

        guard JSONSerialization.isValidJSONObject(rawObject) else {
            throw AIServiceError.invalidResponse
        }

        let responseData = try JSONSerialization.data(withJSONObject: rawObject)
        return try JSONDecoder().decode(TaskDescriptionResponse.self, from: responseData)
    }

    private func decodeTaskDraftResponse(from value: String?) throws -> TaskDraftResponse {
        guard let json = extractJSONObjectString(from: value) else {
            throw AIServiceError.invalidResponse
        }

        struct RawTaskDraftResponse: Decodable {
            let title: String?
            let description: String?
            let subtasks: [String]?
            let estimatedPomodoros: Int?
            let priority: String?
            let tags: [String]?
            let focusStyle: String?
        }

        let data = Data(json.utf8)
        let raw = try JSONDecoder().decode(RawTaskDraftResponse.self, from: data)
        let title = (raw.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (raw.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty || !description.isEmpty else {
            throw AIServiceError.invalidResponse
        }

        let subtasks = (raw.subtasks ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(6)

        let tags = (raw.tags ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let focusStyle = raw.focusStyle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPriority = normalizePriority(raw.priority)

        return TaskDraftResponse(
            title: title,
            description: description,
            subtasks: Array(subtasks),
            estimatedPomodoros: raw.estimatedPomodoros.map { min(max($0, 1), 12) },
            priority: normalizedPriority,
            tags: Array(NSOrderedSet(array: tags)) as? [String] ?? tags,
            focusStyle: (focusStyle?.isEmpty == false) ? focusStyle : nil
        )
    }

    private func decodeEventTaskSuggestionResponse(from value: String?) throws -> EventTaskSuggestionResponse {
        guard let json = extractJSONObjectString(from: value) else {
            throw AIServiceError.invalidResponse
        }

        struct RawResponse: Decodable {
            struct Task: Decodable {
                let title: String?
            }
            let tasks: [Task]?
        }

        let data = Data(json.utf8)
        let raw = try JSONDecoder().decode(RawResponse.self, from: data)
        let tasks = (raw.tasks ?? [])
            .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let uniqueTasks = Array(NSOrderedSet(array: tasks)) as? [String] ?? tasks
        let limitedTasks = Array(uniqueTasks.prefix(7))
        guard !limitedTasks.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return EventTaskSuggestionResponse(tasks: limitedTasks)
    }

    private func extractJSONObjectString(from value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("```") {
            let unfenced = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if let start = unfenced.firstIndex(of: "{"),
               let end = unfenced.lastIndex(of: "}") {
                return String(unfenced[start...end])
            }
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return String(trimmed[start...end])
    }

    private func normalizePriority(_ value: String?) -> TodoItem.Priority? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high":
            return .high
        case "medium":
            return .medium
        case "low":
            return .low
        case "none":
            return TodoItem.Priority.none
        default:
            return nil
        }
    }

    private struct CalendarScheduleEnvelope: Decodable {
        let data: AIScheduleResponse
    }

    private static var schedulerPresetPayloads: [TaskPlanningRequest.PresetPayload] {
        Preset.builtIn.map {
            TaskPlanningRequest.PresetPayload(
                id: $0.id,
                workMinutes: max(1, $0.durationConfig.workDuration / 60),
                shortBreakMinutes: max(0, $0.durationConfig.shortBreakDuration / 60)
            )
        }
    }

    private static var schedulerPresetPreferencePayloads: [CalendarRescheduleRequest.PreferencesPayload.PresetPayload] {
        Preset.builtIn.map {
            CalendarRescheduleRequest.PreferencesPayload.PresetPayload(
                id: $0.id,
                workMinutes: max(1, $0.durationConfig.workDuration / 60),
                shortBreakMinutes: max(0, $0.durationConfig.shortBreakDuration / 60)
            )
        }
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        let encoded = try? JSONEncoder().encode(value)
        return encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

extension AIService {
    enum SummaryInsightSection: String, CaseIterable, Codable {
        case weeklyFocusTrend
        case dailyCompletionTrend
        case focusBreakRatio
        case focusByHour
        case sessionLengthDistribution
        case taskCompletion

        var cacheKey: String { rawValue }

        var displayName: String {
            switch self {
            case .weeklyFocusTrend: return "Weekly Focus Trend"
            case .dailyCompletionTrend: return "Daily Completion Trend"
            case .focusBreakRatio: return "Focus vs Break Ratio"
            case .focusByHour: return "Focus by Hour"
            case .sessionLengthDistribution: return "Session Length Distribution"
            case .taskCompletion: return "Task Completion"
            }
        }
    }

    struct ProductivityTaskSummary: Codable, Equatable {
        let totalTasks: Int
        let completedTasks: Int
        let activeTasks: Int

        var completionRate: Double {
            guard totalTasks > 0 else { return 0 }
            return Double(completedTasks) / Double(totalTasks)
        }

        static func from(items: [TodoItem]) -> ProductivityTaskSummary {
            let completed = items.filter(\.isCompleted).count
            let total = items.count
            return ProductivityTaskSummary(
                totalTasks: total,
                completedTasks: completed,
                activeTasks: max(0, total - completed)
            )
        }
    }

    struct ProductivityInsightResult: Equatable {
        let text: String
        let usedModelFamily: String?
        let generatedAt: Date
        let isFallback: Bool
        let cacheKey: String
    }

    enum ProductivityInsightMetric: String, CaseIterable, Codable {
        case totalFocusTime
        case sessionCount
        case streakDays
        case averageSessionLength
        case focusQualityScore
        case consistencyScore
        case shortSessionRatio
        case focusByHour
        case breakFocusRatio

        var isComplex: Bool {
            switch self {
            case .focusQualityScore, .consistencyScore, .shortSessionRatio, .focusByHour, .breakFocusRatio:
                return true
            case .totalFocusTime, .sessionCount, .streakDays, .averageSessionLength:
                return false
            }
        }

        var featureType: String {
            "insights_metric_simple"
        }

        var modelFamily: String {
            "deepseek"
        }

        var displayName: String {
            switch self {
            case .totalFocusTime: return "Total Focus Time"
            case .sessionCount: return "Session Count"
            case .streakDays: return "Streak Days"
            case .averageSessionLength: return "Average Session Length"
            case .focusQualityScore: return "Focus Quality Score"
            case .consistencyScore: return "Consistency Score"
            case .shortSessionRatio: return "Short Session Ratio"
            case .focusByHour: return "Time-of-Day Efficiency"
            case .breakFocusRatio: return "Break-to-Focus Ratio"
            }
        }
    }

    func generateSummarySectionInsight(
        for section: SummaryInsightSection,
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary,
        now: Date = Date()
    ) async -> ProductivityInsightResult {
        let fallback = summarySectionFallback(section, snapshot: snapshot, taskSummary: taskSummary)
        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        let payload = StructuredSummaryInsightPayload(section: section, input: input)
        let canRunLightweight = FeatureGate.shared.canUseAIWeeklyOverview
        let cacheKey = "summary-section-\(section.cacheKey)-deepseek-\(cacheDayKey(for: now))-\(payload.cacheHash)"

        if let cached = insightsCache.cachedResult(for: cacheKey, now: now) {
            return cached
        }

        guard canRunLightweight else {
            return ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: cacheKey
            )
        }

        let prompt = """
        You are writing a brief productivity insight for one Summary section in a Pomodoro app.
        Focus only on \(section.displayName).
        Keep the answer to 1-3 short sentences.
        Describe patterns simply and directly. Do not use deep reasoning.

        Structured input:
        \(payload.jsonString)
        """
        let modelFamily = "deepseek"
        let featureType = "insights_weekly_overview"
        let maxOutputTokens = 110

        do {
            let response: AIProxyClient.ProxyResponse = try await aiProxyClient.sendPrompt(
                .init(
                    prompt: prompt,
                    modelFamily: modelFamily,
                    featureType: featureType,
                    temperature: 0.2,
                    maxOutputTokens: maxOutputTokens,
                    metadata: [
                        "insight_kind": "summary_section",
                        "summary_section": section.rawValue
                    ]
                )
            )
            let text = sanitizeInsightText(response.outputText) ?? fallback
            let result = ProductivityInsightResult(
                text: text,
                usedModelFamily: response.modelFamily ?? modelFamily,
                generatedAt: now,
                isFallback: text == fallback,
                cacheKey: cacheKey
            )
            insightsCache.store(result, for: cacheKey, expiresAt: now.addingTimeInterval(12 * 60 * 60))
            return result
        } catch {
            let result = ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: cacheKey
            )
            insightsCache.store(result, for: cacheKey, expiresAt: now.addingTimeInterval(6 * 60 * 60))
            return result
        }
    }

    func generateWeeklyOverview(
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary,
        now: Date = Date()
    ) async -> ProductivityInsightResult {
        let fallback = weeklyOverviewFallback(snapshot: snapshot, taskSummary: taskSummary)
        guard FeatureGate.shared.canUseAIWeeklyOverview else {
            return ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: "weekly-overview-unavailable"
            )
        }

        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        let isProSummary = FeatureGate.shared.canUseAIDeepAnalysis
        let payload = StructuredInsightPayload(
            kind: "weekly_overview",
            input: input,
            metric: nil
        )
        let cacheKey = "weekly-overview-\(isProSummary ? "gemini" : "deepseek")-\(cacheWeekKey(for: now))-\(payload.cacheHash)"
        if let cached = insightsCache.cachedResult(for: cacheKey, now: now) {
            return cached
        }

        let prompt: String
        let model: String?
        let modelFamily: String
        let featureType: String
        let maxOutputTokens: Int

        if isProSummary {
            prompt = """
            You are writing a premium weekly summary for a Pomodoro app user.
            Keep the answer to 4-6 concise sentences.
            Summarize the week as a clear executive-style readout, not a deep analysis report.
            Prefer trends like best focus window, consistency, quality, completion, overload risk, imbalance, and task drift when supported by the data.
            Do not explain individual metrics or small sections.
            Do not provide chain-of-thought.

            Structured input:
            \(payload.jsonString)
            """
            model = Self.proDeepAnalysisModel
            modelFamily = "gemini"
            featureType = "insights_summary"
            maxOutputTokens = 220
        } else {
            prompt = """
            You are writing a weekly productivity overview for a Pomodoro app user.
            Keep the answer to 3-5 short sentences.
            Describe trends clearly. Do not provide deep reasoning, chain-of-thought, or long explanations.
            Prefer observations like trend direction, best focus window, streaks, task completion, overload risk, imbalance, and task drift when supported by the data.
            If data is mixed, stay specific and neutral.

            Structured input:
            \(payload.jsonString)
            """
            model = nil
            modelFamily = "deepseek"
            featureType = "insights_weekly_overview"
            maxOutputTokens = 140
        }

        do {
            let response: AIProxyClient.ProxyResponse = try await aiProxyClient.sendPrompt(
                .init(
                    prompt: prompt,
                    model: model,
                    modelFamily: modelFamily,
                    featureType: featureType,
                    temperature: 0.2,
                    maxOutputTokens: maxOutputTokens,
                    metadata: [
                        "insight_kind": "weekly_overview",
                        "analytics_level": FeatureGate.shared.analyticsLevel.rawValue
                    ]
                )
            )
            let text = sanitizeInsightText(response.outputText) ?? fallback
            let result = ProductivityInsightResult(
                text: text,
                usedModelFamily: response.modelFamily ?? modelFamily,
                generatedAt: now,
                isFallback: text == fallback,
                cacheKey: cacheKey
            )
            insightsCache.store(result, for: cacheKey, expiresAt: cacheWeekExpiry(for: now))
            return result
        } catch {
            let result = ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: cacheKey
            )
            insightsCache.store(result, for: cacheKey, expiresAt: now.addingTimeInterval(12 * 60 * 60))
            return result
        }
    }

    func generateDeepAnalysis(
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary,
        now: Date = Date()
    ) async -> ProductivityInsightResult {
        print("🚀 Deep Analysis started")
        let fallback = deepAnalysisFallback(snapshot: snapshot, taskSummary: taskSummary)
        guard FeatureGate.shared.canUseAIDeepAnalysis else {
            print("❌ Deep Analysis blocked by entitlement. tier=\(FeatureGate.shared.tier.rawValue) aiLevel=\(FeatureGate.shared.aiLevel.rawValue) dailyRemaining=\(FeatureGate.shared.dailyAIUsage.remaining.map(String.init) ?? "nil")")
            print("⚠️ Using fallback analysis")
            return ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: "deep-analysis-unavailable"
            )
        }

        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        let payload = StructuredInsightPayload(
            kind: "deep_analysis",
            input: input,
            metric: nil
        )
        let cacheKey = "deep-analysis-\(cacheDayKey(for: now))-\(payload.cacheHash)"
        if let cached = insightsCache.cachedResult(for: cacheKey, now: now), !cached.isFallback {
            print("✅ Deep Analysis served from cache")
            return cached
        }

        let prompt = """
        You are analyzing structured productivity metrics for a Pomodoro app user.
        Use only the provided structured data. Do not infer raw logs or hidden causes.
        This is a Pro-only deep analysis request and must feel materially deeper than a short summary.
        If the dataset is weak or empty, you must still provide a useful onboarding-style deep analysis based on the available structured input.
        Explicitly acknowledge when the user is early in their tracking history and explain what patterns cannot be confirmed yet.
        Requirements:
        - Organize the response into clear parts for Summary, Insights, and Recommendations.
        - Be concrete and evidence-based.
        - Explain why each pattern matters using the provided metrics.
        - Call out consistency, focus quality, short-session behavior, break/focus balance, peak hours, completion behavior, overload risk, imbalance, and task drift when supported.
        - Recommendations must be actionable and specific, not generic.
        - Do not mention missing raw logs or hidden causes.
        - If there are no focus sessions yet, explain what the current task/activity context suggests and what the user should do to generate better insight next week.
        - You may choose the best structure for those parts. A natural report format is preferred over a rigid template.
        - The response should be longer and more reflective than a weekly overview, but still readable in one screen.
        - It is fine to use headings, short paragraphs, and bullet points when helpful.
        - Include concrete interpretation, not just metric restatement.

        Structured input:
        \(payload.jsonString)
        """

        do {
            print("📡 Calling AI API for Deep Analysis model=\(Self.proDeepAnalysisModel)")
            let response: AIProxyClient.ProxyResponse = try await aiProxyClient.sendPrompt(
                .init(
                    prompt: prompt,
                    model: Self.proDeepAnalysisModel,
                    modelFamily: "gemini",
                    featureType: "insights_deep_analysis",
                    temperature: 0.2,
                    maxOutputTokens: 900,
                    metadata: [
                        "insight_kind": "deep_analysis",
                        "analytics_level": FeatureGate.shared.analyticsLevel.rawValue
                    ]
                )
            )
            print("✅ AI response received for Deep Analysis")
            let text = sanitizeInsightText(response.outputText) ?? fallback
            if text == fallback {
                print("⚠️ Using fallback analysis")
            }
            let result = ProductivityInsightResult(
                text: text,
                usedModelFamily: response.modelFamily ?? "gemini",
                generatedAt: now,
                isFallback: text == fallback,
                cacheKey: cacheKey
            )
            insightsCache.store(result, for: cacheKey, expiresAt: now.addingTimeInterval(24 * 60 * 60))
            return result
        } catch {
            print("❌ AI call failed: \(error)")
            print("⚠️ Using fallback analysis")
            return ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: cacheKey
            )
        }
    }

    func analyzeMetric(
        _ metric: ProductivityInsightMetric,
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary,
        now: Date = Date()
    ) async -> ProductivityInsightResult {
        let fallback = metricFallback(metric, snapshot: snapshot, taskSummary: taskSummary)
        guard FeatureGate.shared.canUseAIWeeklyOverview else {
            return ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: "metric-\(metric.rawValue)-unavailable"
            )
        }

        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        let payload = StructuredInsightPayload(
            kind: "metric_analysis",
            input: input,
            metric: metric
        )
        let cacheKey = "metric-\(metric.rawValue)-\(cacheDayKey(for: now))-\(payload.cacheHash)"
        if let cached = insightsCache.cachedResult(for: cacheKey, now: now), !cached.isFallback {
            return cached
        }

        let prompt = """
        You are explaining one productivity metric for a Pomodoro app user.
        Focus only on the metric named \(metric.displayName).
        Return 2-4 concise sentences and one specific suggestion.
        Explain what the metric likely means for the user's work pattern using only the structured data.
        Do not generate a full report.

        Structured input:
        \(payload.jsonString)
        """

        do {
            let response: AIProxyClient.ProxyResponse = try await aiProxyClient.sendPrompt(
                .init(
                    prompt: prompt,
                    model: nil,
                    modelFamily: metric.modelFamily,
                    featureType: metric.featureType,
                    temperature: 0.2,
                    maxOutputTokens: metric.isComplex ? 240 : 110,
                    metadata: [
                        "insight_kind": "metric_analysis",
                        "metric": metric.rawValue
                    ]
                )
            )
            let text = sanitizeInsightText(response.outputText) ?? fallback
            let result = ProductivityInsightResult(
                text: text,
                usedModelFamily: response.modelFamily ?? metric.modelFamily,
                generatedAt: now,
                isFallback: text == fallback,
                cacheKey: cacheKey
            )
            insightsCache.store(result, for: cacheKey, expiresAt: now.addingTimeInterval(12 * 60 * 60))
            return result
        } catch {
            return ProductivityInsightResult(
                text: fallback,
                usedModelFamily: nil,
                generatedAt: now,
                isFallback: true,
                cacheKey: cacheKey
            )
        }
    }

    private func sanitizeInsightText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func cacheWeekKey(for date: Date) -> String {
        let calendar = Calendar(identifier: .iso8601)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return "\(year)-W\(week)"
    }

    private func cacheDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func cacheWeekExpiry(for date: Date) -> Date {
        let calendar = Calendar(identifier: .iso8601)
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? date.addingTimeInterval(7 * 24 * 60 * 60)
    }

    private func weeklyOverviewFallback(
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary
    ) -> String {
        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        return "\(input.weeklyTrendSummary) \(input.peakHourSummary) \(input.taskSummaryText) \(input.patternWarningSummary)"
    }

    private func deepAnalysisFallback(
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary
    ) -> String {
        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        return """
        Summary:
        \(input.weeklyTrendSummary)

        Key Insights:
        - \(input.consistencySummary)
        - \(input.completionSummary)
        - \(input.peakHourSummary)
        - \(input.patternWarningSummary)

        Recommendations:
        - \(input.recommendationSummary)
        """
    }

    private func metricFallback(
        _ metric: ProductivityInsightMetric,
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary
    ) -> String {
        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        switch metric {
        case .totalFocusTime:
            return input.weeklyTrendSummary
        case .sessionCount:
            return "You completed \(input.completedSessions) of \(input.totalSessions) tracked sessions in the current analytics window."
        case .streakDays:
            return "Your current focus streak is \(input.streakDays) day\(input.streakDays == 1 ? "" : "s"). Keep at least one completed focus session each day to maintain it."
        case .averageSessionLength:
            return "Your average session length is \(input.averageSessionMinutes)m, with a longest session of \(input.longestSessionMinutes)m."
        case .focusQualityScore:
            return "Your focus quality score is \(input.focusQualityScoreText), shaped by session length, completion rate, and short-session frequency."
        case .consistencyScore:
            return input.consistencySummary
        case .shortSessionRatio:
            return "Short sessions make up \(input.shortSessionRatioText) of your tracked sessions. Reducing early exits should improve focus quality."
        case .focusByHour:
            return input.peakHourSummary
        case .breakFocusRatio:
            return "Your break-to-focus ratio is \(input.breakFocusRatioText). If breaks feel too frequent, try extending the next focus block before pausing."
        }
    }

    private func summarySectionFallback(
        _ section: SummaryInsightSection,
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: ProductivityTaskSummary
    ) -> String {
        let input = ProductivityAIInput(snapshot: snapshot, taskSummary: taskSummary)
        switch section {
        case .weeklyFocusTrend:
            return input.weeklyTrendSummary
        case .dailyCompletionTrend:
            return "You completed \(input.completedSessions) of \(input.totalSessions) tracked sessions in this analytics window."
        case .focusBreakRatio:
            return "Your break-to-focus ratio is \(input.breakFocusRatioText), which shows how much recovery time you take relative to focused work."
        case .focusByHour:
            return input.peakHourSummary
        case .sessionLengthDistribution:
            return "Your average session length is \(input.averageSessionMinutes)m, and your longest session reached \(input.longestSessionMinutes)m."
        case .taskCompletion:
            return input.taskSummaryText
        }
    }
}

private struct StructuredInsightPayload: Encodable {
    let kind: String
    let input: ProductivityAIInput
    let metric: AIService.ProductivityInsightMetric?

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    var cacheHash: String {
        let digest = SHA256.hash(data: Data(jsonString.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private struct StructuredSummaryInsightPayload: Encodable {
    let section: AIService.SummaryInsightSection
    let input: ProductivityAIInput

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    var cacheHash: String {
        let digest = SHA256.hash(data: Data(jsonString.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private struct ProductivityAIInput: Encodable {
    let avgFocusMinutes7Days: Int
    let avgFocusMinutes30Days: Int
    let weeklyTrendDirection: String
    let monthlyTrendDirection: String
    let streakDays: Int
    let totalSessions: Int
    let completedSessions: Int
    let completionRate: Double
    let averageSessionMinutes: Int
    let longestSessionMinutes: Int
    let focusQualityScore: Double
    let consistencyScore: Double
    let shortSessionRatio: Double
    let breakFocusRatio: Double
    let peakHours: [Int]
    let lowFocusHours: [Int]
    let focusTrend7Days: [Int]
    let focusTrend30Days: [Int]
    let taskCompletionRate: Double
    let totalTasks: Int
    let completedTasks: Int
    let activeTasks: Int
    let anomalyFlags: [String]
    let dataAvailability: String
    let noDataSummary: String

    init(snapshot: ProductivityAnalyticsSnapshot, taskSummary: AIService.ProductivityTaskSummary) {
        avgFocusMinutes7Days = Self.averageMinutes(from: snapshot.focusTrend7Days)
        avgFocusMinutes30Days = Self.averageMinutes(from: snapshot.focusTrend30Days)
        weeklyTrendDirection = Self.trendDirection(from: snapshot.focusTrend7Days)
        monthlyTrendDirection = Self.trendDirection(from: snapshot.focusTrend30Days)
        streakDays = snapshot.insights.streakDays
        totalSessions = snapshot.dailyAggregates.reduce(0) { $0 + $1.totalSessions }
        completedSessions = snapshot.dailyAggregates.reduce(0) { $0 + $1.completedSessions }
        completionRate = snapshot.insights.completionRate
        averageSessionMinutes = Int((snapshot.insights.averageSessionLengthSeconds / 60).rounded())
        longestSessionMinutes = Int((Double(snapshot.insights.longestSessionSeconds) / 60).rounded())
        focusQualityScore = snapshot.insights.focusQualityScore
        consistencyScore = snapshot.insights.consistencyScore
        shortSessionRatio = snapshot.insights.shortSessionRatio
        breakFocusRatio = snapshot.insights.breakFocusRatio
        peakHours = Self.topHours(from: snapshot.focusByHour, highest: true)
        lowFocusHours = Self.topHours(from: snapshot.focusByHour, highest: false)
        focusTrend7Days = snapshot.focusTrend7Days.map { Int($0.value.rounded()) }
        focusTrend30Days = snapshot.focusTrend30Days.map { Int($0.value.rounded()) }
        taskCompletionRate = taskSummary.completionRate
        totalTasks = taskSummary.totalTasks
        completedTasks = taskSummary.completedTasks
        activeTasks = taskSummary.activeTasks
        anomalyFlags = Self.anomalyFlags(snapshot: snapshot, taskSummary: taskSummary)
        dataAvailability = Self.dataAvailability(snapshot: snapshot, taskSummary: taskSummary)
        noDataSummary = Self.noDataSummaryText(snapshot: snapshot, taskSummary: taskSummary)
    }

    var weeklyTrendSummary: String {
        "Your 7-day focus trend is \(weeklyTrendDirection), averaging \(avgFocusMinutes7Days) minutes per day."
    }

    var peakHourSummary: String {
        guard !peakHours.isEmpty else { return "Your focus pattern does not yet show a clear peak hour." }
        let hours = peakHours.map(Self.hourLabel).joined(separator: ", ")
        return "Your strongest focus periods are around \(hours)."
    }

    var taskSummaryText: String {
        guard totalTasks > 0 else { return "You have no tracked tasks in this window." }
        return "You completed \(completedTasks) of \(totalTasks) tasks."
    }

    var consistencySummary: String {
        "Your consistency score is \(consistencyScoreText), which means your daily focus pattern is \(consistencyDescriptor)."
    }

    var completionSummary: String {
        "You complete \(completionRateText) of tracked sessions and \(taskCompletionRateText) of tracked tasks."
    }

    var patternWarningSummary: String {
        if anomalyFlags.contains("high_short_session_ratio") {
            return "Short sessions are interrupting your flow often, which suggests drift or low-friction context switching."
        }
        if anomalyFlags.contains("low_consistency") {
            return "Your focus pattern is uneven enough to suggest an imbalance between strong and weak workdays."
        }
        if anomalyFlags.contains("high_break_focus_ratio") {
            return "Break time is running high relative to focus time, which may point to overload or fragmented sessions."
        }
        if activeTasks > completedTasks, activeTasks >= 6 {
            return "You have more active tasks than completed ones, which may signal task drift or overcommitment."
        }
        return "Your workload looks reasonably balanced in the current window."
    }

    var recommendationSummary: String {
        if shortSessionRatio >= 0.35 {
            return "Aim to reduce short sessions by protecting your first 15 minutes of work."
        }
        if !lowFocusHours.isEmpty {
            return "Schedule harder work outside your lower-energy hours around \(lowFocusHours.map(Self.hourLabel).joined(separator: ", "))."
        }
        return "Keep your strongest focus blocks in your peak hours and protect that routine."
    }

    var consistencyScoreText: String { "\(Int(consistencyScore.rounded()))%" }
    var consistencyDescriptor: String {
        switch consistencyScore {
        case ..<35: return "highly uneven"
        case ..<70: return "moderately stable"
        default: return "very stable"
        }
    }
    var completionRateText: String { "\(Int((completionRate * 100).rounded()))%" }
    var taskCompletionRateText: String { "\(Int((taskCompletionRate * 100).rounded()))%" }
    var focusQualityScoreText: String { "\(Int(focusQualityScore.rounded()))/100" }
    var shortSessionRatioText: String { "\(Int((shortSessionRatio * 100).rounded()))%" }
    var breakFocusRatioText: String { String(format: "%.2f", breakFocusRatio) }

    private static func averageMinutes(from points: [ProductivityTrendPoint]) -> Int {
        guard !points.isEmpty else { return 0 }
        let total = points.reduce(0.0) { $0 + $1.value }
        return Int((total / Double(points.count)).rounded())
    }

    private static func trendDirection(from points: [ProductivityTrendPoint]) -> String {
        guard let first = points.first?.value, let last = points.last?.value else { return "stable" }
        let delta = last - first
        if delta > 15 { return "increasing" }
        if delta < -15 { return "decreasing" }
        return "stable"
    }

    private static func topHours(from points: [FocusHourPoint], highest: Bool) -> [Int] {
        points
            .filter { $0.focusSeconds > 0 }
            .sorted { highest ? $0.focusSeconds > $1.focusSeconds : $0.focusSeconds < $1.focusSeconds }
            .prefix(3)
            .map(\.hour)
    }

    private static func anomalyFlags(
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: AIService.ProductivityTaskSummary
    ) -> [String] {
        var flags: [String] = []
        if snapshot.insights.shortSessionRatio >= 0.35 {
            flags.append("high_short_session_ratio")
        }
        if snapshot.insights.completionRate < 0.6 {
            flags.append("low_session_completion")
        }
        if snapshot.insights.consistencyScore < 40 {
            flags.append("low_consistency")
        }
        if snapshot.insights.breakFocusRatio > 0.45 {
            flags.append("high_break_focus_ratio")
        }
        if taskSummary.totalTasks > 0 && taskSummary.completionRate < 0.5 {
            flags.append("low_task_completion")
        }
        return flags
    }

    private static func dataAvailability(
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: AIService.ProductivityTaskSummary
    ) -> String {
        let totalSessions = snapshot.dailyAggregates.reduce(0) { $0 + $1.totalSessions }
        if totalSessions > 0 {
            return "tracked_sessions_available"
        }
        if taskSummary.totalTasks > 0 {
            return "task_only_context"
        }
        return "empty_history"
    }

    private static func noDataSummaryText(
        snapshot: ProductivityAnalyticsSnapshot,
        taskSummary: AIService.ProductivityTaskSummary
    ) -> String {
        let totalSessions = snapshot.dailyAggregates.reduce(0) { $0 + $1.totalSessions }
        if totalSessions > 0 {
            return "The user has limited but valid productivity data."
        }
        if taskSummary.totalTasks > 0 {
            return "The user has no recorded focus sessions yet, but does have tracked tasks. Base the analysis on task load and explain what early usage suggests."
        }
        return "The user has no recorded focus sessions or tracked tasks yet. Provide an onboarding-style analysis and explain what to track first."
    }

    nonisolated private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}

private final class AIInsightCacheStore {
    static let shared = AIInsightCacheStore()

    private struct Entry: Codable {
        let text: String
        let usedModelFamily: String?
        let generatedAt: Date
        let isFallback: Bool
        let expiresAt: Date
    }

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var entries: [String: Entry] = [:]

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = supportDir.appendingPathComponent("PomodoroApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("ai_insight_cache.json")
        load()
    }

    func cachedResult(for key: String, now: Date) -> AIService.ProductivityInsightResult? {
        guard let entry = entries[key], entry.expiresAt > now else {
            if entries[key] != nil {
                entries.removeValue(forKey: key)
                save()
            }
            return nil
        }
        return AIService.ProductivityInsightResult(
            text: entry.text,
            usedModelFamily: entry.usedModelFamily,
            generatedAt: entry.generatedAt,
            isFallback: entry.isFallback,
            cacheKey: key
        )
    }

    func store(_ result: AIService.ProductivityInsightResult, for key: String, expiresAt: Date) {
        entries[key] = Entry(
            text: result.text,
            usedModelFamily: result.usedModelFamily,
            generatedAt: result.generatedAt,
            isFallback: result.isFallback,
            expiresAt: expiresAt
        )
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([String: Entry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL)
    }
}

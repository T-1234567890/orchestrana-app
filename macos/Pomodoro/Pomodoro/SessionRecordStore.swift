import Foundation
import Combine

/// Local-only storage for focus session records.
/// No server sync or cloud dependency by design to keep insights private and predictable.
struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let durationSeconds: Int
    let taskId: UUID?
    let sessionType: SessionType
    let completed: Bool
    let interruptionCount: Int?

    init(
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        taskId: UUID?,
        sessionType: SessionType = .focus,
        completed: Bool = true,
        interruptionCount: Int? = nil
    ) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.taskId = taskId
        self.sessionType = sessionType
        self.completed = completed
        self.interruptionCount = interruptionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decode(Date.self, forKey: .endTime)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        taskId = try container.decodeIfPresent(UUID.self, forKey: .taskId)
        sessionType = try container.decodeIfPresent(SessionType.self, forKey: .sessionType) ?? .focus
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? true
        interruptionCount = try container.decodeIfPresent(Int.self, forKey: .interruptionCount)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startTime
        case endTime
        case durationSeconds
        case taskId
        case sessionType
        case completed
        case interruptionCount
    }
}

@MainActor
final class SessionRecordStore: ObservableObject {
    static let shared = SessionRecordStore()
    
    @Published private(set) var records: [SessionRecord] = []
    
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = supportDir.appendingPathComponent("PomodoroApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("session_records.json")
        load()
        ProductivityAnalyticsStore.shared.rebuild(from: records)
    }
    
    func appendRecord(
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        taskId: UUID?,
        sessionType: SessionType = .focus,
        completed: Bool = true,
        interruptionCount: Int? = nil
    ) {
        let record = SessionRecord(
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSeconds,
            taskId: taskId,
            sessionType: sessionType,
            completed: completed,
            interruptionCount: interruptionCount
        )
        records.append(record)
        save()
        ProductivityAnalyticsStore.shared.ingest(record)
    }
    
    /// Returns records within the last N days (inclusive of today).
    func records(lastDays: Int, calendar: Calendar = .current) -> [SessionRecord] {
        guard lastDays > 0 else { return [] }
        let start = calendar.date(byAdding: .day, value: -(lastDays - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        return records.filter { $0.startTime >= start }
    }
    
    /// Returns records for a specific day.
    func records(for day: Date, calendar: Calendar = .current) -> [SessionRecord] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return records.filter { $0.startTime >= start && $0.startTime < end }
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? decoder.decode([SessionRecord].self, from: data) {
            records = decoded
            ProductivityAnalyticsStore.shared.rebuild(from: decoded)
        }
    }
    
    private func save() {
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL)
        }
    }
}

import Foundation
import Combine

enum SessionType: String, Codable, CaseIterable {
    case focus
    case `break`
}

struct ProductivityTrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct FocusHourPoint: Identifiable, Equatable {
    let hour: Int
    let focusSeconds: Int
    let sessionCount: Int

    var id: Int { hour }
}

enum SessionLengthBucket: Int, CaseIterable, Codable, Identifiable {
    case under15
    case between15And25
    case between25And45
    case over45

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .under15: return "<15m"
        case .between15And25: return "15-25m"
        case .between25And45: return "25-45m"
        case .over45: return "45m+"
        }
    }

    static func bucket(for durationSeconds: Int) -> SessionLengthBucket {
        switch durationSeconds {
        case ..<900:
            return .under15
        case ..<1500:
            return .between15And25
        case ..<2700:
            return .between25And45
        default:
            return .over45
        }
    }
}

struct SessionLengthDistributionPoint: Identifiable, Equatable {
    let bucket: SessionLengthBucket
    let sessionCount: Int

    var id: SessionLengthBucket { bucket }
}

struct ProductivityInsights: Equatable {
    let streakDays: Int
    let completionRate: Double
    let focusQualityScore: Double
    let shortSessionRatio: Double
    let consistencyScore: Double
    let breakFocusRatio: Double
    let averageSessionLengthSeconds: Double
    let longestSessionSeconds: Int
}

struct ProductivityAnalyticsSnapshot: Equatable {
    let dailyAggregates: [DailyProductivityAggregate]
    let focusTrend7Days: [ProductivityTrendPoint]
    let focusTrend30Days: [ProductivityTrendPoint]
    let focusByHour: [FocusHourPoint]
    let sessionLengthDistribution: [SessionLengthDistributionPoint]
    let insights: ProductivityInsights
}

struct DailyProductivityAggregate: Codable, Identifiable, Equatable {
    let dayStart: Date
    private(set) var totalFocusSeconds: Int
    private(set) var totalBreakSeconds: Int
    private(set) var totalSessions: Int
    private(set) var completedSessions: Int
    private(set) var totalSessionSeconds: Int
    private(set) var longestSessionSeconds: Int
    private(set) var totalInterruptions: Int
    private(set) var shortSessions: Int
    private(set) var focusSessions: Int
    private(set) var breakSessions: Int
    private(set) var focusByHour: [Int]
    private(set) var sessionLengthBuckets: [Int]

    var id: Date { dayStart }

    init(dayStart: Date) {
        self.dayStart = dayStart
        self.totalFocusSeconds = 0
        self.totalBreakSeconds = 0
        self.totalSessions = 0
        self.completedSessions = 0
        self.totalSessionSeconds = 0
        self.longestSessionSeconds = 0
        self.totalInterruptions = 0
        self.shortSessions = 0
        self.focusSessions = 0
        self.breakSessions = 0
        self.focusByHour = Array(repeating: 0, count: 24)
        self.sessionLengthBuckets = Array(repeating: 0, count: SessionLengthBucket.allCases.count)
    }

    init(
        dayStart: Date,
        totalFocusSeconds: Int,
        totalBreakSeconds: Int,
        totalSessions: Int,
        completedSessions: Int,
        totalSessionSeconds: Int,
        longestSessionSeconds: Int,
        totalInterruptions: Int,
        shortSessions: Int,
        focusSessions: Int,
        breakSessions: Int,
        focusByHour: [Int],
        sessionLengthBuckets: [Int]
    ) {
        self.dayStart = dayStart
        self.totalFocusSeconds = totalFocusSeconds
        self.totalBreakSeconds = totalBreakSeconds
        self.totalSessions = totalSessions
        self.completedSessions = completedSessions
        self.totalSessionSeconds = totalSessionSeconds
        self.longestSessionSeconds = longestSessionSeconds
        self.totalInterruptions = totalInterruptions
        self.shortSessions = shortSessions
        self.focusSessions = focusSessions
        self.breakSessions = breakSessions
        self.focusByHour = focusByHour.count == 24
            ? focusByHour
            : Array(focusByHour.prefix(24)) + Array(repeating: 0, count: max(0, 24 - focusByHour.count))
        self.sessionLengthBuckets = sessionLengthBuckets.count == SessionLengthBucket.allCases.count
            ? sessionLengthBuckets
            : Array(sessionLengthBuckets.prefix(SessionLengthBucket.allCases.count))
                + Array(repeating: 0, count: max(0, SessionLengthBucket.allCases.count - sessionLengthBuckets.count))
    }

    var averageSessionLengthSeconds: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(totalSessionSeconds) / Double(totalSessions)
    }

    var completionRate: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }

    var breakFocusRatio: Double {
        guard totalFocusSeconds > 0 else {
            return totalBreakSeconds > 0 ? 1 : 0
        }
        return Double(totalBreakSeconds) / Double(totalFocusSeconds)
    }

    var shortSessionRatio: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(shortSessions) / Double(totalSessions)
    }

    var focusQualityScore: Double {
        DailyProductivityAggregate.computeFocusQualityScore(
            averageSessionLengthSeconds: averageSessionLengthSeconds,
            completionRate: completionRate,
            shortSessionRatio: shortSessionRatio
        )
    }

    mutating func ingest(
        _ record: SessionRecord,
        shortSessionThreshold: Int = ProductivityAnalyticsConfiguration.defaultShortSessionThreshold
    ) {
        let durationSeconds = max(0, record.durationSeconds)
        guard durationSeconds > 0 else { return }

        totalSessions += 1
        totalSessionSeconds += durationSeconds
        longestSessionSeconds = max(longestSessionSeconds, durationSeconds)
        if record.completed {
            completedSessions += 1
        }
        if durationSeconds < shortSessionThreshold {
            shortSessions += 1
        }
        let lengthBucket = SessionLengthBucket.bucket(for: durationSeconds)
        sessionLengthBuckets[lengthBucket.rawValue] += 1
        totalInterruptions += max(0, record.interruptionCount ?? 0)

        switch record.sessionType {
        case .focus:
            totalFocusSeconds += durationSeconds
            focusSessions += 1
            let hour = min(23, max(0, Calendar.current.component(.hour, from: record.startTime)))
            focusByHour[hour] += durationSeconds
        case .break:
            totalBreakSeconds += durationSeconds
            breakSessions += 1
        }
    }

    static func computeFocusQualityScore(
        averageSessionLengthSeconds: Double,
        completionRate: Double,
        shortSessionRatio: Double
    ) -> Double {
        let sessionLengthScore = min(1, averageSessionLengthSeconds / Double(45 * 60))
        let completionScore = min(max(completionRate, 0), 1)
        let shortPenalty = 1 - min(max(shortSessionRatio, 0), 1)
        return ((sessionLengthScore * 0.5) + (completionScore * 0.35) + (shortPenalty * 0.15)) * 100
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayStart = try container.decode(Date.self, forKey: .dayStart)
        totalFocusSeconds = try container.decodeIfPresent(Int.self, forKey: .totalFocusSeconds) ?? 0
        totalBreakSeconds = try container.decodeIfPresent(Int.self, forKey: .totalBreakSeconds) ?? 0
        totalSessions = try container.decodeIfPresent(Int.self, forKey: .totalSessions) ?? 0
        completedSessions = try container.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        totalSessionSeconds = try container.decodeIfPresent(Int.self, forKey: .totalSessionSeconds) ?? 0
        longestSessionSeconds = try container.decodeIfPresent(Int.self, forKey: .longestSessionSeconds) ?? 0
        totalInterruptions = try container.decodeIfPresent(Int.self, forKey: .totalInterruptions) ?? 0
        shortSessions = try container.decodeIfPresent(Int.self, forKey: .shortSessions) ?? 0
        focusSessions = try container.decodeIfPresent(Int.self, forKey: .focusSessions) ?? 0
        breakSessions = try container.decodeIfPresent(Int.self, forKey: .breakSessions) ?? 0
        focusByHour = try container.decodeIfPresent([Int].self, forKey: .focusByHour) ?? Array(repeating: 0, count: 24)
        let decodedBuckets = try container.decodeIfPresent([Int].self, forKey: .sessionLengthBuckets)
            ?? Array(repeating: 0, count: SessionLengthBucket.allCases.count)
        if decodedBuckets.count == SessionLengthBucket.allCases.count {
            sessionLengthBuckets = decodedBuckets
        } else {
            sessionLengthBuckets = Array(decodedBuckets.prefix(SessionLengthBucket.allCases.count))
            if sessionLengthBuckets.count < SessionLengthBucket.allCases.count {
                sessionLengthBuckets.append(contentsOf: Array(repeating: 0, count: SessionLengthBucket.allCases.count - sessionLengthBuckets.count))
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case dayStart
        case totalFocusSeconds
        case totalBreakSeconds
        case totalSessions
        case completedSessions
        case totalSessionSeconds
        case longestSessionSeconds
        case totalInterruptions
        case shortSessions
        case focusSessions
        case breakSessions
        case focusByHour
        case sessionLengthBuckets
    }
}

enum ProductivityAnalyticsConfiguration {
    static let defaultShortSessionThreshold = 15 * 60
}

@MainActor
final class ProductivityAnalyticsStore: ObservableObject {
    static let shared = ProductivityAnalyticsStore()

    @Published private(set) var dailyAggregates: [DailyProductivityAggregate] = []

    private var aggregateIndex: [Date: DailyProductivityAggregate] = [:]
    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = supportDir.appendingPathComponent("PomodoroApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("productivity_analytics_cache.json")
        load()
    }

    func rebuild(from records: [SessionRecord], calendar: Calendar = .current) {
        aggregateIndex.removeAll(keepingCapacity: true)

        for record in records {
            let dayStart = calendar.startOfDay(for: record.startTime)
            var aggregate = aggregateIndex[dayStart] ?? DailyProductivityAggregate(dayStart: dayStart)
            aggregate.ingest(record)
            aggregateIndex[dayStart] = aggregate
        }

        publishAndPersist()
    }

    func ingest(_ record: SessionRecord, calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: record.startTime)
        var aggregate = aggregateIndex[dayStart] ?? DailyProductivityAggregate(dayStart: dayStart)
        aggregate.ingest(record)
        aggregateIndex[dayStart] = aggregate
        publishAndPersist()
    }

    func aggregate(for day: Date, calendar: Calendar = .current) -> DailyProductivityAggregate {
        let dayStart = calendar.startOfDay(for: day)
        return aggregateIndex[dayStart] ?? DailyProductivityAggregate(dayStart: dayStart)
    }

    func trend(days: Int, calendar: Calendar = .current) -> [ProductivityTrendPoint] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: Date())
        return (0..<days).compactMap { offset -> Date? in
            calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today)
        }.map { day in
            let aggregate = aggregateIndex[day] ?? DailyProductivityAggregate(dayStart: day)
            return ProductivityTrendPoint(date: day, value: Double(aggregate.totalFocusSeconds) / 60)
        }
    }

    func focusByHour(days: Int? = nil, calendar: Calendar = .current) -> [FocusHourPoint] {
        let aggregates = aggregatesForWindow(days: days, calendar: calendar)
        var secondsByHour = Array(repeating: 0, count: 24)
        var sessionCountByHour = Array(repeating: 0, count: 24)

        for aggregate in aggregates {
            for hour in 0..<24 {
                let seconds = aggregate.focusByHour[safe: hour] ?? 0
                secondsByHour[hour] += seconds
                if seconds > 0 {
                    sessionCountByHour[hour] += 1
                }
            }
        }

        return (0..<24).map { hour in
            FocusHourPoint(hour: hour, focusSeconds: secondsByHour[hour], sessionCount: sessionCountByHour[hour])
        }
    }

    func snapshot(calendar: Calendar = .current) -> ProductivityAnalyticsSnapshot {
        let aggregates = dailyAggregates
        let focusTrend7Days = trend(days: 7, calendar: calendar)
        let focusTrend30Days = trend(days: 30, calendar: calendar)
        let focusByHourPoints = focusByHour(days: 30, calendar: calendar)
        var sessionLengthCounts = Array(repeating: 0, count: SessionLengthBucket.allCases.count)

        let totalSessions = aggregates.reduce(0) { $0 + $1.totalSessions }
        let completedSessions = aggregates.reduce(0) { $0 + $1.completedSessions }
        let totalSessionSeconds = aggregates.reduce(0) { $0 + $1.totalSessionSeconds }
        let longestSessionSeconds = aggregates.map(\.longestSessionSeconds).max() ?? 0
        let totalFocusSeconds = aggregates.reduce(0) { $0 + $1.totalFocusSeconds }
        let totalBreakSeconds = aggregates.reduce(0) { $0 + $1.totalBreakSeconds }
        let totalShortSessions = aggregates.reduce(0) { $0 + $1.shortSessions }
        for aggregate in aggregates {
            for bucket in SessionLengthBucket.allCases {
                sessionLengthCounts[bucket.rawValue] += aggregate.sessionLengthBuckets[safe: bucket.rawValue] ?? 0
            }
        }
        let sessionLengthDistribution = SessionLengthBucket.allCases.map { bucket in
            SessionLengthDistributionPoint(
                bucket: bucket,
                sessionCount: sessionLengthCounts[bucket.rawValue]
            )
        }

        let completionRate = totalSessions == 0 ? 0 : Double(completedSessions) / Double(totalSessions)
        let averageSessionLengthSeconds = totalSessions == 0 ? 0 : Double(totalSessionSeconds) / Double(totalSessions)
        let shortSessionRatio = totalSessions == 0 ? 0 : Double(totalShortSessions) / Double(totalSessions)
        let breakFocusRatio = totalFocusSeconds == 0
            ? (totalBreakSeconds > 0 ? 1 : 0)
            : Double(totalBreakSeconds) / Double(totalFocusSeconds)

        let insights = ProductivityInsights(
            streakDays: streakDays(calendar: calendar),
            completionRate: completionRate,
            focusQualityScore: DailyProductivityAggregate.computeFocusQualityScore(
                averageSessionLengthSeconds: averageSessionLengthSeconds,
                completionRate: completionRate,
                shortSessionRatio: shortSessionRatio
            ),
            shortSessionRatio: shortSessionRatio,
            consistencyScore: consistencyScore(from: focusTrend30Days),
            breakFocusRatio: breakFocusRatio,
            averageSessionLengthSeconds: averageSessionLengthSeconds,
            longestSessionSeconds: longestSessionSeconds
        )

        return ProductivityAnalyticsSnapshot(
            dailyAggregates: aggregates,
            focusTrend7Days: focusTrend7Days,
            focusTrend30Days: focusTrend30Days,
            focusByHour: focusByHourPoints,
            sessionLengthDistribution: sessionLengthDistribution,
            insights: insights
        )
    }

    func streakDays(calendar: Calendar = .current) -> Int {
        var streak = 0
        var currentDay = calendar.startOfDay(for: Date())

        while true {
            let aggregate = aggregateIndex[currentDay] ?? DailyProductivityAggregate(dayStart: currentDay)
            guard aggregate.totalFocusSeconds > 0 else { break }
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = previousDay
        }

        return streak
    }

    private func consistencyScore(from points: [ProductivityTrendPoint]) -> Double {
        let values = points.map(\.value)
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return 0 }
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + (delta * delta)
        } / Double(values.count)
        let standardDeviation = sqrt(variance)
        return max(0, (1 - min(1, standardDeviation / mean)) * 100)
    }

    private func aggregatesForWindow(days: Int?, calendar: Calendar) -> [DailyProductivityAggregate] {
        guard let days, days > 0 else {
            return dailyAggregates
        }
        let today = calendar.startOfDay(for: Date())
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return dailyAggregates
        }
        return dailyAggregates.filter { $0.dayStart >= startDay }
    }

    private func publishAndPersist() {
        dailyAggregates = aggregateIndex.values.sorted { $0.dayStart < $1.dayStart }
        guard let data = try? encoder.encode(dailyAggregates) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([DailyProductivityAggregate].self, from: data) else {
            return
        }

        dailyAggregates = decoded.sorted { $0.dayStart < $1.dayStart }
        aggregateIndex = Dictionary(uniqueKeysWithValues: dailyAggregates.map { ($0.dayStart, $0) })
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

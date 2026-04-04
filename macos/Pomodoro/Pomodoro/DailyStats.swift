//
//  DailyStats.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import Foundation

struct DailyStats: Codable, Equatable {
    private(set) var dayStart: Date
    private(set) var totalFocusSeconds: Int
    private(set) var totalBreakSeconds: Int
    private(set) var completedSessions: Int
    private(set) var totalSessions: Int
    private(set) var totalSessionSeconds: Int
    private(set) var longestSessionSeconds: Int

    init(date: Date = Date(), calendar: Calendar = .current) {
        let startOfDay = calendar.startOfDay(for: date)
        self.dayStart = startOfDay
        self.totalFocusSeconds = 0
        self.totalBreakSeconds = 0
        self.completedSessions = 0
        self.totalSessions = 0
        self.totalSessionSeconds = 0
        self.longestSessionSeconds = 0
    }

    mutating func reset(for date: Date = Date(), calendar: Calendar = .current) {
        dayStart = calendar.startOfDay(for: date)
        totalFocusSeconds = 0
        totalBreakSeconds = 0
        completedSessions = 0
        totalSessions = 0
        totalSessionSeconds = 0
        longestSessionSeconds = 0
    }

    mutating func ensureCurrentDay(_ date: Date = Date(), calendar: Calendar = .current) {
        let startOfDay = calendar.startOfDay(for: date)
        guard startOfDay != dayStart else { return }
        reset(for: date, calendar: calendar)
    }

    var averageSessionLengthSeconds: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(totalSessionSeconds) / Double(totalSessions)
    }

    var completionRate: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }

    mutating func logSession(
        type: SessionType,
        durationSeconds: Int,
        completed: Bool,
        date: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard durationSeconds > 0 else { return }
        ensureCurrentDay(date, calendar: calendar)

        switch type {
        case .focus:
            totalFocusSeconds += durationSeconds
        case .break:
            totalBreakSeconds += durationSeconds
        }

        totalSessions += 1
        totalSessionSeconds += durationSeconds
        longestSessionSeconds = max(longestSessionSeconds, durationSeconds)
        if completed {
            completedSessions += 1
        }
    }

    mutating func logFocusSession(
        durationSeconds: Int,
        completed: Bool = true,
        date: Date = Date(),
        calendar: Calendar = .current
    ) {
        logSession(
            type: .focus,
            durationSeconds: durationSeconds,
            completed: completed,
            date: date,
            calendar: calendar
        )
    }

    mutating func logBreakSession(
        durationSeconds: Int,
        completed: Bool = true,
        date: Date = Date(),
        calendar: Calendar = .current
    ) {
        logSession(
            type: .break,
            durationSeconds: durationSeconds,
            completed: completed,
            date: date,
            calendar: calendar
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayStart = try container.decode(Date.self, forKey: .dayStart)
        totalFocusSeconds = try container.decodeIfPresent(Int.self, forKey: .totalFocusSeconds) ?? 0
        totalBreakSeconds = try container.decodeIfPresent(Int.self, forKey: .totalBreakSeconds) ?? 0
        completedSessions = try container.decodeIfPresent(Int.self, forKey: .completedSessions) ?? 0
        totalSessions = try container.decodeIfPresent(Int.self, forKey: .totalSessions) ?? completedSessions
        totalSessionSeconds = try container.decodeIfPresent(Int.self, forKey: .totalSessionSeconds)
            ?? (totalFocusSeconds + totalBreakSeconds)
        longestSessionSeconds = try container.decodeIfPresent(Int.self, forKey: .longestSessionSeconds) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case dayStart
        case totalFocusSeconds
        case totalBreakSeconds
        case completedSessions
        case totalSessions
        case totalSessionSeconds
        case longestSessionSeconds
    }
}

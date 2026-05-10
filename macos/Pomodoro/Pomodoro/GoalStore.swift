import Foundation
import Combine

struct GoalRecord: Identifiable, Codable, Equatable {
    enum Status: String, Codable, CaseIterable {
        case active
        case paused
        case completed

        var title: String {
            switch self {
            case .active:
                return "Active"
            case .paused:
                return "Paused"
            case .completed:
                return "Completed"
            }
        }
    }

    let id: UUID
    var outcome: String
    var successCriteria: String
    var notes: String
    var nextAction: String
    var targetDate: Date?
    var status: Status
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        outcome: String,
        successCriteria: String = "",
        notes: String = "",
        nextAction: String = "",
        targetDate: Date? = nil,
        status: Status = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.outcome = outcome
        self.successCriteria = successCriteria
        self.notes = notes
        self.nextAction = nextAction
        self.targetDate = targetDate
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct GoalLink: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case task
        case event
        case session

        var title: String {
            switch self {
            case .task:
                return "Task"
            case .event:
                return "Event"
            case .session:
                return "Session"
            }
        }
    }

    let id: UUID
    let goalID: UUID
    let kind: Kind
    let targetID: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        goalID: UUID,
        kind: Kind,
        targetID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.goalID = goalID
        self.kind = kind
        self.targetID = targetID
        self.createdAt = createdAt
    }
}

@MainActor
final class GoalStore: ObservableObject {
    @Published private(set) var goals: [GoalRecord] = []
    @Published private(set) var links: [GoalLink] = []

    private let goalsKey = "com.pomodoro.workspace.goals"
    private let linksKey = "com.pomodoro.workspace.goalLinks"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    @discardableResult
    func addGoal(
        outcome: String,
        successCriteria: String,
        notes: String,
        nextAction: String,
        targetDate: Date?
    ) -> GoalRecord? {
        let trimmedOutcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutcome.isEmpty else { return nil }

        let goal = GoalRecord(
            outcome: trimmedOutcome,
            successCriteria: successCriteria.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            nextAction: nextAction.trimmingCharacters(in: .whitespacesAndNewlines),
            targetDate: targetDate
        )
        goals.insert(goal, at: 0)
        save()
        return goal
    }

    func updateGoal(_ goal: GoalRecord) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        var updated = goal
        updated.outcome = updated.outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.outcome.isEmpty else { return }
        updated.successCriteria = updated.successCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = updated.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.nextAction = updated.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        goals[index] = updated
        save()
    }

    func setStatus(goalID: UUID, status: GoalRecord.Status) {
        guard let index = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[index].status = status
        goals[index].updatedAt = Date()
        save()
    }

    func deleteGoal(_ goal: GoalRecord) {
        goals.removeAll { $0.id == goal.id }
        links.removeAll { $0.goalID == goal.id }
        save()
    }

    @discardableResult
    func addLink(goalID: UUID, kind: GoalLink.Kind, targetID: String) -> GoalLink? {
        let trimmedTargetID = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard goals.contains(where: { $0.id == goalID }),
              !trimmedTargetID.isEmpty,
              !links.contains(where: { $0.goalID == goalID && $0.kind == kind && $0.targetID == trimmedTargetID }) else {
            return nil
        }

        let link = GoalLink(goalID: goalID, kind: kind, targetID: trimmedTargetID)
        links.insert(link, at: 0)
        save()
        return link
    }

    func removeLink(_ link: GoalLink) {
        links.removeAll { $0.id == link.id }
        save()
    }

    func links(for goalID: UUID) -> [GoalLink] {
        links
            .filter { $0.goalID == goalID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func linkCount(for goalID: UUID) -> Int {
        links.filter { $0.goalID == goalID }.count
    }

    func hasLink(goalID: UUID, kind: GoalLink.Kind, targetID: String) -> Bool {
        links.contains { $0.goalID == goalID && $0.kind == kind && $0.targetID == targetID }
    }

    private func load() {
        if let goalsData = UserDefaults.standard.data(forKey: goalsKey),
           let decodedGoals = try? decoder.decode([GoalRecord].self, from: goalsData) {
            goals = decodedGoals.sorted { $0.updatedAt > $1.updatedAt }
        }

        if let linksData = UserDefaults.standard.data(forKey: linksKey),
           let decodedLinks = try? decoder.decode([GoalLink].self, from: linksData) {
            links = decodedLinks
        }
    }

    private func save() {
        if let encodedGoals = try? encoder.encode(goals) {
            UserDefaults.standard.set(encodedGoals, forKey: goalsKey)
        }
        if let encodedLinks = try? encoder.encode(links) {
            UserDefaults.standard.set(encodedLinks, forKey: linksKey)
        }
    }
}

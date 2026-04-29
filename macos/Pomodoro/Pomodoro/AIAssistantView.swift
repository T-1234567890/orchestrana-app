import SwiftUI

enum AIAssistantAction: String, CaseIterable, Identifiable {
    case breakdown
    case draftFromIdea
    case planning
    case reschedule

    var id: String { rawValue }

    var allowsMultipleSelection: Bool {
        self == .planning
    }

    var requiresTaskSelection: Bool {
        switch self {
        case .breakdown, .planning:
            return true
        case .draftFromIdea, .reschedule:
            return false
        }
    }

    var systemImage: String {
        switch self {
        case .breakdown:
            return "list.bullet.rectangle.portrait"
        case .draftFromIdea:
            return "text.badge.plus"
        case .planning:
            return "calendar.badge.clock"
        case .reschedule:
            return "calendar.badge.clock"
        }
    }
}

@MainActor
struct AIAssistantView: View {
    let tasks: [TodoItem]
    let availableActions: [AIAssistantAction]
    let isLoading: Bool
    let errorMessage: String?
    let isActionEnabled: (AIAssistantAction) -> Bool
    let onClose: () -> Void
    let onLockedActionTap: (AIAssistantAction) -> Void
    let onRunAction: (AIAssistantAction, [TodoItem], Date, Int) async -> Void

    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var selectedAction: AIAssistantAction?
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var dueDate = Date()
    @State private var estimatedHours = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(localizationManager.text("tasks.ai_assistant.title"))
                .font(.title2.weight(.semibold))

            Text(localizationManager.text("tasks.ai_assistant.description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let selectedAction {
                selectionView(for: selectedAction)
            } else {
                optionButtons
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var optionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(availableActions) { action in
                assistantOptionButton(for: action)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(localizationManager.text("common.cancel")) {
                    onClose()
                }
                .orchestranaButton(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func assistantOptionButton(for action: AIAssistantAction) -> some View {
        Button {
            guard isActionEnabled(action) else {
                onLockedActionTap(action)
                return
            }
            if !action.requiresTaskSelection {
                Task { @MainActor in
                    await onRunAction(action, [], Date(), 0)
                }
                return
            }
            selectedAction = action
            selectedTaskIDs.removeAll()
            dueDate = Date()
            estimatedHours = defaultEstimatedHours(for: action)
        } label: {
            HStack(spacing: 12) {
                if isLoading && action == .reschedule {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28)
                } else {
                    Image(systemName: action.systemImage)
                        .font(.title3)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoading && action == .reschedule ? localizationManager.text("calendar.reschedule.loading") : title(for: action))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(description(for: action))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isActionEnabled(action) ? "chevron.right" : "lock.fill")
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func selectionView(for action: AIAssistantAction) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    selectedAction = nil
                } label: {
                    Label(localizationManager.text("common.back"), systemImage: "chevron.left")
                }
                .orchestranaButton(.secondary)

                Spacer()
            }

            Text(title(for: action))
                .font(.title3.weight(.semibold))

            Text(selectionPrompt(for: action))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if action.requiresTaskSelection {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            Button {
                                toggleSelection(for: task.id, allowsMultiple: action.allowsMultipleSelection)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedTaskIDs.contains(task.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selectedTaskIDs.contains(task.id) ? Color.accentColor : .secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(task.title)
                                            .foregroundStyle(.primary)

                                        if let notes = task.notes, !notes.isEmpty {
                                            Text(notes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .background(Color.primary.opacity(0.04))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 300)

                DatePicker(
                    localizationManager.text("tasks.ai_plan.deadline"),
                    selection: $dueDate,
                    displayedComponents: [.date]
                )

                OrchestranaStepControl(
                    value: $estimatedHours,
                    in: 1...40,
                    valueText: { localizationManager.format("tasks.ai_plan.estimated_hours_value", $0) }
                )
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(localizationManager.text("common.cancel")) {
                    onClose()
                }
                .orchestranaButton(.secondary)

                Spacer()

                Button {
                    let selectedTasks = tasks.filter { selectedTaskIDs.contains($0.id) }
                    Task { @MainActor in
                        await onRunAction(action, selectedTasks, dueDate, estimatedHours)
                    }
                } label: {
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(action == .reschedule
                                 ? localizationManager.text("calendar.reschedule.loading")
                                 : localizationManager.text("tasks.ai_plan.loading"))
                        }
                    } else {
                        Text(buttonTitle(for: action))
                    }
                }
                .orchestranaButton(.primary)
                .disabled(isLoading || (action.requiresTaskSelection && selectedTaskIDs.isEmpty))
            }
        }
    }

    private func toggleSelection(for id: UUID, allowsMultiple: Bool) {
        if allowsMultiple {
            if selectedTaskIDs.contains(id) {
                selectedTaskIDs.remove(id)
            } else {
                selectedTaskIDs.insert(id)
            }
        } else if selectedTaskIDs.contains(id) {
            selectedTaskIDs.removeAll()
        } else {
            selectedTaskIDs = [id]
        }
    }

    private func defaultEstimatedHours(for action: AIAssistantAction) -> Int {
        switch action {
        case .breakdown:
            return 1
        case .draftFromIdea:
            return 1
        case .planning:
            let totalMinutes = tasks.compactMap(\.durationMinutes).reduce(0, +)
            return max(1, totalMinutes / 60)
        case .reschedule:
            return 1
        }
    }

    private func title(for action: AIAssistantAction) -> String {
        switch action {
        case .breakdown:
            return localizationManager.text("tasks.ai_assistant.breakdown_title")
        case .draftFromIdea:
            return localizationManager.text("tasks.ai_assistant.draft_from_idea_title")
        case .planning:
            return localizationManager.text("tasks.ai_assistant.plan_title")
        case .reschedule:
            return localizationManager.text("calendar.ai_assistant.reschedule_title")
        }
    }

    private func description(for action: AIAssistantAction) -> String {
        switch action {
        case .breakdown:
            return localizationManager.text("tasks.ai_assistant.breakdown_description")
        case .draftFromIdea:
            return localizationManager.text("tasks.ai_assistant.draft_from_idea_description")
        case .planning:
            return localizationManager.text("tasks.ai_assistant.plan_description")
        case .reschedule:
            return localizationManager.text("calendar.ai_assistant.reschedule_description")
        }
    }

    private func buttonTitle(for action: AIAssistantAction) -> String {
        switch action {
        case .breakdown:
            return localizationManager.text("tasks.ai_assistant.breakdown_run")
        case .draftFromIdea:
            return localizationManager.text("tasks.ai_assistant.draft_from_idea_run")
        case .planning:
            return localizationManager.text("tasks.ai_assistant.plan_run")
        case .reschedule:
            return localizationManager.text("calendar.ai_assistant.reschedule_title")
        }
    }

    private func selectionPrompt(for action: AIAssistantAction) -> String {
        switch action {
        case .breakdown:
            return localizationManager.text("tasks.ai_assistant.breakdown_prompt")
        case .draftFromIdea:
            return localizationManager.text("tasks.ai_assistant.draft_from_idea_description")
        case .planning:
            return localizationManager.text("tasks.ai_assistant.plan_prompt")
        case .reschedule:
            return localizationManager.text("calendar.ai_assistant.reschedule_description")
        }
    }
}

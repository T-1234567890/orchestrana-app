import SwiftUI
import AppKit

/// Todo/Tasks view - always accessible with optional Reminders sync.
/// Shows non-blocking banner when Reminders is unauthorized.
@MainActor
struct TodoListView: View {
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject var remindersSync: RemindersSync
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject private var featureGate = FeatureGate.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var showingEditor = false
    @State private var editingItem: TodoItem?
    @State private var titleField = ""
    @State private var descriptionField = ""
    @State private var tagsField = ""
    @State private var dueDateEnabled = false
    @State private var dueDateField = Date()
    /// Time is opt-in; we default to date-only for quick entry.
    @State private var includeDueTime = false
    @State private var selectedSegment: Segment = .active
    @State private var taskViewMode: TaskViewMode = .list
    @State private var syncToCalendarField = false
    @State private var priorityField: TodoItem.Priority = .none
    @State private var pomodoroEstimateField = 1
    @State private var selectedTaskIDs: Set<UUID> = []
    @State private var lastSelectedTaskID: UUID?
    @State private var expandedTaskIDs: Set<UUID> = []
    @State private var subtaskDrafts: [UUID: String] = [:]
    @State private var batchDueDate: Date = Date()
    @State private var showBatchDeleteConfirmation = false
    @State private var showTaskHint = false
    @State private var aiEstimatedHours = 1
    @State private var isGeneratingAIPlan = false
    @State private var isGeneratingAIDescription = false
    @State private var isGeneratingAITaskDraft = false
    @State private var aiPlanErrorMessage: String?
    @State private var aiDescriptionErrorMessage: String?
    @State private var aiTaskDraftErrorMessage: String?
    @State private var pendingGeneratedDescription: String?
    @State private var showReplaceDescriptionConfirmation = false
    @State private var showAITaskDraftSheet = false
    @State private var aiTaskDraftPrompt = ""
    @State private var showAILoginSheet = false
    @State private var upgradePaywallContext: SubscriptionPaywallContext?
    @State private var showAIAssistant = false
    @State private var isRunningAIAssistant = false
    @State private var aiAssistantErrorMessage: String?
    @State private var animatingCompletionIDs: Set<UUID> = []
    @State private var bouncingCompletionIDs: Set<UUID> = []
    @State private var animatingSubtaskCompletionIDs: Set<UUID> = []
    @State private var bouncingSubtaskCompletionIDs: Set<UUID> = []
    @State private var editorSubtasks: [TodoSubtask] = []
    @State private var collapsedEventGroupIDs: Set<UUID> = []
    
    private static let taskHintDefaultsKey = "com.pomodoro.taskHintShown"
    private var taskExpansionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.34, dampingFraction: 0.82)
    }

    private var completionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.28, dampingFraction: 0.68)
    }

    private var subtaskExpansionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.98, anchor: .top)),
                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
            )
    }
    
    private enum Segment: String, CaseIterable, Identifiable {
        case active
        case completed

        var id: String { rawValue }
    }

    private enum TaskViewMode: String, CaseIterable, Identifiable {
        case list
        case matrix

        var id: String { rawValue }
    }

    private struct EventTaskGroupEntry: Identifiable {
        let id: UUID
        let eventTitle: String
        let eventStartDate: Date?
        let tasks: [PlanningItem.EventTask]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
    
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()
    
    private static let lastSyncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let aiDeadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var isGeneratingTaskAI: Bool {
        isGeneratingAIDescription || isGeneratingAITaskDraft
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(localizationManager.text("tasks.title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(localizationManager.text("tasks.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 16)
            
            // Non-blocking Reminders banner
            if !permissionsManager.isRemindersAuthorized {
                remindersBanner
            }
            
            if showTaskHint {
                taskHint
                    .padding(.horizontal, 32)
                    .padding(.bottom, 12)
            }

            planningOverview
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            
            // Toolbar
            HStack {
                Button(action: { openEditorForNew() }) {
                    Label(localizationManager.text("tasks.add_task"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                
                if permissionsManager.isRemindersAuthorized {
                    Button {
                        Task { await remindersSync.syncAllTasks() }
                    } label: {
                        if remindersSync.isSyncing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localizationManager.text("tasks.syncing"))
                            }
                        } else {
                            Label(localizationManager.text("tasks.sync_all_tasks"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(remindersSync.isSyncing)
                }

                Button {
                    Task { @MainActor in
                        await featureGate.refreshSubscriptionStatusIfNeeded()
                        if !featureGate.canUseCloudProxyAI {
                            presentLockedFeatureInfo(
                                featureName: localizationManager.text("tasks.ai_assistant.button"),
                                description: localizationManager.text("feature_gate.paywall.ai_assistant.description"),
                                requiredTier: .plus,
                                requirementText: localizationManager.text("feature_gate.paywall.requires_plus_or_pro")
                            )
                        } else {
                            aiAssistantErrorMessage = nil
                            showAIAssistant = true
                        }
                    }
                } label: {
                    Label(localizationManager.text("tasks.ai_assistant.button"), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                
                Spacer()

                Picker("", selection: $taskViewMode) {
                    Text(localizationManager.text("tasks.view.list")).tag(TaskViewMode.list)
                    Text(localizationManager.text("tasks.view.matrix")).tag(TaskViewMode.matrix)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .onChange(of: taskViewMode) { _, newMode in
                    guard newMode == .matrix else { return }
                    Task { @MainActor in
                        await featureGate.refreshSubscriptionStatusIfNeeded()
                        guard !featureGate.canUseEisenhowerMatrix else { return }
                        taskViewMode = .list
                        presentLockedFeatureInfo(
                            featureName: "Eisenhower Matrix",
                            description: "Organize tasks by urgency and importance in a matrix view.",
                            requiredTier: .pro
                        )
                    }
                }
                
                Picker("", selection: $selectedSegment) {
                    Text(localizationManager.text("tasks.segment.active")).tag(Segment.active)
                    Text(localizationManager.text("tasks.segment.completed")).tag(Segment.completed)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)

            if let aiAssistantErrorMessage, !aiAssistantErrorMessage.isEmpty {
                HStack {
                    Text(aiAssistantErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            }
            
            if let last = remindersSync.lastSyncDate {
                HStack {
                    Text(localizationManager.format("tasks.last_sync_format", formatLastSyncDate(last)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle(localizationManager.text("tasks.auto_sync"), isOn: $remindersSync.isAutoSyncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 6)
            }
            
            Divider()
            
            // Batch actions bar (shown only when multi-select is active)
            if selectedTaskIDs.count > 1 {
                batchActionsBar
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
            }
            
            // Tasks list
            if taskViewMode == .matrix, featureGate.canUseEisenhowerMatrix, selectedSegment == .active {
                ScrollView {
                    EisenhowerMatrixView(tasks: filteredItems) { task in
                        openEditorForEdit(task)
                    }
                    .padding(16)
                }
            } else {
                if filteredItems.isEmpty && filteredEventTaskGroups.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            todoRow(item)
                                .opacity(selectedSegment == .completed ? 0.9 : 1.0)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }

                        if !filteredEventTaskGroups.isEmpty {
                            eventSectionDivider
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)

                            ForEach(filteredEventTaskGroups) { group in
                                eventTaskGroupRow(group)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
        .sheet(isPresented: $showingEditor) {
            taskEditorSheet
        }
        .sheet(isPresented: $showAILoginSheet) {
            LoginSheetView()
                .environmentObject(authViewModel)
        }
        .sheet(item: $upgradePaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: SubscriptionStore.shared
            )
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView(
                tasks: toolbarAICandidateTasks,
                availableActions: [.breakdown, .draftFromIdea, .planning],
                isLoading: isRunningAIAssistant,
                errorMessage: aiAssistantErrorMessage,
                isActionEnabled: { action in
                    featureGate.canUseAIAssistantAction(action)
                },
                onClose: { showAIAssistant = false },
                onLockedActionTap: { action in
                    presentUpgradePaywall(
                        requiredTier: .plus,
                        title: action == .planning
                            ? localizationManager.text("feature_gate.paywall.smart_planning.title")
                            : localizationManager.text("feature_gate.paywall.ai_assistant.title"),
                        message: action == .planning
                            ? localizationManager.text("feature_gate.paywall.smart_planning.body")
                            : localizationManager.text("feature_gate.paywall.ai_assistant.breakdown_body")
                    )
                },
                onRunAction: { action, tasks, dueDate, estimatedHours in
                    await handleAIAssistantAction(
                        action,
                        selectedTasks: tasks,
                        dueDate: dueDate,
                        estimatedHours: estimatedHours
                    )
                }
            )
            .environmentObject(localizationManager)
        }
        .onAppear {
            permissionsManager.refreshRemindersStatus()
            if !UserDefaults.standard.bool(forKey: Self.taskHintDefaultsKey) {
                showTaskHint = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewTaskComposer)) { _ in
            openEditorForNew()
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskToggleSelectedCompletion)) { _ in
            handleKeyboardToggleDone()
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskDeleteSelection)) { _ in
            handleKeyboardDelete()
        }
    }
    
    private var remindersBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(localizationManager.text("tasks.reminders_sync_disabled.title"))
                    .font(.headline)
                
                Text(localizationManager.text("tasks.reminders_sync_disabled.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(localizationManager.text("permissions.enable")) {
                Task {
                    await permissionsManager.requestRemindersPermission()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
        .alert(localizationManager.text("tasks.reminders_access_denied.title"), isPresented: $permissionsManager.showRemindersDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("tasks.reminders_access_denied.body"))
        }
    }

    private var planningOverview: some View {
        HStack(spacing: 10) {
            planningPill(
                title: localizationManager.text("tasks.planned"),
                value: "\(plannedTaskCount)",
                color: .green
            )
            planningPill(
                title: localizationManager.text("tasks.unplanned"),
                value: "\(unplannedTaskCount)",
                color: .orange
            )
            planningPill(
                title: localizationManager.text("tasks.planned_today"),
                value: "\(plannedTodayCount)",
                color: .blue
            )
            Spacer()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
    }

    private func planningPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text(localizationManager.text("tasks.empty.title"))
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(localizationManager.text("tasks.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
    
    /// Inline, dismissible hint for first-time task writers.
    private var taskHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.title3)
                .foregroundStyle(.yellow)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(localizationManager.text("tasks.hint.title"))
                    .font(.headline)
                Text(localizationManager.text("tasks.hint.body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                showTaskHint = false
                UserDefaults.standard.set(true, forKey: Self.taskHintDefaultsKey)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func todoRow(_ item: TodoItem) -> some View {
        let isSelected = selectedTaskIDs.contains(item.id)
        let isExpanded = expandedTaskIDs.contains(item.id)
        let isAnimatingCompletion = animatingCompletionIDs.contains(item.id)
        let showsCompletedState = item.isCompleted || isAnimatingCompletion
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: {
                    handleCompletionTap(for: item)
                }) {
                    Image(systemName: showsCompletedState ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(showsCompletedState ? .green : .secondary)
                        .scaleEffect(bouncingCompletionIDs.contains(item.id) ? 1.12 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: bouncingCompletionIDs.contains(item.id))
                        .animation(.easeInOut(duration: 0.2), value: showsCompletedState)
                }
                .buttonStyle(.plain)

                Button {
                    toggleExpanded(item.id)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 14)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded && !reduceMotion ? 0 : 0))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .strikethrough(showsCompletedState)
                        .foregroundStyle(showsCompletedState ? .secondary : .primary)
                        .animation(.easeInOut(duration: 0.25), value: showsCompletedState)

                    if let descriptionMarkdown = item.descriptionMarkdown, !descriptionMarkdown.isEmpty {
                        if isExpanded, featureGate.canUseTaskMarkdown {
                            TaskMarkdownView(markdown: descriptionMarkdown)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(descriptionMarkdown)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if IntentMarkers.containsFocusIntent(in: item.title) || IntentMarkers.containsFocusIntent(in: item.notes) {
                        HStack(spacing: 6) {
                            Image(systemName: "target")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(localizationManager.text("tasks.focus_marked"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !item.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .cornerRadius(4)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        if item.priority != .none {
                            priorityBadge(item.priority)
                        }

                        if let estimate = item.pomodoroEstimate {
                            Label(localizationManager.format("tasks.pomodoro_estimate_value", estimate), systemImage: "timer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let dueDate = item.dueDate {
                            Label(formattedDueDate(item, dueDate: dueDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if item.reminderIdentifier != nil {
                            Label(localizationManager.text("tasks.status.synced"), systemImage: "checkmark.icloud")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else if item.syncToCalendar, (item.linkedCalendarEventId ?? item.calendarEventIdentifier) != nil {
                            Label(localizationManager.text("tasks.status.in_calendar"), systemImage: "calendar.badge.checkmark")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        if planningItem(for: item) != nil {
                            Label(planningStatusLabel(for: item), systemImage: "calendar.badge.clock")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        } else if !showsCompletedState {
                            Label(localizationManager.text("tasks.unplanned"), systemImage: "calendar.badge.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                
                Spacer()
                
                Menu {
                if permissionsManager.isRemindersAuthorized {
                    if item.reminderIdentifier == nil {
                        Button(action: {
                            Task {
                                try? await remindersSync.syncTask(item)
                            }
                        }) {
                            Label(localizationManager.text("tasks.action.sync_to_reminders"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    } else {
                        Button(action: {
                            remindersSync.unsyncFromReminders(item)
                        }) {
                            Label(localizationManager.text("tasks.action.unsync_from_reminders"), systemImage: "xmark.icloud")
                        }
                    }
                    
                    Divider()
                }
                
                Button {
                    openEditorForEdit(item)
                } label: {
                    Label(localizationManager.text("common.edit"), systemImage: "pencil")
                }

                if item.dueDate == nil {
                    Button {
                        planTaskForToday(item)
                    } label: {
                        Label(localizationManager.text("tasks.action.plan_for_today"), systemImage: "calendar.badge.plus")
                    }
                } else {
                    Button {
                        clearPlanDate(for: item)
                    } label: {
                        Label(localizationManager.text("tasks.action.remove_plan_date"), systemImage: "calendar.badge.minus")
                    }
                }

                if item.isCompleted {
                    Button {
                        restoreCompletedTask(item)
                    } label: {
                        Label(localizationManager.text("tasks.action.restore_task"), systemImage: "arrow.uturn.backward.circle")
                    }
                }
                
                Button(role: .destructive, action: {
                    if item.reminderIdentifier != nil {
                        Task {
                            try? await remindersSync.deleteReminder(item)
                        }
                    }
                    todoStore.deleteItem(item)
                }) {
                    Label(localizationManager.text("common.delete"), systemImage: "trash")
                }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                subtaskSection(for: item)
                    .transition(subtaskExpansionTransition)
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
        .cornerRadius(8)
        .scaleEffect(reduceMotion ? 1.0 : (showsCompletedState ? 0.98 : 1.0))
        .opacity(showsCompletedState ? 0.6 : (selectedSegment == .completed ? 0.9 : 1.0))
        .animation(.easeInOut(duration: 0.25), value: showsCompletedState)
        .animation(taskExpansionAnimation, value: isExpanded)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTaskSelection(item)
        }
    }
    
    @ViewBuilder
    private func priorityBadge(_ priority: TodoItem.Priority) -> some View {
        Text(priority.displayName)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.2))
            .foregroundStyle(priorityColor(priority))
            .cornerRadius(4)
    }
    
    private func priorityColor(_ priority: TodoItem.Priority) -> Color {
        switch priority {
        case .none:
            return .gray
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    @ViewBuilder
    private func subtaskSection(for item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            Text(localizationManager.text("tasks.subtasks.title"))
                .font(.subheadline.weight(.semibold))

            if !item.subtasks.isEmpty {
                ForEach(item.subtasks) { subtask in
                    subtaskRow(itemID: item.id, subtask: subtask)
                        .transition(subtaskExpansionTransition)
                }
            }

            if featureGate.canUseSubtasks {
                HStack(spacing: 8) {
                    TextField(
                        localizationManager.text("tasks.subtasks.placeholder"),
                        text: Binding(
                            get: { subtaskDrafts[item.id] ?? "" },
                            set: { subtaskDrafts[item.id] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(localizationManager.text("common.add")) {
                        let draft = subtaskDrafts[item.id] ?? ""
                        todoStore.addSubtask(to: item.id, title: draft)
                        subtaskDrafts[item.id] = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled((subtaskDrafts[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button {
                    presentLockedFeatureInfo(
                        featureName: "Subtasks",
                        description: "Break a task into smaller checklist items and track progress.",
                        requiredTier: .plus
                    )
                } label: {
                    Label("Subtasks", systemImage: "lock.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.leading, 34)
        .clipped()
    }

    private func toggleExpanded(_ id: UUID) {
        withAnimation(taskExpansionAnimation) {
            if expandedTaskIDs.contains(id) {
                expandedTaskIDs.remove(id)
            } else {
                expandedTaskIDs.insert(id)
            }
        }
    }

    @ViewBuilder
    private func subtaskRow(itemID: UUID, subtask: TodoSubtask) -> some View {
        let isAnimatingCompletion = animatingSubtaskCompletionIDs.contains(subtask.id)
        let showsCompletedState = subtask.completed || isAnimatingCompletion

        HStack(spacing: 8) {
            Button {
                guard featureGate.canUseSubtasks else {
                    presentLockedFeatureInfo(
                        featureName: "Subtasks",
                        description: "Break a task into smaller checklist items and track progress.",
                        requiredTier: .plus
                    )
                    return
                }
                handleSubtaskCompletionTap(taskID: itemID, subtask: subtask)
            } label: {
                Image(systemName: showsCompletedState ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(showsCompletedState ? .green : .secondary)
                    .scaleEffect(bouncingSubtaskCompletionIDs.contains(subtask.id) ? 1.08 : 1.0)
                    .animation(completionAnimation, value: bouncingSubtaskCompletionIDs.contains(subtask.id))
                    .animation(.easeInOut(duration: 0.18), value: showsCompletedState)
            }
            .buttonStyle(.plain)

            Text(subtask.title)
                .font(.subheadline)
                .strikethrough(showsCompletedState)
                .foregroundStyle(showsCompletedState ? .secondary : .primary)
                .scaleEffect(reduceMotion ? 1.0 : (showsCompletedState ? 0.99 : 1.0))
                .opacity(showsCompletedState ? 0.72 : 1.0)
                .animation(.easeInOut(duration: 0.22), value: showsCompletedState)

            Spacer()
        }
        .offset(y: reduceMotion ? 0 : (showsCompletedState ? -1 : 0))
        .animation(.easeInOut(duration: 0.22), value: showsCompletedState)
    }

    private var keyboardFocusedTask: TodoItem? {
        if let editingItem,
           let current = todoStore.items.first(where: { $0.id == editingItem.id }) {
            return current
        }
        if let selectedID = selectedTaskIDs.first {
            return todoStore.items.first(where: { $0.id == selectedID })
        }
        return nil
    }

    private func handleKeyboardToggleDone() {
        guard featureGate.canUseTaskKeyboardShortcuts,
              let task = keyboardFocusedTask else {
            return
        }
        handleCompletionTap(for: task)
    }

    private func handleCompletionTap(for item: TodoItem) {
        if item.isCompleted {
            withAnimation(.easeInOut(duration: 0.2)) {
                todoStore.toggleCompletion(item)
            }
            syncUpdatedReminderIfNeeded(for: item.id)
            return
        }

        _ = withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            bouncingCompletionIDs.insert(item.id)
        }
        _ = withAnimation(.easeInOut(duration: 0.25)) {
            animatingCompletionIDs.insert(item.id)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            bouncingCompletionIDs.remove(item.id)
            todoStore.toggleCompletion(item)
            animatingCompletionIDs.remove(item.id)
            syncUpdatedReminderIfNeeded(for: item.id)
        }
    }

    private func handleSubtaskCompletionTap(taskID: UUID, subtask: TodoSubtask) {
        if subtask.completed {
            withAnimation(.easeInOut(duration: 0.18)) {
                todoStore.toggleSubtask(taskID: taskID, subtaskID: subtask.id)
            }
            return
        }

        _ = withAnimation(completionAnimation) {
            bouncingSubtaskCompletionIDs.insert(subtask.id)
        }
        _ = withAnimation(.easeInOut(duration: 0.22)) {
            animatingSubtaskCompletionIDs.insert(subtask.id)
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            bouncingSubtaskCompletionIDs.remove(subtask.id)
            todoStore.toggleSubtask(taskID: taskID, subtaskID: subtask.id)
            animatingSubtaskCompletionIDs.remove(subtask.id)
        }
    }

    private func syncUpdatedReminderIfNeeded(for itemID: UUID) {
        guard permissionsManager.isRemindersAuthorized,
              let updatedItem = todoStore.items.first(where: { $0.id == itemID }),
              updatedItem.reminderIdentifier != nil else {
            return
        }

        Task {
            try? await remindersSync.syncTask(updatedItem)
        }
    }

    private func handleKeyboardDelete() {
        guard featureGate.canUseTaskKeyboardShortcuts,
              let task = keyboardFocusedTask else {
            return
        }
        todoStore.deleteItem(task)
        if editingItem?.id == task.id {
            resetEditor()
            showingEditor = false
        }
    }
    
    private func formattedDueDate(_ item: TodoItem, dueDate: Date) -> String {
        Self.dateFormatter.locale = localizationManager.effectiveLocale
        Self.dateTimeFormatter.locale = localizationManager.effectiveLocale
        if item.hasDueTime {
            return Self.dateTimeFormatter.string(from: dueDate)
        }
        return Self.dateFormatter.string(from: dueDate)
    }

    private func formatLastSyncDate(_ date: Date) -> String {
        Self.lastSyncFormatter.locale = localizationManager.effectiveLocale
        return Self.lastSyncFormatter.string(from: date)
    }
    
    /// Strips the time portion unless the user explicitly opted in.
    private func normalizedDueDate(from date: Date, includeTime: Bool) -> Date {
        guard !includeTime else { return date }
        return Calendar.current.startOfDay(for: date)
    }
    
    /// Preserve an existing time component when moving to a new day.
    private func mergedDueDate(newDay: Date, from task: TodoItem) -> (date: Date, hasTime: Bool) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: newDay)
        guard task.hasDueTime, let existing = task.dueDate else {
            return (dayStart, false)
        }
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: existing)
        let merged = calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: timeComponents.second ?? 0,
            of: dayStart
        ) ?? dayStart
        return (merged, true)
    }
    
    private var filteredItems: [TodoItem] {
        switch selectedSegment {
        case .active:
            return todoStore.pendingItems
        case .completed:
            return todoStore.completedItems
        }
    }

    private var filteredEventTaskGroups: [EventTaskGroupEntry] {
        planningStore.localEvents.compactMap { event in
            let tasks = event.eventTasks.filter { task in
                switch selectedSegment {
                case .active:
                    return !task.isCompleted
                case .completed:
                    return task.isCompleted
                }
            }

            guard !tasks.isEmpty else { return nil }

            return EventTaskGroupEntry(
                id: event.id,
                eventTitle: event.title,
                eventStartDate: event.startDate,
                tasks: tasks.sorted { $0.createdAt < $1.createdAt }
            )
        }
        .sorted {
            let lhsDate = $0.eventStartDate ?? .distantFuture
            let rhsDate = $1.eventStartDate ?? .distantFuture
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return $0.eventTitle.localizedCaseInsensitiveCompare($1.eventTitle) == .orderedAscending
        }
    }

    private var toolbarAICandidateTasks: [TodoItem] {
        filteredItems
    }

    private var taskPlansByID: [UUID: PlanningItem] {
        planningStore.items.reduce(into: [UUID: PlanningItem]()) { result, plan in
            guard plan.sourceType == .task,
                  let sourceID = plan.sourceID,
                  let taskID = UUID(uuidString: sourceID) else {
                return
            }
            result[taskID] = plan
        }
    }

    private var plannedTaskCount: Int {
        todoStore.items.filter { taskPlansByID[$0.id] != nil }.count
    }

    private var unplannedTaskCount: Int {
        max(0, todoStore.items.count - plannedTaskCount)
    }

    private var plannedTodayCount: Int {
        let calendar = Calendar.current
        return todoStore.pendingItems.filter { item in
            guard let start = taskPlansByID[item.id]?.startDate else { return false }
            return calendar.isDateInToday(start)
        }.count
    }

    private func planningItem(for item: TodoItem) -> PlanningItem? {
        taskPlansByID[item.id]
    }

    private func planningStatusLabel(for item: TodoItem) -> String {
        guard let start = planningItem(for: item)?.startDate else {
            return localizationManager.text("tasks.unplanned")
        }
        Self.dateFormatter.locale = localizationManager.effectiveLocale
        Self.dateTimeFormatter.locale = localizationManager.effectiveLocale
        let calendar = Calendar.current
        if calendar.isDateInToday(start) {
            return item.hasDueTime
                ? localizationManager.format("tasks.plan_status.today_time_format", Self.dateTimeFormatter.string(from: start))
                : localizationManager.text("tasks.plan_status.planned_today")
        }
        if calendar.isDateInTomorrow(start) {
            return item.hasDueTime
                ? localizationManager.format("tasks.plan_status.tomorrow_time_format", Self.dateTimeFormatter.string(from: start))
                : localizationManager.text("tasks.plan_status.planned_tomorrow")
        }
        return item.hasDueTime
            ? Self.dateTimeFormatter.string(from: start)
            : Self.dateFormatter.string(from: start)
    }

    private func planTaskForToday(_ item: TodoItem) {
        var updated = item
        updated.dueDate = Calendar.current.startOfDay(for: Date())
        updated.hasDueTime = false
        updated.modifiedAt = Date()
        todoStore.updateItem(updated)
        syncToRemindersIfLinked(updated)
        syncToCalendarIfEnabled(updated)
    }

    private func clearPlanDate(for item: TodoItem) {
        var updated = item
        updated.dueDate = nil
        updated.hasDueTime = false
        updated.modifiedAt = Date()
        todoStore.updateItem(updated)
        syncToRemindersIfLinked(updated)
        syncToCalendarIfEnabled(updated)
    }

    private func restoreCompletedTask(_ item: TodoItem) {
        guard item.isCompleted else { return }
        todoStore.toggleCompletion(item)
        if let updatedItem = todoStore.items.first(where: { $0.id == item.id }) {
            syncToRemindersIfLinked(updatedItem)
            syncToCalendarIfEnabled(updatedItem)
        }
    }

    private var eventSectionDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
            Text(localizationManager.text("tasks.events.section_title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func eventTaskGroupRow(_ group: EventTaskGroupEntry) -> some View {
        let isExpanded = !collapsedEventGroupIDs.contains(group.id)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    toggleEventGroupExpanded(group.id)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.eventTitle)
                        .font(.headline)

                    HStack(spacing: 8) {
                        if let startDate = group.eventStartDate {
                            Label(formattedEventTaskDate(startDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("\(group.tasks.count)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                    }
                }

                Spacer()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    ForEach(group.tasks) { task in
                        eventTaskSubtaskRow(eventID: group.id, task: task)
                    }
                }
                .padding(.leading, 34)
                .transition(subtaskExpansionTransition)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .animation(taskExpansionAnimation, value: isExpanded)
    }

    @ViewBuilder
    private func eventTaskSubtaskRow(eventID: UUID, task: PlanningItem.EventTask) -> some View {
        let showsCompletedState = task.isCompleted

        HStack(spacing: 8) {
            Button {
                planningStore.toggleEventTaskCompletion(eventID: eventID, taskID: task.id)
            } label: {
                Image(systemName: showsCompletedState ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(showsCompletedState ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.subheadline)
                .strikethrough(showsCompletedState)
                .foregroundStyle(showsCompletedState ? .secondary : .primary)
                .opacity(showsCompletedState ? 0.72 : 1.0)

            Spacer()

            Text(task.source == .ai
                 ? localizationManager.text("calendar.event_tasks.source_ai")
                 : localizationManager.text("calendar.event_tasks.source_manual"))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.10))
                .foregroundStyle(.purple)
                .cornerRadius(4)
        }
    }

    private func toggleEventGroupExpanded(_ id: UUID) {
        withAnimation(taskExpansionAnimation) {
            if collapsedEventGroupIDs.contains(id) {
                collapsedEventGroupIDs.remove(id)
            } else {
                collapsedEventGroupIDs.insert(id)
            }
        }
    }

    private func formattedEventTaskDate(_ date: Date) -> String {
        Self.dateFormatter.locale = localizationManager.effectiveLocale
        return Self.dateFormatter.string(from: date)
    }

    private func syncToRemindersIfLinked(_ item: TodoItem) {
        guard permissionsManager.isRemindersAuthorized,
              item.reminderIdentifier != nil else {
            return
        }
        Task {
            try? await remindersSync.syncTask(item)
        }
    }

    private func syncToCalendarIfEnabled(_ item: TodoItem) {
        guard permissionsManager.isCalendarAuthorized,
              item.syncToCalendar || item.calendarEventIdentifier != nil else {
            return
        }
        Task {
            let engine = SyncEngine(permissionsManager: permissionsManager)
            engine.attachTodoStore(todoStore)
            try? await engine.syncCalendarEvents()
        }
    }
    
    private var taskEditorSheet: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(editingItem == nil ? localizationManager.text("tasks.editor.add_title") : localizationManager.text("tasks.editor.edit_title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 10) {
                    TextField(localizationManager.text("tasks.editor.title_placeholder"), text: $titleField)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizationManager.text("tasks.ai_plan.estimated_hours"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Stepper(value: $aiEstimatedHours, in: 1...40) {
                            Text(localizationManager.format("tasks.ai_plan.estimated_hours_value", aiEstimatedHours))
                        }
                    }

                    if featureGate.canUseAdvancedTasks {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizationManager.text("tasks.editor.priority"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Picker("", selection: $priorityField) {
                                ForEach(TodoItem.Priority.allCases, id: \.self) { priority in
                                    Text(priority.displayName).tag(priority)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(localizationManager.text("tasks.editor.pomodoro_estimate"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Stepper(value: $pomodoroEstimateField, in: 1...20) {
                                Text(localizationManager.format("tasks.pomodoro_estimate_value", pomodoroEstimateField))
                            }
                        }
                    }

                    Toggle(localizationManager.text("tasks.editor.set_due_date"), isOn: $dueDateEnabled)
                        .onChange(of: dueDateEnabled) { _, isOn in
                            if !isOn { includeDueTime = false }
                        }
                    
                    if dueDateEnabled {
                        DatePicker(
                            localizationManager.text("tasks.editor.due_date"),
                            selection: $dueDateField,
                            displayedComponents: [.date]
                        )
                        Toggle(localizationManager.text("tasks.editor.include_time"), isOn: $includeDueTime)
                            .toggleStyle(.switch)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if includeDueTime {
                            DatePicker(
                                localizationManager.text("tasks.editor.time"),
                                selection: $dueDateField,
                                displayedComponents: [.hourAndMinute]
                            )
                            .datePickerStyle(.field)
                        } else {
                            Text(localizationManager.text("tasks.editor.date_only_hint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if featureGate.canUseTaskMarkdown {
                        HStack(alignment: .center, spacing: 10) {
                            Text(localizationManager.text("tasks.editor.description_markdown"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if isGeneratingTaskAI {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Working…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Menu {
                                    Button("Improve Task Details") {
                                        handleImproveTaskDraftTapped()
                                    }
                                    .disabled(titleField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && descriptionField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Button("Draft From Idea") {
                                        handleDraftFromIdeaTapped()
                                    }

                                    Divider()

                                    Button(localizationManager.text("tasks.ai_description.button")) {
                                        handleGenerateDescriptionTapped()
                                    }
                                    .disabled(titleField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                } label: {
                                    Label("Task AI", systemImage: "sparkles")
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }

                        TextField(localizationManager.text("tasks.editor.notes_placeholder"), text: $descriptionField, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if let aiDescriptionErrorMessage, !aiDescriptionErrorMessage.isEmpty {
                            Text(aiDescriptionErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        if let aiTaskDraftErrorMessage, !aiTaskDraftErrorMessage.isEmpty {
                            Text(aiTaskDraftErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            presentLockedFeatureInfo(
                                featureName: "Markdown Descriptions",
                                description: "Format task notes with headings, lists, and richer structure.",
                                requiredTier: .plus
                            )
                        } label: {
                            Label("Markdown Descriptions", systemImage: "lock.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    if featureGate.canUseSubtasks, !editorSubtasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localizationManager.text("tasks.subtasks.title"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            ForEach(editorSubtasks) { subtask in
                                HStack(spacing: 10) {
                                    Image(systemName: "checklist")
                                        .foregroundStyle(.secondary)
                                    Text(subtask.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Button {
                                        editorSubtasks.removeAll { $0.id == subtask.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    
                    Text(localizationManager.text("tasks.editor.tags_optional"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(localizationManager.text("tasks.editor.tags_placeholder"), text: $tagsField)
                        .textFieldStyle(.roundedBorder)
                    
                    Toggle(localizationManager.text("tasks.editor.sync_to_calendar"), isOn: $syncToCalendarField)
                        .toggleStyle(.switch)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.top, 6)
                        .help(localizationManager.text("tasks.editor.sync_to_calendar_help"))

                    if let aiPlanErrorMessage, !aiPlanErrorMessage.isEmpty {
                        Text(aiPlanErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                Spacer(minLength: 0)
                
                HStack {
                    Button(localizationManager.text("common.cancel")) {
                        resetEditor()
                        showingEditor = false
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()

                    Button(action: handleAIPlanButtonTapped) {
                        if isGeneratingAIPlan {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(localizationManager.text("tasks.ai_plan.loading"))
                            }
                        } else {
                            Label(localizationManager.text("tasks.ai_plan.button"), systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGeneratingAIPlan || titleField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button(editingItem == nil ? localizationManager.text("common.add") : localizationManager.text("common.save")) {
                        Task { @MainActor in
                            await saveTask()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(titleField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 420)

            if showAITaskDraftSheet {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                taskDraftPromptSheet
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .confirmationDialog(
            localizationManager.text("tasks.ai_description.replace_title"),
            isPresented: $showReplaceDescriptionConfirmation,
            titleVisibility: .visible
        ) {
            Button(localizationManager.text("tasks.ai_description.replace_action")) {
                if let pendingGeneratedDescription {
                    descriptionField = pendingGeneratedDescription
                }
                pendingGeneratedDescription = nil
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) {
                pendingGeneratedDescription = nil
            }
        } message: {
            Text(localizationManager.text("tasks.ai_description.replace_message"))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.18), value: showAITaskDraftSheet)
    }

    private var taskDraftPromptSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Draft Task From Idea")
                .font(.title3.weight(.semibold))

            Text("Paste a rough idea, project note, or messy thought. AI will turn it into a clearer task draft without saving anything automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $aiTaskDraftPrompt)
                .font(.body)
                .frame(minHeight: 180)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let aiTaskDraftErrorMessage, !aiTaskDraftErrorMessage.isEmpty {
                Text(aiTaskDraftErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(localizationManager.text("common.cancel")) {
                    showAITaskDraftSheet = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { @MainActor in
                        await generateTaskDraftFromIdea()
                    }
                } label: {
                    if isGeneratingAITaskDraft {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Drafting…")
                        }
                    } else {
                        Text("Generate Draft")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingAITaskDraft || aiTaskDraftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func openEditorForNew() {
        editingItem = nil
        titleField = ""
        descriptionField = ""
        tagsField = ""
        editorSubtasks = []
        dueDateEnabled = false
        dueDateField = Date()
        includeDueTime = false
        syncToCalendarField = false
        priorityField = .none
        pomodoroEstimateField = 1
        aiEstimatedHours = 1
        aiPlanErrorMessage = nil
        aiDescriptionErrorMessage = nil
        aiTaskDraftErrorMessage = nil
        isGeneratingAIPlan = false
        isGeneratingAIDescription = false
        isGeneratingAITaskDraft = false
        pendingGeneratedDescription = nil
        aiTaskDraftPrompt = ""
        showingEditor = true
    }
    
    private func openEditorForEdit(_ item: TodoItem) {
        editingItem = item
        titleField = item.title
        descriptionField = item.descriptionMarkdown ?? ""
        tagsField = item.tags.joined(separator: ", ")
        editorSubtasks = item.subtasks
        if let due = item.dueDate {
            dueDateEnabled = true
            dueDateField = due
            includeDueTime = item.hasDueTime
        } else {
            dueDateEnabled = false
            dueDateField = Date()
            includeDueTime = false
        }
        syncToCalendarField = item.syncToCalendar
        priorityField = item.priority
        pomodoroEstimateField = item.pomodoroEstimate ?? 1
        aiEstimatedHours = max(1, ((item.durationMinutes ?? 25) + 59) / 60)
        aiPlanErrorMessage = nil
        aiDescriptionErrorMessage = nil
        aiTaskDraftErrorMessage = nil
        isGeneratingAIPlan = false
        isGeneratingAIDescription = false
        isGeneratingAITaskDraft = false
        pendingGeneratedDescription = nil
        aiTaskDraftPrompt = ""
        showingEditor = true
    }
    
    private func resetEditor() {
        editingItem = nil
        titleField = ""
        descriptionField = ""
        tagsField = ""
        editorSubtasks = []
        dueDateEnabled = false
        dueDateField = Date()
        includeDueTime = false
        syncToCalendarField = false
        priorityField = .none
        pomodoroEstimateField = 1
        aiEstimatedHours = 1
        aiPlanErrorMessage = nil
        aiDescriptionErrorMessage = nil
        aiTaskDraftErrorMessage = nil
        isGeneratingAIPlan = false
        isGeneratingAIDescription = false
        isGeneratingAITaskDraft = false
        pendingGeneratedDescription = nil
        aiTaskDraftPrompt = ""
    }
    
    private func saveTask() async {
        await featureGate.refreshSubscriptionStatusIfNeeded()
        aiPlanErrorMessage = nil
        let trimmedTitle = titleField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        let hasDueTime = dueDateEnabled ? includeDueTime : false
        let dueDate = dueDateEnabled ? normalizedDueDate(from: dueDateField, includeTime: includeDueTime) : nil
        let trimmedDescription = descriptionField.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = parsedTagsField()
        
        if var editing = editingItem {
            editing.title = trimmedTitle
            editing.descriptionMarkdown = trimmedDescription.isEmpty ? nil : trimmedDescription
            editing.dueDate = dueDate
            editing.hasDueTime = hasDueTime
            editing.tags = tags
            editing.subtasks = editorSubtasks
            editing.syncToCalendar = syncToCalendarField
            editing.priority = featureGate.canUseAdvancedTasks ? priorityField : .none
            editing.pomodoroEstimate = featureGate.canUseAdvancedTasks ? pomodoroEstimateField : nil
            todoStore.updateItem(editing)
            
            if permissionsManager.isRemindersAuthorized,
               editing.reminderIdentifier != nil {
                Task { try? await remindersSync.syncTask(editing) }
            }
            syncToCalendarIfEnabled(editing)
        } else {
            let newItem = TodoItem(
                title: trimmedTitle,
                descriptionMarkdown: trimmedDescription.isEmpty ? nil : trimmedDescription,
                dueDate: dueDate,
                hasDueTime: hasDueTime,
                durationMinutes: featureGate.canUseAdvancedTasks ? pomodoroEstimateField * 25 : nil,
                priority: featureGate.canUseAdvancedTasks ? priorityField : .none,
                subtasks: editorSubtasks,
                syncToCalendar: syncToCalendarField
            )
            todoStore.addItem(newItem)
            syncToCalendarIfEnabled(newItem)
        }
        
        resetEditor()
        showingEditor = false
    }

    private func generateAIPlan() async {
        aiPlanErrorMessage = nil

        let trimmedTitle = titleField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        guard dueDateEnabled else {
            aiPlanErrorMessage = localizationManager.text("tasks.ai_plan.requires_deadline")
            return
        }

        isGeneratingAIPlan = true
        defer { isGeneratingAIPlan = false }

        do {
            let response = try await AIService.shared.taskBreakdown(
                task: trimmedTitle,
                deadline: Self.aiDeadlineFormatter.string(from: dueDateField),
                estimatedHours: aiEstimatedHours
            )
            try applyAIPlan(
                response,
                dueDate: dueDateEnabled ? normalizedDueDate(from: dueDateField, includeTime: includeDueTime) : nil,
                hasDueTime: dueDateEnabled ? includeDueTime : false,
                parentNotes: descriptionField.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: parsedTagsField(),
                createAsSubtasks: true,
                aiOrigin: .breakdown
            )
            resetEditor()
            showingEditor = false
        } catch {
            aiPlanErrorMessage = (error as NSError).localizedDescription
        }
    }

    private func generateTaskDescription() async {
        aiDescriptionErrorMessage = nil

        let trimmedTitle = titleField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            aiDescriptionErrorMessage = localizationManager.text("tasks.ai_description.requires_title")
            return
        }

        isGeneratingAIDescription = true
        defer { isGeneratingAIDescription = false }

        do {
            let response = try await AIService.shared.generateTaskDescription(
                title: trimmedTitle,
                notes: descriptionField.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let generatedDescription = response.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !generatedDescription.isEmpty else {
                aiDescriptionErrorMessage = localizationManager.text("tasks.ai_description.error")
                return
            }

            let hasExistingDescription = !descriptionField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasExistingDescription {
                pendingGeneratedDescription = generatedDescription
                showReplaceDescriptionConfirmation = true
            } else {
                descriptionField = generatedDescription
            }
        } catch {
            aiDescriptionErrorMessage = localizationManager.text("tasks.ai_description.error")
        }
    }

    private func generateTaskDraftFromIdea() async {
        aiTaskDraftErrorMessage = nil
        let trimmedPrompt = aiTaskDraftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            aiTaskDraftErrorMessage = "Enter an idea first."
            return
        }

        isGeneratingAITaskDraft = true
        defer { isGeneratingAITaskDraft = false }

        do {
            let draft = try await AIService.shared.draftTask(idea: trimmedPrompt)
            applyTaskDraftToEditor(draft)
            showAITaskDraftSheet = false
            aiTaskDraftPrompt = ""
        } catch {
            aiTaskDraftErrorMessage = (error as NSError).localizedDescription
        }
    }

    private func improveCurrentTaskDraft() async {
        aiTaskDraftErrorMessage = nil
        let trimmedTitle = titleField.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionField.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty || !trimmedDescription.isEmpty else {
            aiTaskDraftErrorMessage = "Add a task title or description first."
            return
        }

        let context = [trimmedTitle, trimmedDescription]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        isGeneratingAITaskDraft = true
        defer { isGeneratingAITaskDraft = false }

        do {
            let draft = try await AIService.shared.draftTask(
                idea: context,
                existingTitle: trimmedTitle,
                existingDescription: trimmedDescription
            )
            applyTaskDraftToEditor(draft)
        } catch {
            aiTaskDraftErrorMessage = (error as NSError).localizedDescription
        }
    }

    private func applyTaskDraftToEditor(_ draft: AIService.TaskDraftResponse) {
        if !draft.title.isEmpty {
            titleField = draft.title
        }
        if !draft.description.isEmpty {
            descriptionField = draft.description
        }
        if featureGate.canUseAdvancedTasks {
            if let estimatedPomodoros = draft.estimatedPomodoros {
                pomodoroEstimateField = min(max(estimatedPomodoros, 1), 20)
                aiEstimatedHours = max(1, Int(ceil(Double(estimatedPomodoros * 25) / 60.0)))
            }
            if let priority = draft.priority {
                priorityField = priority
            }
        }
        if featureGate.canUseSubtasks, !draft.subtasks.isEmpty {
            editorSubtasks = draft.subtasks.map { TodoSubtask(title: $0) }
        }

        var mergedTags = parsedTagsField()
        mergedTags.append(contentsOf: draft.tags)
        if let focusStyle = draft.focusStyle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !focusStyle.isEmpty {
            mergedTags.append(focusStyle.replacingOccurrences(of: " ", with: "-"))
        }
        let normalizedTags = Array(NSOrderedSet(array: mergedTags.map { $0.lowercased() })) as? [String] ?? mergedTags
        tagsField = normalizedTags.joined(separator: ", ")
    }

    private func handleAIPlanButtonTapped() {
        Task { @MainActor in
            await featureGate.refreshSubscriptionStatusIfNeeded()
            handleAIPlanButtonTappedAfterRefresh()
        }
    }

    @MainActor
    private func handleAIPlanButtonTappedAfterRefresh() {
        aiPlanErrorMessage = nil

        guard authViewModel.isAuthenticated else {
            showAILoginSheet = true
            return
        }

        if !featureGate.canUseAIAssistantBreakdown {
            presentLockedFeatureInfo(
                featureName: localizationManager.text("feature_gate.paywall.ai_assistant.title"),
                description: localizationManager.text("feature_gate.paywall.ai_assistant.description"),
                requiredTier: .plus,
                requirementText: localizationManager.text("feature_gate.paywall.requires_plus_or_pro")
            )
            return
        }

        if let quotaMessage = featureGate.aiPlanningQuotaMessage {
            aiPlanErrorMessage = quotaMessage
            return
        }

        guard featureGate.canRunAIPlanningRequest else {
            aiPlanErrorMessage = featureGate.aiAssistantDisabledReason(for: .breakdown)
            return
        }

        Task { @MainActor in
            await generateAIPlan()
        }
    }

    private func handleGenerateDescriptionTapped() {
        Task { @MainActor in
            await featureGate.refreshSubscriptionStatusIfNeeded()
            handleGenerateDescriptionTappedAfterRefresh()
        }
    }

    @MainActor
    private func handleGenerateDescriptionTappedAfterRefresh() {
        aiDescriptionErrorMessage = nil

        guard authViewModel.isAuthenticated else {
            showAILoginSheet = true
            return
        }

        guard featureGate.canUseAIAssistantBreakdown else {
            presentLockedFeatureInfo(
                featureName: localizationManager.text("tasks.ai_assistant.button"),
                description: localizationManager.text("feature_gate.paywall.ai_assistant.description"),
                requiredTier: .plus,
                requirementText: localizationManager.text("feature_gate.paywall.requires_plus_or_pro")
            )
            return
        }

        if let quotaMessage = featureGate.aiPlanningQuotaMessage {
            aiDescriptionErrorMessage = quotaMessage
            return
        }

        guard featureGate.canRunAIPlanningRequest else {
            aiDescriptionErrorMessage = localizationManager.text("tasks.ai_description.error")
            return
        }

        Task { @MainActor in
            await generateTaskDescription()
        }
    }

    private func handleDraftFromIdeaTapped() {
        Task { @MainActor in
            await featureGate.refreshSubscriptionStatusIfNeeded()
            handleDraftFromIdeaTappedAfterRefresh()
        }
    }

    @MainActor
    private func handleDraftFromIdeaTappedAfterRefresh() {
        aiTaskDraftErrorMessage = nil

        guard authViewModel.isAuthenticated else {
            showAILoginSheet = true
            return
        }

        guard featureGate.canUseAIAssistantBreakdown else {
            presentLockedFeatureInfo(
                featureName: localizationManager.text("tasks.ai_assistant.title"),
                description: localizationManager.text("feature_gate.paywall.ai_assistant.description"),
                requiredTier: .plus,
                requirementText: localizationManager.text("feature_gate.paywall.requires_plus_or_pro")
            )
            return
        }

        if let quotaMessage = featureGate.aiPlanningQuotaMessage {
            aiTaskDraftErrorMessage = quotaMessage
            return
        }

        guard featureGate.canRunAIPlanningRequest else {
            aiTaskDraftErrorMessage = featureGate.aiAssistantDisabledReason(for: .breakdown)
            return
        }

        showAITaskDraftSheet = true
    }

    private func handleImproveTaskDraftTapped() {
        Task { @MainActor in
            await featureGate.refreshSubscriptionStatusIfNeeded()
            handleImproveTaskDraftTappedAfterRefresh()
        }
    }

    @MainActor
    private func handleImproveTaskDraftTappedAfterRefresh() {
        aiTaskDraftErrorMessage = nil

        guard authViewModel.isAuthenticated else {
            showAILoginSheet = true
            return
        }

        guard featureGate.canUseAIAssistantBreakdown else {
            presentLockedFeatureInfo(
                featureName: localizationManager.text("tasks.ai_assistant.title"),
                description: localizationManager.text("feature_gate.paywall.ai_assistant.description"),
                requiredTier: .plus,
                requirementText: localizationManager.text("feature_gate.paywall.requires_plus_or_pro")
            )
            return
        }

        if let quotaMessage = featureGate.aiPlanningQuotaMessage {
            aiTaskDraftErrorMessage = quotaMessage
            return
        }

        guard featureGate.canRunAIPlanningRequest else {
            aiTaskDraftErrorMessage = featureGate.aiAssistantDisabledReason(for: .breakdown)
            return
        }

        Task { @MainActor in
            await improveCurrentTaskDraft()
        }
    }

    private func handleAIAssistantAction(
        _ action: AIAssistantAction,
        selectedTasks: [TodoItem],
        dueDate: Date,
        estimatedHours: Int
    ) async {
        await featureGate.refreshSubscriptionStatusIfNeeded()
        aiAssistantErrorMessage = nil

        guard authViewModel.isAuthenticated else {
            showAIAssistant = false
            showAILoginSheet = true
            return
        }

        if featureGate.shouldShowUpgradeModal(for: action) {
            switch action {
            case .breakdown:
                presentLockedFeatureInfo(
                    featureName: localizationManager.text("feature_gate.paywall.ai_assistant.title"),
                    description: localizationManager.text("feature_gate.paywall.ai_assistant.breakdown_description"),
                    requiredTier: .plus
                )
            case .draftFromIdea:
                presentLockedFeatureInfo(
                    featureName: localizationManager.text("feature_gate.paywall.ai_assistant.title"),
                    description: localizationManager.text("feature_gate.paywall.ai_assistant.breakdown_description"),
                    requiredTier: .plus
                )
            case .planning:
                presentLockedFeatureInfo(
                    featureName: localizationManager.text("feature_gate.paywall.smart_planning.title"),
                    description: localizationManager.text("feature_gate.paywall.smart_planning.description"),
                    requiredTier: .plus
                )
            case .reschedule:
                presentLockedFeatureInfo(
                    featureName: localizationManager.text("feature_gate.paywall.smart_rescheduling.title"),
                    description: localizationManager.text("feature_gate.paywall.smart_rescheduling.description"),
                    requiredTier: .pro
                )
            }
            return
        }

        if let quotaMessage = featureGate.aiPlanningQuotaMessage {
            aiAssistantErrorMessage = quotaMessage
            return
        }

        guard featureGate.canUseAIAssistantAction(action), !featureGate.isAIQuotaExhausted else {
            aiAssistantErrorMessage = featureGate.aiAssistantDisabledReason(for: action)
            return
        }

        if action.requiresTaskSelection, selectedTasks.isEmpty {
            return
        }

        if action == .draftFromIdea {
            showAIAssistant = false
            if !showingEditor {
                openEditorForNew()
            }
            aiTaskDraftErrorMessage = nil
            aiTaskDraftPrompt = ""
            showAITaskDraftSheet = true
            return
        }

        isRunningAIAssistant = true
        defer { isRunningAIAssistant = false }

        do {
            let response: AIService.AIPlanningResponse

            switch action {
            case .breakdown:
                response = try await AIService.shared.taskBreakdown(
                    task: assistantBreakdownPrompt(for: selectedTasks[0]),
                    deadline: Self.aiDeadlineFormatter.string(from: dueDate),
                    estimatedHours: estimatedHours
                )
            case .planning:
                response = try await AIService.shared.taskPlanning(
                    tasks: selectedTasks.map(\.title),
                    deadline: Self.aiDeadlineFormatter.string(from: dueDate),
                    estimatedHours: estimatedHours
                )
            case .draftFromIdea:
                return
            case .reschedule:
                return
            }

            try applyAIPlan(
                response,
                dueDate: Calendar.current.startOfDay(for: dueDate),
                hasDueTime: false,
                parentNotes: assistantNotes(for: selectedTasks, action: action),
                tags: assistantTags(for: selectedTasks),
                createAsSubtasks: action == .breakdown,
                aiOrigin: action == .planning ? .planning : .breakdown
            )
            showAIAssistant = false
        } catch {
            aiAssistantErrorMessage = (error as NSError).localizedDescription
        }
    }

    private func assistantBreakdownPrompt(for task: TodoItem) -> String {
        let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notes.isEmpty else {
            return task.title
        }
        return "\(task.title)\n\nContext:\n\(notes)"
    }

    private func assistantNotes(for tasks: [TodoItem], action: AIAssistantAction) -> String {
        switch action {
        case .breakdown:
            return tasks[0].notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .draftFromIdea:
            return ""
        case .planning:
            let titles = tasks.map(\.title).joined(separator: ", ")
            return localizationManager.format("tasks.ai_plan.generated_note", titles, tasks.count)
        case .reschedule:
            return ""
        }
    }

    private func assistantTags(for tasks: [TodoItem]) -> [String] {
        Array(Set(tasks.flatMap(\.tags))).sorted()
    }

    private func presentUpgradePaywall(requiredTier: PlanTier, title: String, message: String) {
        upgradePaywallContext = SubscriptionPaywallContext(
            requiredTier: requiredTier,
            title: title,
            message: message
        )
    }

    private func presentLockedFeatureInfo(
        featureName: String,
        description: String,
        requiredTier: PlanTier,
        requirementText: String? = nil
    ) {
        let requiredMessage = requirementText ?? localizedRequirementText(for: requiredTier)
        presentUpgradePaywall(
            requiredTier: requiredTier,
            title: featureName,
            message: "\(description)\n\n\(requiredMessage)"
        )
    }

    private func localizedRequirementText(for requiredTier: PlanTier) -> String {
        switch requiredTier {
        case .free:
            return ""
        case .plus:
            return localizationManager.text("feature_gate.paywall.requires_plus")
        case .pro:
            return localizationManager.text("feature_gate.paywall.requires_pro")
        }
    }

    private func applyAIPlan(
        _ response: AIService.TaskBreakdownResponse,
        dueDate: Date?,
        hasDueTime: Bool,
        parentNotes: String,
        tags: [String],
        createAsSubtasks: Bool = false,
        aiOrigin: TodoItem.AIOrigin
    ) throws {
        guard !response.subtasks.isEmpty else {
            throw AIService.AIServiceError.invalidResponse
        }

        if createAsSubtasks, featureGate.canUseSubtasks {
            let item = TodoItem(
                title: response.taskTitle,
                descriptionMarkdown: parentNotes.isEmpty ? nil : parentNotes,
                dueDate: dueDate,
                hasDueTime: hasDueTime,
                durationMinutes: totalDurationMinutes(for: response.subtasks),
                priority: .medium,
                subtasks: response.subtasks.map { TodoSubtask(title: "\($0.title) (\($0.pomodoros)x25m)") },
                tags: tags,
                syncToCalendar: false,
                aiOrigin: aiOrigin,
                plannedPomodoroCount: response.estimatedPomodoros
            )
            todoStore.addItem(item)
        } else {
            for (index, subtask) in response.subtasks.enumerated() {
                let item = TodoItem(
                    title: subtask.title,
                    descriptionMarkdown: aiNotes(
                        parentTaskTitle: response.taskTitle,
                        parentNotes: parentNotes,
                        pomodoros: subtask.pomodoros
                    ),
                    dueDate: dueDate,
                    hasDueTime: hasDueTime,
                    durationMinutes: durationMinutes(for: subtask.pomodoros, presetID: subtask.pomodoroPreset),
                    tags: tags,
                    syncToCalendar: false,
                    aiOrigin: aiOrigin,
                    aiOrder: index,
                    pomodoroPresetID: subtask.pomodoroPreset,
                    plannedPomodoroCount: subtask.pomodoros
                )
                todoStore.addItem(item)
            }
        }
    }

    private func parsedTagsField() -> [String] {
        tagsField
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func aiNotes(parentTaskTitle: String, parentNotes: String, pomodoros: Int) -> String? {
        let generatedSummary = localizationManager.format("tasks.ai_plan.generated_note", parentTaskTitle, pomodoros)
        guard !parentNotes.isEmpty else {
            return generatedSummary
        }
        return "\(generatedSummary)\n\(parentNotes)"
    }

    private func durationMinutes(for pomodoros: Int, presetID: String?) -> Int {
        let preset = Preset.matching(id: presetID) ?? Preset.shortestBuiltIn
        return max(1, pomodoros) * max(1, preset.durationConfig.workDuration / 60)
    }

    private func totalDurationMinutes(for subtasks: [AIService.AIPlanningResponse.Subtask]) -> Int {
        subtasks.reduce(0) { total, subtask in
            total + durationMinutes(for: subtask.pomodoros, presetID: subtask.pomodoroPreset)
        }
    }
}

// MARK: - Selection helpers

extension TodoListView {
    fileprivate func handleTaskSelection(_ item: TodoItem) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)
        
        if isShift, let anchor = lastSelectedTaskID,
           let anchorIndex = filteredItems.firstIndex(where: { $0.id == anchor }),
           let targetIndex = filteredItems.firstIndex(where: { $0.id == item.id }) {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            let rangeIDs = filteredItems[lower...upper].map { $0.id }
            selectedTaskIDs.formUnion(rangeIDs)
            lastSelectedTaskID = item.id
            return
        }
        
        if isCommand {
            if selectedTaskIDs.contains(item.id) {
                selectedTaskIDs.remove(item.id)
            } else {
                selectedTaskIDs.insert(item.id)
                lastSelectedTaskID = item.id
            }
            return
        }
        
        // Default single selection
        selectedTaskIDs = [item.id]
        lastSelectedTaskID = item.id
    }
}

// MARK: - Batch actions

extension TodoListView {
    @ViewBuilder
    fileprivate var batchActionsBar: some View {
        HStack(spacing: 12) {
            Text(localizationManager.format("common.selected_count", selectedTaskIDs.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
            
            DatePicker(
                localizationManager.text("common.move_to"),
                selection: $batchDueDate,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            
            Button {
                applyBatchMove(to: batchDueDate)
            } label: {
                Label(localizationManager.text("common.move"), systemImage: "arrow.right.circle")
            }
            .buttonStyle(.bordered)
            
            Button {
                applyBatchClearDate()
            } label: {
                Label(localizationManager.text("tasks.action.clear_date"), systemImage: "calendar.badge.minus")
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button(role: .destructive) {
                showBatchDeleteConfirmation = true
            } label: {
                Label(localizationManager.text("common.delete"), systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .alert(localizationManager.format("tasks.batch.delete_confirmation_title", selectedTaskIDs.count), isPresented: $showBatchDeleteConfirmation) {
            Button(localizationManager.text("common.delete"), role: .destructive) {
                applyBatchDelete()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("tasks.batch.delete_confirmation_body"))
        }
    }
    
    /// Move all selected tasks to a specific date (user-invoked, explicit).
    fileprivate func applyBatchMove(to date: Date) {
        let tasks = selectedTasks()
        guard !tasks.isEmpty else { return }
        for var task in tasks {
            let merged = mergedDueDate(newDay: date, from: task)
            task.dueDate = merged.date
            task.hasDueTime = merged.hasTime
            task.modifiedAt = Date()
            todoStore.updateItem(task)
            
            // Propagate to Reminders/Calendar only for managed items; this is user-initiated.
            if permissionsManager.isRemindersAuthorized,
               task.reminderIdentifier != nil {
                Task { try? await remindersSync.syncTask(task) }
            }
            syncToCalendarIfEnabled(task)
        }
        clearTaskSelection()
    }
    
    /// Clear due date on selected tasks.
    fileprivate func applyBatchClearDate() {
        let tasks = selectedTasks()
        guard !tasks.isEmpty else { return }
        for var task in tasks {
            task.dueDate = nil
            task.hasDueTime = false
            task.modifiedAt = Date()
            todoStore.updateItem(task)
            if permissionsManager.isRemindersAuthorized,
               task.reminderIdentifier != nil {
                Task { try? await remindersSync.syncTask(task) }
            }
            syncToCalendarIfEnabled(task)
        }
        clearTaskSelection()
    }
    
    /// Atomic delete for selected tasks.
    fileprivate func applyBatchDelete() {
        let tasks = selectedTasks()
        guard !tasks.isEmpty else { return }
        for task in tasks {
            todoStore.deleteItem(task)
        }
        clearTaskSelection()
    }
    
    private func selectedTasks() -> [TodoItem] {
        todoStore.items.filter { selectedTaskIDs.contains($0.id) }
    }
    
    private func clearTaskSelection() {
        selectedTaskIDs.removeAll()
        lastSelectedTaskID = nil
    }
}

#Preview {
    MainActor.assumeIsolated {
        let store = TodoStore()
        let planningStore = PlanningStore()
        store.attachPlanningStore(planningStore)
        let sync = RemindersSync(permissionsManager: .shared)
        sync.setTodoStore(store)

        return TodoListView(
            todoStore: store,
            planningStore: planningStore,
            remindersSync: sync,
            permissionsManager: .shared
        )
        .frame(width: 700, height: 600)
    }
}

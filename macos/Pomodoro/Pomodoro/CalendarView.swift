import SwiftUI
import EventKit
import AppKit
import FirebaseAuth
import FirebaseFunctions

/// Calendar view showing time-based events and allowing event creation.
/// Blocked when unauthorized with explanation and enable button.
@MainActor
struct CalendarView: View {
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject private var featureGate = FeatureGate.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Namespace private var rescheduleAnimationNamespace
    
    @State private var selectedView: ViewType = .day
    @State private var anchorDate: Date = Date()
    @State private var selectedEventIDs: Set<String> = []
    @State private var lastSelectedEventID: String?
    @State private var batchEventDate: Date = Date()
    @State private var showDeleteEventsConfirmation = false
    @State private var batchEventWarning: String?
    
    // New event sheet state
    @State private var showingAddEvent = false
    @State private var newEventTitle: String = ""
    @State private var newEventStart: Date = Date()
    @State private var newEventDurationMinutes: Int = 60
    @State private var newEventNotes: String = ""
    @State private var addEventError: String?
    @State private var showAIAssistant = false
    @State private var isRunningAIAssistant = false
    @State private var aiAssistantErrorMessage: String?
    @State private var isRescheduling = false
    @State private var rescheduleError: String?
    @State private var showAILoginSheet = false
    @State private var upgradePaywallContext: SubscriptionPaywallContext?
    @State private var selectedLocalEventID: UUID?

    // MARK: - Reschedule state
    /// Snapshot of tasks/events as they existed before the last reschedule — used for Undo.
    @State private var rescheduleUndoSnapshot: RescheduleUndoSnapshot? = nil
    /// Set of calendarEventIdentifiers that were written/changed during the last reschedule.
    @State private var recentlyRescheduledEventIDs: Set<String> = []
    /// Toast shown after a successful reschedule.
    @State private var rescheduleToast: RescheduleToast? = nil

    /// Lightweight value type for the post-reschedule toast.
    private struct RescheduleToast {
        let changedCount: Int
    }

    private struct CalendarEventSnapshot {
        let eventIdentifier: String
        let title: String
        let start: Date
        let end: Date
    }

    private struct RescheduleUndoSnapshot {
        let tasks: [TodoItem]
        let restoredEvents: [CalendarEventSnapshot]
        let createdEventIDs: [String]
    }

    private struct AppliedRescheduleResult {
        let changedEventIDs: Set<String>
        let undoSnapshot: RescheduleUndoSnapshot
    }

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E, MMM d"
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
    
    enum ViewType {
        case day
        case week
        case month
        
        var title: String {
            switch self {
            case .day: return LocalizationManager.shared.text("calendar.view.day")
            case .week: return LocalizationManager.shared.text("calendar.view.week")
            case .month: return LocalizationManager.shared.text("calendar.view.month")
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if permissionsManager.isCalendarAuthorized {
                authorizedContent
            } else {
                unauthorizedContent
            }
        }
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 900, minHeight: 520, alignment: .top)
        .onAppear {
            permissionsManager.refreshCalendarStatus()
            if permissionsManager.isCalendarAuthorized {
                Task {
                    await loadEvents()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarGoToToday)) { _ in
            selectedView = .day
            anchorDate = Date()
            if permissionsManager.isCalendarAuthorized {
                Task {
                    await loadEvents()
                }
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventSheet(
                title: $newEventTitle,
                startDate: $newEventStart,
                durationMinutes: $newEventDurationMinutes,
                notes: $newEventNotes,
                errorMessage: addEventError,
                onCancel: {
                    showingAddEvent = false
                    addEventError = nil
                },
                onSave: {
                    Task { await saveEvent() }
                }
            )
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
        .sheet(isPresented: Binding(
            get: { selectedLocalEventID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedLocalEventID = nil
                }
            }
        )) {
            if let selectedEventID = selectedLocalEventID {
                EventTaskDetailSheet(
                    eventID: selectedEventID,
                    planningStore: planningStore,
                    todoStore: todoStore,
                    onClose: { selectedLocalEventID = nil }
                )
                .environmentObject(authViewModel)
                .environmentObject(localizationManager)
            }
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView(
                tasks: todoStore.pendingItems,
                availableActions: [.breakdown, .planning, .reschedule],
                isLoading: isRunningAIAssistant || isRescheduling,
                errorMessage: rescheduleError ?? aiAssistantErrorMessage,
                isActionEnabled: { action in
                    featureGate.canUseAIAssistantAction(action) && !(action == .reschedule && isRescheduling)
                },
                onClose: { showAIAssistant = false },
                onLockedActionTap: { action in
                    switch action {
                    case .reschedule:
                        presentAISchedulingUpgradePrompt()
                    case .planning:
                        presentLockedFeatureInfo(
                            featureName: localizationManager.text("feature_gate.paywall.smart_planning.title"),
                            description: localizationManager.text("feature_gate.paywall.smart_planning.description"),
                            requiredTier: .plus
                        )
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
                    }
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
    }
    
    private var authorizedContent: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizationManager.text("calendar.title"))
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        Text(localizationManager.text("calendar.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Picker(localizationManager.text("calendar.view"), selection: $selectedView) {
                            Text(localizationManager.text("calendar.view.day")).tag(ViewType.day)
                            Text(localizationManager.text("calendar.view.week")).tag(ViewType.week)
                            Text(localizationManager.text("calendar.view.month")).tag(ViewType.month)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                        .onChange(of: selectedView) { _, _ in
                            Task { await loadEvents() }
                        }

                        DatePicker(
                            "",
                            selection: $anchorDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .onChange(of: anchorDate) { _, _ in
                            Task { await loadEvents() }
                        }

                        Spacer()

                        Button {
                            prepareNewEventDefaults()
                            showingAddEvent = true
                        } label: {
                            Label(localizationManager.text("calendar.add_event"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
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
                        } label: {
                            Label(localizationManager.text("tasks.ai_assistant.button"), systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .help(localizationManager.text("calendar.ai_assistant.reschedule_description"))

                        Button {
                            Task { await loadEvents() }
                        } label: {
                            Label(localizationManager.text("common.refresh"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    if selectedEventIDs.count > 1 {
                        batchEventActionsBar
                    }
                }

                // Events list constrained to the available detail height
                GeometryReader { proxy in
                    ScrollView {
                        eventsContent(maxWidth: proxy.size.width)
                    }
                    .frame(height: max(proxy.size.height, 280))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 860, alignment: .leading)

            // MARK: Reschedule toast
            if let toast = rescheduleToast {
                rescheduleToastView(toast)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .padding(.top, 24)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: rescheduleToast != nil)
    }
    
    private var unauthorizedContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                Text(localizationManager.text("calendar.unavailable.title"))
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text(localizationManager.text("calendar.unavailable.body"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(localizationManager.text("calendar.unavailable.cta"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 400)
            
            Button(action: {
                Task {
                    await permissionsManager.requestCalendarPermission()
                }
            }) {
                Label(localizationManager.text("calendar.request_access"), systemImage: "calendar")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(48)
        .frame(maxWidth: 520, minHeight: 420, alignment: .center)
        .alert(localizationManager.text("calendar.access_denied.title"), isPresented: $permissionsManager.showCalendarDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("calendar.access_denied.body"))
        }
    }

    @ViewBuilder
    private func rescheduleToastView(_ toast: RescheduleToast) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizationManager.text("calendar.reschedule.toast_title"))
                    .font(.subheadline.weight(.semibold))
                if toast.changedCount > 0 {
                    Text(localizationManager.format("calendar.reschedule.toast_detail", toast.changedCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(localizationManager.text("calendar.reschedule.undo")) {
                revertCalendarReschedule()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private func eventsContent(maxWidth: CGFloat) -> some View {        if calendarManager.isLoading {
            ProgressView(localizationManager.text("calendar.loading"))
                .padding(32)
                .frame(maxWidth: maxWidth, alignment: .leading)
        } else {
            switch selectedView {
            case .day:
                dayContent(maxWidth: maxWidth)
            case .week:
                WeekCalendarView(
                    days: daysInWeek(from: anchorDate),
                    events: calendarManager.events,
                    localEvents: planningStore.localEvents,
                    tasks: todoStore.items,
                    onSelectLocalEvent: { event in
                        selectedLocalEventID = event.id
                    }
                )
                .frame(maxWidth: maxWidth, alignment: .leading)
            case .month:
                monthContent(maxWidth: maxWidth)
            }
        }
    }
    
    @ViewBuilder
    private func dayContent(maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            daySummary
            dayBlocks
        }
        .frame(maxWidth: maxWidth, alignment: Alignment.leading)
        .padding(Edge.Set.horizontal, 8)
    }
    
    @ViewBuilder
    private func monthContent(maxWidth: CGFloat) -> some View {
        CalendarMonthView(
            date: anchorDate,
            events: calendarManager.events,
            localEvents: planningStore.localEvents,
            onSelectLocalEvent: { event in
                selectedLocalEventID = event.id
            }
        )
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private func handleAIAssistantAction(
        _ action: AIAssistantAction,
        selectedTasks: [TodoItem],
        dueDate: Date,
        estimatedHours: Int
    ) async {
        await featureGate.refreshSubscriptionStatusIfNeeded()
        aiAssistantErrorMessage = nil
        rescheduleError = nil

        guard authViewModel.isAuthenticated else {
            showAIAssistant = false
            showAILoginSheet = true
            return
        }

        if let quotaMessage = featureGate.aiPlanningQuotaMessage {
            aiAssistantErrorMessage = quotaMessage
            return
        }

        guard featureGate.canUseAIAssistantAction(action), !featureGate.isAIQuotaExhausted else {
            switch action {
            case .reschedule:
                presentAISchedulingUpgradePrompt()
            case .planning:
                aiAssistantErrorMessage = localizationManager.text("tasks.ai_assistant.planning_requires_plus")
            case .breakdown:
                aiAssistantErrorMessage = localizationManager.text("tasks.ai_assistant.breakdown_requires_plus")
            case .draftFromIdea:
                aiAssistantErrorMessage = localizationManager.text("tasks.ai_assistant.draft_from_idea_requires_plus")
            }
            return
        }

        isRunningAIAssistant = true
        defer { isRunningAIAssistant = false }

        do {
            switch action {
            case .breakdown:
                guard let task = selectedTasks.first else { return }
                let response = try await AIService.shared.taskBreakdown(
                    task: assistantBreakdownPrompt(for: task),
                    deadline: Self.aiDeadlineFormatter.string(from: dueDate),
                    estimatedHours: estimatedHours
                )
                try applyAIPlan(
                    response,
                    dueDate: Calendar.current.startOfDay(for: dueDate),
                    parentNotes: assistantNotes(for: selectedTasks, action: action),
                    tags: assistantTags(for: selectedTasks),
                    createAsSubtasks: true,
                    aiOrigin: .breakdown
                )
            case .planning:
                guard !selectedTasks.isEmpty else { return }
                let response = try await AIService.shared.taskPlanning(
                    tasks: selectedTasks.map(\.title),
                    deadline: Self.aiDeadlineFormatter.string(from: dueDate),
                    estimatedHours: estimatedHours
                )
                try applyAIPlan(
                    response,
                    dueDate: Calendar.current.startOfDay(for: dueDate),
                    parentNotes: assistantNotes(for: selectedTasks, action: action),
                    tags: assistantTags(for: selectedTasks),
                    createAsSubtasks: false,
                    aiOrigin: .planning
                )
            case .draftFromIdea:
                return
            case .reschedule:
                await performCalendarReschedule()
            }
            if action != .reschedule || rescheduleError == nil {
                showAIAssistant = false
            }
        } catch {
            if action == .reschedule {
                rescheduleError = "Failed to reschedule. Please try again."
            } else {
                aiAssistantErrorMessage = (error as NSError).localizedDescription
            }
        }
    }

    private func assistantBreakdownPrompt(for task: TodoItem) -> String {
        let notes = task.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notes.isEmpty else { return task.title }
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

    private func applyAIPlan(
        _ response: AIService.TaskBreakdownResponse,
        dueDate: Date?,
        parentNotes: String,
        tags: [String],
        createAsSubtasks: Bool,
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
                hasDueTime: false,
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
                    hasDueTime: false,
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

    private func applyCalendarSchedule(_ response: AIService.AIScheduleResponse) throws {
        guard response.success, !response.schedule.isEmpty else {
            throw AIService.AIServiceError.invalidResponse
        }

        let eventStore = SharedEventStore.shared.eventStore
        let defaultCalendar = eventStore.defaultCalendarForNewEvents

        for entry in response.schedule {
            guard let taskID = UUID(uuidString: entry.taskId),
                  let existing = todoStore.items.first(where: { $0.id == taskID }) else {
                continue
            }

            var updated = existing
            updated.dueDate = entry.start
            updated.hasDueTime = true
            updated.durationMinutes = max(max(1, Preset.shortestBuiltIn.durationConfig.workDuration / 60), Int(entry.end.timeIntervalSince(entry.start) / 60))
            updated.syncToCalendar = entry.calendarWritable
            updated.aiOrigin = .calendarSchedule
            updated.pomodoroPresetID = entry.pomodoroPreset
            updated.plannedPomodoroCount = entry.pomodoros
            updated.modifiedAt = Date()
            todoStore.updateItem(updated)

            guard entry.calendarWritable else {
                print("[CalendarView] Skipping read-only schedule block for task \(entry.taskId)")
                continue
            }

            guard let defaultCalendar else {
                print("[CalendarView] No writable default calendar available for scheduled task \(entry.taskId)")
                continue
            }

            let event = EKEvent(eventStore: eventStore)
            event.title = entry.taskTitle
            event.startDate = entry.start
            event.endDate = entry.end
            event.isAllDay = false
            event.calendar = defaultCalendar

            do {
                try eventStore.save(event, span: .thisEvent, commit: true)
                if let savedEventId = event.eventIdentifier {
                    var linked = updated
                    linked.calendarEventIdentifier = savedEventId
                    linked.linkedCalendarEventId = savedEventId
                    todoStore.updateItem(linked)
                }
            } catch {
                print("[CalendarView] Failed to save scheduled event for task \(entry.taskId): \(error)")
            }
        }

        calendarManager.updateAIFreeSlots(response.freeSlots)
        Task {
            await loadEvents()
        }
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

    private func presentAISchedulingUpgradePrompt() {
        presentLockedFeatureInfo(
            featureName: localizationManager.text("feature_gate.paywall.smart_rescheduling.title"),
            description: localizationManager.text("feature_gate.paywall.smart_rescheduling.description"),
            requiredTier: .pro
        )
    }

    private func performCalendarReschedule() async {
        print("Reschedule button tapped")
        await featureGate.refreshSubscriptionStatusIfNeeded()
        isRescheduling = true
        rescheduleError = nil
        defer { isRescheduling = false }

        withAnimation(.easeInOut(duration: 0.2)) {
            rescheduleToast = nil
            recentlyRescheduledEventIDs = []
        }

        // Prefer today first, but include tomorrow so true overflow can spill over.
        let schedulingStart = Calendar.current.startOfDay(for: Date())
        guard let preferredDayEnd = Calendar.current.date(byAdding: .day, value: 1, to: schedulingStart),
              let schedulingRangeEnd = Calendar.current.date(byAdding: .day, value: 2, to: schedulingStart) else { return }

        let calendarEvents = calendarManager.readEvents(from: schedulingStart, to: schedulingRangeEnd)
        let schedulableTasks = tasksRelevantForTodayReschedule(
            from: todoStore.pendingItems,
            calendarEvents: calendarEvents,
            schedulingEnd: preferredDayEnd
        )
        guard !schedulableTasks.isEmpty else {
            rescheduleError = "No tasks planned for today to reorganize."
            return
        }

        let immutableCalendarEvents = immutableCalendarEventsForTodayReschedule(
            allEvents: calendarEvents,
            schedulableTasks: schedulableTasks
        )
        let freeSlots = calendarFreeSlots(from: immutableCalendarEvents, rangeStart: schedulingStart, rangeEnd: schedulingRangeEnd)
        let workingHours = defaultWorkingHours()
        let schedulingPreset = Preset.shortestBuiltIn
        let requestTasks = rescheduleRequestTasks(from: schedulableTasks, schedulingEnd: schedulingRangeEnd)

        // Snapshot current task state for potential undo.
        let preRescheduleSnapshot = schedulableTasks

        do {
            print("Sending reschedule request to backend (scope: today)")
            let decoded = try await AIService.shared.calendarReschedule(
                tasks: requestTasks,
                events: immutableCalendarEvents,
                freeSlots: freeSlots,
                preferences: .init(
                    pomodoroLength: max(1, schedulingPreset.durationConfig.workDuration / 60),
                    breakLength: max(0, schedulingPreset.durationConfig.shortBreakDuration / 60),
                    workingHoursStart: workingHours.start,
                    workingHoursEnd: workingHours.end
                ),
                preferredDayEnd: preferredDayEnd
            )

            guard decoded.success else {
                rescheduleError = "Scheduling request was rejected by the server."
                return
            }

            guard !decoded.schedule.isEmpty else {
                rescheduleError = "No schedule could be generated."
                return
            }

            // Persist the before-state and apply the new schedule.
            let result = try applyCalendarScheduleReturningResult(
                decoded,
                originalTasks: preRescheduleSnapshot
            )
            rescheduleUndoSnapshot = result.undoSnapshot

            // Show animated highlight and toast.
            withAnimation(.easeInOut(duration: 0.5)) {
                recentlyRescheduledEventIDs = result.changedEventIDs
                rescheduleToast = RescheduleToast(changedCount: result.changedEventIDs.count)
            }

            // Auto-clear highlights after 4 s; dismiss toast after 6 s.
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { recentlyRescheduledEventIDs = [] }
            }
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                withAnimation { rescheduleToast = nil }
            }

        } catch {
            print("[CalendarView] Reschedule request failed: \(error)")
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain,
               nsError.code == FunctionsErrorCode.deadlineExceeded.rawValue {
                rescheduleError = "Scheduling request timed out. Please try again."
            } else {
                rescheduleError = error.localizedDescription
            }
        }
    }

    /// Restores tasks from the pre-reschedule snapshot and reloads events.
    private func revertCalendarReschedule() {
        guard let snapshot = rescheduleUndoSnapshot else { return }
        let eventStore = SharedEventStore.shared.eventStore

        for eventIdentifier in snapshot.createdEventIDs {
            guard let event = eventStore.event(withIdentifier: eventIdentifier),
                  event.calendar.allowsContentModifications else {
                continue
            }
            try? eventStore.remove(event, span: .thisEvent, commit: false)
        }

        for eventSnapshot in snapshot.restoredEvents {
            guard let event = eventStore.event(withIdentifier: eventSnapshot.eventIdentifier),
                  event.calendar.allowsContentModifications else {
                continue
            }
            event.title = eventSnapshot.title
            event.startDate = eventSnapshot.start
            event.endDate = eventSnapshot.end
            try? eventStore.save(event, span: .thisEvent, commit: false)
        }

        try? eventStore.commit()

        for item in snapshot.tasks {
            todoStore.updateItem(item)
        }
        rescheduleUndoSnapshot = nil
        withAnimation { rescheduleToast = nil }
        recentlyRescheduledEventIDs = []
        Task { await loadEvents() }
    }

    private func defaultWorkingHours() -> (start: String, end: String) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"

        let calendar = Calendar.current
        let today = Date()
        let startDate = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: today) ?? today
        let endDate = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: today) ?? today
        return (start: formatter.string(from: startDate), end: formatter.string(from: endDate))
    }

    private func calendarFreeSlots(from events: [EKEvent], rangeStart: Date, rangeEnd: Date) -> [AIService.FreeSlot] {
        guard rangeEnd > rangeStart else { return [] }

        let workingHours = defaultWorkingHoursComponents()
        var freeSlots: [AIService.FreeSlot] = []
        let calendar = Calendar.current
        var dayCursor = calendar.startOfDay(for: rangeStart)

        while dayCursor < rangeEnd {
            guard let workingStart = calendar.date(
                bySettingHour: workingHours.startHour,
                minute: workingHours.startMinute,
                second: 0,
                of: dayCursor
            ),
            let workingEnd = calendar.date(
                bySettingHour: workingHours.endHour,
                minute: workingHours.endMinute,
                second: 0,
                of: dayCursor
            ) else {
                break
            }

            let dayStart = max(workingStart, rangeStart)
            let dayEnd = min(workingEnd, rangeEnd)
            if dayEnd > dayStart {
                let dayEvents = events
                    .filter { $0.endDate > dayStart && $0.startDate < dayEnd }
                    .sorted { $0.startDate < $1.startDate }

                var cursor = dayStart
                for event in dayEvents {
                    let blockStart = max(event.startDate, dayStart)
                    let blockEnd = min(event.endDate, dayEnd)
                    if blockStart > cursor {
                        freeSlots.append(AIService.FreeSlot(start: cursor, end: blockStart))
                    }
                    cursor = max(cursor, blockEnd)
                }

                if cursor < dayEnd {
                    freeSlots.append(AIService.FreeSlot(start: cursor, end: dayEnd))
                }
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayCursor) else {
                break
            }
            dayCursor = nextDay
        }

        return freeSlots.filter { $0.end > $0.start }
    }

    private func isSubscribedCalendar(_ calendar: EKCalendar) -> Bool {
        calendar.type == .subscription
    }

    private func defaultWorkingHoursComponents() -> (startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        (startHour: 8, startMinute: 0, endHour: 22, endMinute: 0)
    }
    
    private func daysInWeek(from date: Date) -> [Date] {
        var days: [Date] = []
        var calendar = Calendar.current
        calendar.locale = localizationManager.effectiveLocale
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        guard let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: startOfDay) else {
            return days
        }
        for offset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: startOfWeek) {
                days.append(day)
            }
        }
        return days
    }
    
    private func loadEvents() async {
        switch selectedView {
        case .day:
            await calendarManager.fetchDayEvents(for: anchorDate)
        case .week:
            await calendarManager.fetchWeekEvents(containing: anchorDate)
        case .month:
            await calendarManager.fetchMonthEvents(containing: anchorDate)
        }
    }

    private func formatEventTime(_ event: EKEvent) -> String {
        if event.isAllDay {
            return localizationManager.text("calendar.all_day")
        }
        Self.eventTimeFormatter.locale = localizationManager.effectiveLocale
        let start = Self.eventTimeFormatter.string(from: event.startDate)
        let end = Self.eventTimeFormatter.string(from: event.endDate)
        return "\(start) - \(end)"
    }

    // MARK: - Day helpers

    private var daySummary: some View {
        let todayEvents = events(for: anchorDate)
        let todayLocalEvents = localEvents(for: anchorDate)
        let todayTasks = tasks(for: anchorDate)
        let totalMinutes = todayEvents.reduce(0) { partial, event in
            partial + max(0, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
        } + todayLocalEvents.reduce(0) { partial, item in
            guard let start = item.startDate else { return partial }
            let end = item.endDate ?? start
            return partial + max(0, Int(end.timeIntervalSince(start) / 60))
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.text("calendar.today_summary"))
                .font(.headline)
            HStack(spacing: 12) {
                summaryPill(title: localizationManager.text("calendar.blocks"), value: "\(todayEvents.count + todayLocalEvents.count)")
                summaryPill(title: localizationManager.text("calendar.tasks"), value: "\(todayTasks.count)")
                summaryPill(title: localizationManager.text("calendar.planned_mins"), value: "\(totalMinutes)")
            }
        }
    }

    private var dayBlocks: some View {
        let todayEvents = events(for: anchorDate)
        let todayLocalEvents = localEvents(for: anchorDate)
        let todayTasks = tasks(for: anchorDate)

        return ScrollView {
            if todayEvents.isEmpty && todayLocalEvents.isEmpty && todayTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(localizationManager.text("calendar.no_blocks_today"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !todayEvents.isEmpty || !todayLocalEvents.isEmpty {
                        Text(localizationManager.text("calendar.time_blocks"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(dayEventBlocks(events: todayEvents, localEvents: todayLocalEvents)) { block in
                            dayEventBlockView(block, events: todayEvents)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .move(edge: .bottom))
                                ))
                        }
                    }

                    if !todayTasks.isEmpty {
                        Text(localizationManager.text("calendar.tasks"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(todayTasks) { task in
                            taskCard(task)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: todayEvents.map { "\(($0.eventIdentifier ?? "missing"))-\($0.startDate.timeIntervalSinceReferenceDate)" })
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 360, alignment: .top)
    }

    // MARK: - Card builders

    private func blockCard(_ event: EKEvent, events: [EKEvent]) -> some View {
        let isSelected = event.eventIdentifier.map { selectedEventIDs.contains($0) } ?? false
        let isRescheduled = event.eventIdentifier.map { recentlyRescheduledEventIDs.contains($0) } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(event.title ?? localizationManager.text("common.untitled"))
                    .font(.headline)
                if isRescheduled {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            Text(formatEventTime(event))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let calendar = event.calendar {
                Text(calendar.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isRescheduled
                ? Color.green.opacity(0.10)
                : (isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
        )
        .overlay(
            isRescheduled
                ? RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.4), lineWidth: 1)
                : nil
        )
        .cornerRadius(8)
        .scaleEffect(isRescheduled ? 1.02 : 1.0)
        .shadow(color: isRescheduled ? Color.green.opacity(0.18) : .clear, radius: 10, x: 0, y: 6)
        .modifier(RescheduleMatchedGeometry(
            eventIdentifier: event.eventIdentifier,
            namespace: rescheduleAnimationNamespace
        ))
        .contentShape(Rectangle())
        .onTapGesture(perform: {
            handleEventSelection(event, allEvents: events)
        })
    }

    private func taskCard(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
                .strikethrough(item.isCompleted)
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let due = item.dueDate {
                Text(formattedTaskDue(item: item, due: due))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func dayEventBlockView(_ block: DayEventBlock, events: [EKEvent]) -> some View {
        switch block {
        case .system(let event):
            blockCard(event, events: events)
        case .local(let item):
            localEventCard(item)
        }
    }

    private func localEventCard(_ item: PlanningItem) -> some View {
        Button {
            selectedLocalEventID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                    if item.hasTaskMode && !item.eventTasks.isEmpty {
                        Text("\(item.eventTasks.count)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(formattedLocalEventTime(item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.06))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection helpers

    private func handleEventSelection(_ event: EKEvent, allEvents: [EKEvent]) {
        guard let id = event.eventIdentifier else { return }
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)
        
        if isShift, let anchor = lastSelectedEventID,
           let anchorIndex = allEvents.firstIndex(where: { $0.eventIdentifier == anchor }),
           let targetIndex = allEvents.firstIndex(where: { $0.eventIdentifier == id }) {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            let rangeIDs = allEvents[lower...upper].compactMap { $0.eventIdentifier }
            selectedEventIDs.formUnion(rangeIDs)
            lastSelectedEventID = id
            return
        }
        
        if isCommand {
            if selectedEventIDs.contains(id) {
                selectedEventIDs.remove(id)
            } else {
                selectedEventIDs.insert(id)
                lastSelectedEventID = id
            }
            return
        }
        
        // Default single selection
        selectedEventIDs = [id]
        lastSelectedEventID = id
    }
    
    @ViewBuilder
    private var batchEventActionsBar: some View {
        let editableSelection = selectedEventIDs.compactMap { id in
            calendarManager.events.first(where: { $0.eventIdentifier == id })
        }.filter { $0.calendar.allowsContentModifications }
        let hasReadOnly = selectedEventIDs.count != editableSelection.count
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(localizationManager.format("common.selected_count", selectedEventIDs.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if hasReadOnly {
                    Text(localizationManager.text("calendar.read_only_warning"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                
                Spacer()
                
                DatePicker(
                    localizationManager.text("common.move_to"),
                    selection: $batchEventDate,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                
                Button {
                    Task { await applyEventMove(to: batchEventDate, editable: editableSelection) }
                } label: {
                    Label(localizationManager.text("common.move"), systemImage: "arrow.right.circle")
                }
                .buttonStyle(.bordered)
                .disabled(editableSelection.isEmpty)
                
                Button(role: .destructive) {
                    showDeleteEventsConfirmation = true
                } label: {
                    Label(localizationManager.text("common.delete"), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(editableSelection.isEmpty)
            }
            
            if let warning = batchEventWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .alert(localizationManager.format("calendar.delete_events.confirmation", editableSelection.count), isPresented: $showDeleteEventsConfirmation) {
            Button(localizationManager.text("common.delete"), role: .destructive) {
                Task { await applyEventDelete(editable: editableSelection) }
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("calendar.delete_events.read_only_note"))
        }
    }
    
    private func applyEventMove(to date: Date, editable: [EKEvent]) async {
        guard !editable.isEmpty else { return }
        let ids = editable.compactMap { $0.eventIdentifier }
        do {
            try await calendarManager.moveEvents(with: ids, to: date)
            selectedEventIDs.removeAll()
            lastSelectedEventID = nil
            await loadEvents()
        } catch {
            batchEventWarning = localizationManager.format("calendar.error.move_all_failed", error.localizedDescription)
            print("[CalendarView] move events failed: \(error)")
        }
    }
    
    private func applyEventDelete(editable: [EKEvent]) async {
        guard !editable.isEmpty else { return }
        let ids = editable.compactMap { $0.eventIdentifier }
        do {
            try await calendarManager.deleteEvents(with: ids)
            selectedEventIDs.removeAll()
            lastSelectedEventID = nil
            await loadEvents()
        } catch {
            batchEventWarning = localizationManager.format("calendar.error.delete_all_failed", error.localizedDescription)
            print("[CalendarView] delete events failed: \(error)")
        }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Data helpers

    private func events(for day: Date) -> [EKEvent] {
        let calendar = Calendar.current
        return calendarManager.events
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func localEvents(for day: Date) -> [PlanningItem] {
        planningStore.localEvents(on: day)
    }

    private enum DayEventBlock: Identifiable {
        case system(EKEvent)
        case local(PlanningItem)

        var id: String {
            switch self {
            case .system(let event):
                return "system-\(event.eventIdentifier ?? UUID().uuidString)"
            case .local(let item):
                return "local-\(item.id.uuidString)"
            }
        }

        var startDate: Date {
            switch self {
            case .system(let event):
                return event.startDate
            case .local(let item):
                return item.startDate ?? .distantPast
            }
        }
    }

    private func dayEventBlocks(events: [EKEvent], localEvents: [PlanningItem]) -> [DayEventBlock] {
        let blocks = events.map(DayEventBlock.system) + localEvents.map(DayEventBlock.local)
        return blocks.sorted { $0.startDate < $1.startDate }
    }

    private func tasks(for day: Date) -> [TodoItem] {
        let calendar = Calendar.current
        return todoStore.items.filter { item in
            if let due = item.dueDate {
                return calendar.isDate(due, inSameDayAs: day)
            }
            return false
        }
    }

    private func tasksRelevantForTodayReschedule(
        from tasks: [TodoItem],
        calendarEvents: [EKEvent],
        schedulingEnd: Date
    ) -> [TodoItem] {
        let todaysEventIDs = Set(calendarEvents.compactMap(\.eventIdentifier))
        return tasks.filter { item in
            let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return false }

            if let dueDate = item.dueDate, dueDate < schedulingEnd {
                return true
            }

            if let linkedEventID = item.calendarEventIdentifier ?? item.linkedCalendarEventId {
                return todaysEventIDs.contains(linkedEventID)
            }

            return false
        }
    }

    private func rescheduleRequestTasks(from tasks: [TodoItem], schedulingEnd: Date) -> [TodoItem] {
        tasks.map { item in
            var requestItem = item
            // Existing block start times should not act as hard deadlines.
            // We allow spillover into tomorrow when today is genuinely full.
            requestItem.dueDate = schedulingEnd
            requestItem.hasDueTime = true
            return requestItem
        }
    }

    private func immutableCalendarEventsForTodayReschedule(
        allEvents: [EKEvent],
        schedulableTasks: [TodoItem]
    ) -> [EKEvent] {
        let movableEventIDs = Set(
            schedulableTasks.compactMap { $0.calendarEventIdentifier ?? $0.linkedCalendarEventId }
        )
        return allEvents.filter { event in
            if shouldIgnoreForRescheduleBlocking(event) {
                return false
            }
            guard let eventIdentifier = event.eventIdentifier else { return true }
            return !movableEventIDs.contains(eventIdentifier)
        }
    }

    private func shouldIgnoreForRescheduleBlocking(_ event: EKEvent) -> Bool {
        // Holiday / national calendars are often subscribed all-day feeds. They should
        // not consume the entire workday as busy time for AI rescheduling.
        if event.isAllDay && isSubscribedCalendar(event.calendar) {
            return true
        }

        let calendarTitle = event.calendar.title.lowercased()
        let eventTitle = (event.title ?? "").lowercased()
        let holidayHints = ["holiday", "holidays", "national", "public holiday"]
        if event.isAllDay && holidayHints.contains(where: { calendarTitle.contains($0) || eventTitle.contains($0) }) {
            return true
        }

        return false
    }

    private func applyCalendarScheduleReturningResult(
        _ response: AIService.AIScheduleResponse,
        originalTasks: [TodoItem]
    ) throws -> AppliedRescheduleResult {
        guard response.success, !response.schedule.isEmpty else {
            throw AIService.AIServiceError.invalidResponse
        }

        let eventStore = SharedEventStore.shared.eventStore
        let defaultCalendar = eventStore.defaultCalendarForNewEvents
        let originalTasksByID = Dictionary(uniqueKeysWithValues: originalTasks.map { ($0.id, $0) })
        var restoredEvents: [CalendarEventSnapshot] = []
        var restoredEventIDs: Set<String> = []
        var createdEventIDs: [String] = []
        var changedEventIDs: Set<String> = []

        for entry in response.schedule {
            guard let taskID = UUID(uuidString: entry.taskId),
                  let existing = todoStore.items.first(where: { $0.id == taskID }) else {
                continue
            }

            let originalTask = originalTasksByID[taskID] ?? existing
            var updated = existing
            updated.dueDate = entry.start
            updated.hasDueTime = true
            updated.durationMinutes = max(max(1, Preset.shortestBuiltIn.durationConfig.workDuration / 60), Int(entry.end.timeIntervalSince(entry.start) / 60))
            updated.syncToCalendar = entry.calendarWritable
            updated.aiOrigin = .calendarSchedule
            updated.pomodoroPresetID = entry.pomodoroPreset
            updated.plannedPomodoroCount = entry.pomodoros
            updated.modifiedAt = Date()
            todoStore.updateItem(updated)

            guard entry.calendarWritable else {
                print("[CalendarView] Skipping read-only schedule block for task \(entry.taskId)")
                continue
            }

            let existingEventID = originalTask.calendarEventIdentifier ?? originalTask.linkedCalendarEventId
            if let existingEventID,
               let event = eventStore.event(withIdentifier: existingEventID),
               event.calendar.allowsContentModifications {
                let hasChanged = event.title != entry.taskTitle
                    || event.startDate != entry.start
                    || event.endDate != entry.end
                if hasChanged {
                    if restoredEventIDs.insert(existingEventID).inserted {
                        restoredEvents.append(
                            CalendarEventSnapshot(
                                eventIdentifier: existingEventID,
                                title: event.title ?? localizationManager.text("common.untitled"),
                                start: event.startDate,
                                end: event.endDate
                            )
                        )
                    }
                    event.title = entry.taskTitle
                    event.startDate = entry.start
                    event.endDate = entry.end
                    try eventStore.save(event, span: .thisEvent, commit: false)
                    changedEventIDs.insert(existingEventID)
                }

                var linked = updated
                linked.calendarEventIdentifier = existingEventID
                linked.linkedCalendarEventId = existingEventID
                todoStore.updateItem(linked)
                continue
            }

            guard let defaultCalendar else {
                print("[CalendarView] No writable default calendar available for scheduled task \(entry.taskId)")
                continue
            }

            let event = EKEvent(eventStore: eventStore)
            event.title = entry.taskTitle
            event.startDate = entry.start
            event.endDate = entry.end
            event.isAllDay = false
            event.calendar = defaultCalendar

            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                if let savedEventId = event.eventIdentifier {
                    createdEventIDs.append(savedEventId)
                    changedEventIDs.insert(savedEventId)

                    var linked = updated
                    linked.calendarEventIdentifier = savedEventId
                    linked.linkedCalendarEventId = savedEventId
                    todoStore.updateItem(linked)
                }
            } catch {
                print("[CalendarView] Failed to save scheduled event for task \(entry.taskId): \(error)")
            }
        }

        try eventStore.commit()

        calendarManager.updateAIFreeSlots(response.freeSlots)
        Task {
            await loadEvents()
        }

        return AppliedRescheduleResult(
            changedEventIDs: changedEventIDs,
            undoSnapshot: RescheduleUndoSnapshot(
                tasks: originalTasks,
                restoredEvents: restoredEvents,
                createdEventIDs: createdEventIDs
            )
        )
    }

    private func formattedTaskDue(item: TodoItem, due: Date) -> String {
        Self.shortDayFormatter.locale = localizationManager.effectiveLocale
        Self.eventTimeFormatter.locale = localizationManager.effectiveLocale
        let day = Self.shortDayFormatter.string(from: due)
        let suffix = item.hasDueTime ? " • \(Self.eventTimeFormatter.string(from: due))" : ""
        return day + suffix
    }
    
    private func prepareNewEventDefaults() {
        newEventTitle = ""
        newEventNotes = ""
        newEventDurationMinutes = 60
        
        // Align start time to the selected date, keeping the current hour.
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let roundedMinute = minute >= 30 ? 30 : 0
        newEventStart = calendar.date(
            bySettingHour: hour,
            minute: roundedMinute,
            second: 0,
            of: anchorDate
        ) ?? anchorDate
    }
    
    private func saveEvent() async {
        let endDate = newEventStart.addingTimeInterval(Double(newEventDurationMinutes * 60))
        let trimmedTitle = newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            addEventError = localizationManager.text("calendar.event_tasks.title_required")
            return
        }

        _ = planningStore.addLocalEvent(
            title: trimmedTitle,
            notes: newEventNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newEventNotes,
            startDate: newEventStart,
            endDate: endDate
        )
        addEventError = nil
        showingAddEvent = false
    }

    private func formattedLocalEventTime(_ item: PlanningItem) -> String {
        guard let start = item.startDate else {
            return localizationManager.text("calendar.no_due_time")
        }
        Self.eventTimeFormatter.locale = localizationManager.effectiveLocale
        let startText = Self.eventTimeFormatter.string(from: start)
        guard let end = item.endDate else {
            return startText
        }
        let endText = Self.eventTimeFormatter.string(from: end)
        return "\(startText) - \(endText)"
    }

    private var selectedLocalEventBinding: Binding<PlanningItem?> {
        Binding(
            get: {
                guard let selectedLocalEventID else { return nil }
                return planningStore.localEvents.first(where: { $0.id == selectedLocalEventID })
            },
            set: { newValue in
                guard let newValue else {
                    selectedLocalEventID = nil
                    return
                }
                selectedLocalEventID = newValue.id
                planningStore.updateTask(newValue)
            }
        )
    }
}

private struct AddEventSheet: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var durationMinutes: Int
    @Binding var notes: String
    
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text(localizationManager.text("calendar.add_event"))
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField(localizationManager.text("common.title"), text: $title)
                    .textFieldStyle(.roundedBorder)
                
                DatePicker(localizationManager.text("common.start"), selection: $startDate)
                
                HStack {
                    Text(localizationManager.text("common.duration"))
                    Spacer()
                    Stepper(localizationManager.format("common.duration_minutes_format", durationMinutes), value: $durationMinutes, in: 15...480, step: 15)
                }
                
                TextField(localizationManager.text("common.notes_optional"), text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Button(localizationManager.text("common.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button(localizationManager.text("common.save")) {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct RescheduleMatchedGeometry: ViewModifier {
    let eventIdentifier: String?
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if let eventIdentifier {
            content.matchedGeometryEffect(id: eventIdentifier, in: namespace)
        } else {
            content
        }
    }
}

#Preview {
    MainActor.assumeIsolated {
        CalendarView(
            calendarManager: CalendarManager(permissionsManager: .shared),
            permissionsManager: .shared,
            todoStore: TodoStore(),
            planningStore: PlanningStore()
        )
        .frame(width: 700, height: 600)
    }
}

private struct EventTaskDetailSheet: View {
    let eventID: UUID
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject var todoStore: TodoStore
    let onClose: () -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @ObservedObject private var featureGate = FeatureGate.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared

    @State private var manualTaskTitle = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var upgradePaywallContext: SubscriptionPaywallContext?

    private let aiService = AIService.shared

    var body: some View {
        Group {
            if let eventBinding {
                sheetContent(event: eventBinding)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear(perform: onClose)
            }
        }
    }

    private var eventBinding: Binding<PlanningItem>? {
        guard planningStore.localEvents.contains(where: { $0.id == eventID }) else {
            return nil
        }

        return Binding(
            get: {
                planningStore.localEvents.first(where: { $0.id == eventID })
                ?? PlanningItem(
                    id: eventID,
                    title: "",
                    startDate: nil,
                    endDate: nil,
                    isTask: false,
                    isCalendarEvent: true,
                    completed: false,
                    source: .local
                )
            },
            set: { newValue in
                planningStore.updateTask(newValue)
            }
        )
    }

    private func sheetContent(event: Binding<PlanningItem>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.wrappedValue.title)
                        .font(.title3.weight(.semibold))
                    if let start = event.wrappedValue.startDate, let end = event.wrappedValue.endDate {
                        Text("\(formatted(start)) - \(formatted(end))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(localizationManager.text("common.close"), action: onClose)
                    .buttonStyle(.bordered)
            }

            if let notes = event.wrappedValue.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Toggle(localizationManager.text("calendar.event_tasks.enable_toggle"), isOn: taskModeBinding(for: event))

            if event.wrappedValue.hasTaskMode {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(localizationManager.text("calendar.event_tasks.section_title"))
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await generateTasks(event: event) }
                        } label: {
                            if isGenerating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(localizationManager.text("calendar.event_tasks.generate_ai"))
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGenerating)
                    }

                    if canInteractWithEventTasks {
                        HStack(spacing: 8) {
                            TextField(localizationManager.text("calendar.event_tasks.add_placeholder"), text: $manualTaskTitle)
                                .textFieldStyle(.roundedBorder)
                            Button(localizationManager.text("calendar.event_tasks.add_button")) {
                                Task { await addManualTask(event: event) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        lockedEventTasksView
                    }

                    if event.wrappedValue.eventTasks.isEmpty {
                        Text(localizationManager.text("calendar.event_tasks.empty_state"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(event.wrappedValue.eventTasks) { task in
                                HStack(spacing: 10) {
                                    Button {
                                        planningStore.toggleEventTaskCompletion(eventID: eventID, taskID: task.id)
                                    } label: {
                                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(task.isCompleted ? Color.accentColor : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!canInteractWithEventTasks)

                                    VStack(alignment: .leading, spacing: 3) {
                                        TextField(
                                            "",
                                            text: taskTitleBinding(for: task),
                                            prompt: Text(localizationManager.text("calendar.event_tasks.add_placeholder"))
                                        )
                                            .textFieldStyle(.plain)
                                            .strikethrough(task.isCompleted)
                                            .disabled(!canInteractWithEventTasks)
                                            .onSubmit {
                                                planningStore.updateEventTaskTitle(
                                                    eventID: eventID,
                                                    taskID: task.id,
                                                    title: taskTitleBinding(for: task).wrappedValue
                                                )
                                            }
                                        Text(task.source == .ai
                                             ? localizationManager.text("calendar.event_tasks.source_ai")
                                             : localizationManager.text("calendar.event_tasks.source_manual"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Button(localizationManager.text("calendar.event_tasks.convert_to_task")) {
                                        let todo = TodoItem(
                                            title: task.title,
                                            descriptionMarkdown: event.wrappedValue.notes,
                                            dueDate: event.wrappedValue.startDate,
                                            hasDueTime: true,
                                            syncToCalendar: false
                                        )
                                        todoStore.addItem(todo)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .onDelete { offsets in
                                let tasks = event.wrappedValue.eventTasks
                                for index in offsets {
                                    planningStore.deleteEventTask(eventID: eventID, taskID: tasks[index].id)
                                }
                            }
                        }
                        .frame(minHeight: 180, maxHeight: 260)
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .sheet(item: $upgradePaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: subscriptionStore
            )
        }
    }

    private var canInteractWithEventTasks: Bool {
        featureGate.canUseEventTasks
    }

    private func taskModeBinding(for event: Binding<PlanningItem>) -> Binding<Bool> {
        Binding(
            get: { event.wrappedValue.hasTaskMode },
            set: { isEnabled in
                errorMessage = nil
                if isEnabled && !featureGate.canUseEventTasks {
                    presentUpgrade(requiredTier: .plus, messageKey: "calendar.event_tasks.plus_required")
                    return
                }
                planningStore.setEventTaskMode(for: eventID, enabled: isEnabled)
            }
        )
    }

    @ViewBuilder
    private var lockedEventTasksView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizationManager.text("calendar.event_tasks.plus_required"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(localizationManager.text("tasks.ai_assistant.upgrade")) {
                presentUpgrade(requiredTier: .plus, messageKey: "calendar.event_tasks.plus_required")
            }
            .buttonStyle(.bordered)
        }
    }

    private func generateTasks(event: Binding<PlanningItem>) async {
        errorMessage = nil

        guard authViewModel.isAuthenticated else {
            errorMessage = localizationManager.text("calendar.event_tasks.ai_requires_login")
            return
        }

        guard featureGate.canUseAIEventTasks else {
            presentUpgrade(requiredTier: .pro, messageKey: "calendar.event_tasks.ai_requires_pro")
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let response = try await aiService.generateEventTasks(
                eventTitle: event.wrappedValue.title,
                description: event.wrappedValue.notes
            )
            let tasks = response.tasks.map { PlanningItem.EventTask(title: $0, source: .ai) }
            planningStore.replaceEventTasks(eventID: eventID, tasks: tasks)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addManualTask(event: Binding<PlanningItem>) async {
        errorMessage = nil
        guard canInteractWithEventTasks else {
            presentUpgrade(requiredTier: .plus, messageKey: "calendar.event_tasks.plus_required")
            return
        }
        let trimmed = manualTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        planningStore.addEventTask(to: eventID, title: trimmed, source: .manual)
        manualTaskTitle = ""
    }

    private func presentUpgrade(requiredTier: PlanTier, messageKey: String) {
        upgradePaywallContext = SubscriptionPaywallContext(
            requiredTier: requiredTier,
            title: localizationManager.text("calendar.event_tasks.section_title"),
            message: localizationManager.text(messageKey)
        )
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = localizationManager.effectiveLocale
        return formatter.string(from: date)
    }

    private func taskTitleBinding(for task: PlanningItem.EventTask) -> Binding<String> {
        Binding(
            get: {
                planningStore.localEvents
                    .first(where: { $0.id == eventID })?
                    .eventTasks
                    .first(where: { $0.id == task.id })?
                    .title ?? task.title
            },
            set: { newValue in
                planningStore.updateEventTaskTitle(eventID: eventID, taskID: task.id, title: newValue)
            }
        )
    }
}

import SwiftUI
import EventKit
import AppKit
import FirebaseAuth
import FirebaseFunctions

/// Calendar view showing local planning items and optional EventKit events.
@MainActor
struct CalendarView: View {
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject var goalStore: GoalStore
    @ObservedObject var noteStore: NoteStore
    @ObservedObject var locationStore: LocationStore
    @ObservedObject var calendarAutoSync: CalendarAutoSync
    @ObservedObject private var featureGate = FeatureGate.shared
    @ObservedObject private var googleIntegrationManager = GoogleIntegrationManager.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Namespace private var rescheduleAnimationNamespace
    @AppStorage(DeveloperDemoMode.googleVideoDemoModeKey) private var googleVideoDemoMode = false
    @AppStorage("googleCalendarPausedBannerDismissed") private var isGoogleCalendarPausedBannerDismissed = false
    
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
    @State private var newEventLocationID: UUID?
    @State private var addEventError: String?
    @State private var showAIAssistant = false
    @State private var isRunningAIAssistant = false
    @State private var aiAssistantErrorMessage: String?
    @State private var isRescheduling = false
    @State private var rescheduleError: String?
    @State private var showAILoginSheet = false
    @State private var upgradePaywallContext: SubscriptionPaywallContext?
    @State private var locationPickerContext: CalendarLocationPickerContext?
    @State private var selectedLocalEventID: UUID?
    @State private var selectedTaskDetailID: UUID?
    @State private var pendingMoveAction: PendingCalendarMove?
    @State private var moveTargetDate: Date = Date()
    @State private var pendingDeleteAction: PendingCalendarDelete?

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

    private struct PendingCalendarMove: Identifiable {
        enum Kind {
            case systemEvent(String)
            case localEvent(UUID)
            case task(UUID)
        }

        let id = UUID()
        let title: String
        let kind: Kind
    }

    private struct PendingCalendarDelete: Identifiable {
        enum Kind {
            case systemEvent(String)
            case localEvent(UUID)
        }

        let id = UUID()
        let title: String
        let kind: Kind
    }

    private struct CalendarLocationPickerContext: Identifiable {
        enum Kind {
            case systemEvent(String)
            case localEvent(UUID)
            case task(UUID)
        }

        let id = UUID()
        let kind: Kind
        let currentLocationID: UUID?
        let title: String
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
            calendarContent
        }
        .frame(minWidth: 520, idealWidth: 680, maxWidth: 900, minHeight: 520, alignment: .top)
        .onAppear {
            permissionsManager.refreshCalendarStatus()
            calendarAutoSync.setVisibleRefreshHandler {
                await loadEvents()
            }
            Task {
                await loadEvents()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarGoToToday)) { _ in
            selectedView = .day
            anchorDate = Date()
            calendarAutoSync.visibleRangeDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .calendarFocusItem)) { notification in
            focusCalendarItem(from: notification)
        }
        .onChange(of: googleVideoDemoMode) { _, _ in
            selectedEventIDs.removeAll()
            selectedLocalEventID = nil
            selectedTaskDetailID = nil
            Task {
                await loadEvents()
            }
        }
        .sheet(isPresented: $showingAddEvent) {
            AddEventSheet(
                locationStore: locationStore,
                title: $newEventTitle,
                startDate: $newEventStart,
                durationMinutes: $newEventDurationMinutes,
                notes: $newEventNotes,
                locationID: $newEventLocationID,
                canUseLocationNotifications: canUseLocationTagsAndNotifications,
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
        .sheet(item: $locationPickerContext) { context in
            WorkLocationPickerSheet(
                locationStore: locationStore,
                title: context.title,
                canCreateNewLocation: canCreateLocation(for: context),
                canUseLocationNotifications: canUseLocationTagsAndNotifications,
                notificationTaskCount: locationNotificationCount(for: context.currentLocationID),
                onCreateLimitReached: {
                    locationPickerContext = nil
                    presentCalendarTaskLocationLimitPaywall()
                },
                onCancel: {
                    locationPickerContext = nil
                },
                onSelect: { locationID in
                    assignPickedLocation(locationID, for: context)
                    locationPickerContext = nil
                }
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
        .sheet(isPresented: Binding(
            get: { selectedTaskDetailID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedTaskDetailID = nil
                }
            }
        )) {
            if let selectedTaskDetailID,
               let task = displayedTodoItems.first(where: { $0.id == selectedTaskDetailID }) {
                CalendarTaskDetailSheet(task: task) {
                    self.selectedTaskDetailID = nil
                }
                .environmentObject(localizationManager)
            }
        }
        .sheet(item: $pendingMoveAction) { action in
            CalendarMoveSheet(
                title: action.title,
                targetDate: $moveTargetDate,
                onCancel: { pendingMoveAction = nil },
                onMove: {
                    Task { await confirmPendingMove(action) }
                }
            )
            .environmentObject(localizationManager)
        }
        .alert(item: $pendingDeleteAction) { action in
            Alert(
                title: Text(localizationManager.format("calendar.delete_item.confirmation", action.title)),
                message: Text(localizationManager.text("common.cannot_undo")),
                primaryButton: .destructive(Text(localizationManager.text("common.delete"))) {
                    Task { await confirmPendingDelete(action) }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView(
                tasks: displayedPendingTodoItems,
                availableActions: [.breakdown, .planning, .reschedule],
                isLoading: isRunningAIAssistant || isRescheduling,
                errorMessage: rescheduleError ?? aiAssistantErrorMessage,
                isActionEnabled: { action in
                    featureGate.canUseAIAssistantAction(action)
                    && !(action == .reschedule && isRescheduling)
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

    private func focusCalendarItem(from notification: Notification) {
        selectedView = .day

        if let date = notification.userInfo?["date"] as? Date {
            anchorDate = date
        }

        selectedEventIDs.removeAll()
        selectedLocalEventID = nil
        selectedTaskDetailID = nil

        if let localEventIDString = notification.userInfo?["localEventID"] as? String,
           let localEventID = UUID(uuidString: localEventIDString) {
            selectedLocalEventID = localEventID
            if notification.userInfo?["date"] == nil,
               let event = planningStore.localEvents.first(where: { $0.id == localEventID }),
               let startDate = event.startDate {
                anchorDate = startDate
            }
        } else if let systemEventID = notification.userInfo?["systemEventID"] as? String {
            selectedEventIDs = [systemEventID]
            lastSelectedEventID = systemEventID
        } else if let taskIDString = notification.userInfo?["taskID"] as? String,
                  let taskID = UUID(uuidString: taskIDString) {
            selectedTaskDetailID = taskID
            if notification.userInfo?["date"] == nil,
               let task = todoStore.items.first(where: { $0.id == taskID }),
               let dueDate = task.dueDate {
                anchorDate = dueDate
            }
        }

        calendarAutoSync.visibleRangeDidChange()
    }
    
    private var calendarContent: some View {
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

                    calendarToolbar

                    calendarSyncPanel

                    if selectedEventIDs.count > 1 {
                        batchEventActionsBar
                    }

                    if googleIntegrationManager.isAnyGoogleServiceConnected && !isGoogleCalendarPausedBannerDismissed {
                        googleCalendarPausedBanner
                    } else if !permissionsManager.isCalendarAuthorized {
                        calendarPermissionBanner
                    }
                }

                // Events list constrained to the available detail height
                GeometryReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
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
    
    private var calendarPermissionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizationManager.text("calendar.permission_off.title"))
                    .font(.subheadline.weight(.semibold))
                Text(calendarPermissionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: {
                Task {
                    await permissionsManager.requestCalendarPermission()
                    await loadEvents()
                }
            }) {
                Label(localizationManager.text("calendar.request_access"), systemImage: "calendar")
            }
            .buttonStyle(.bordered)

            if permissionsManager.calendarStatus == .denied || permissionsManager.calendarStatus == .restricted {
                Button(localizationManager.text("common.open_settings")) {
                    permissionsManager.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        }
        .alert(localizationManager.text("calendar.access_denied.title"), isPresented: $permissionsManager.showCalendarDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("calendar.access_denied.body"))
        }
    }

    private var googleCalendarPausedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizationManager.text("calendar.apple_sync_paused.title"))
                    .font(.subheadline.weight(.semibold))
                Text(localizationManager.text("calendar.apple_sync_paused.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                isGoogleCalendarPausedBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.blue.opacity(0.20), lineWidth: 1)
        }
    }

    private var calendarPermissionMessage: String {
        if permissionsManager.calendarStatus == .denied || permissionsManager.calendarStatus == .restricted {
            return localizationManager.text("calendar.permission_off.denied_body")
        }
        return localizationManager.text("calendar.permission_off.body")
    }

    private var calendarToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                calendarViewControls

                if !googleIntegrationManager.isAnyGoogleServiceConnected && !permissionsManager.isCalendarAuthorized {
                    calendarPermissionOffBadge
                }

                Spacer(minLength: 16)

                calendarPrimaryActions
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    calendarViewControls

                    if !googleIntegrationManager.isAnyGoogleServiceConnected && !permissionsManager.isCalendarAuthorized {
                        calendarPermissionOffBadge
                    }
                }

                calendarPrimaryActions
            }
        }
    }

    private var calendarViewControls: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(localizationManager.text("calendar.view"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, alignment: .trailing)

            Picker("", selection: $selectedView) {
                Text(localizationManager.text("calendar.view.day")).tag(ViewType.day)
                Text(localizationManager.text("calendar.view.week")).tag(ViewType.week)
                Text(localizationManager.text("calendar.view.month")).tag(ViewType.month)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 204)
            .onChange(of: selectedView) { _, _ in
                calendarAutoSync.visibleRangeDidChange()
            }

            DatePicker(
                "",
                selection: $anchorDate,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(width: 148)
            .onChange(of: anchorDate) { _, _ in
                calendarAutoSync.visibleRangeDidChange()
            }
        }
    }

    private var calendarPermissionOffBadge: some View {
        Text(localizationManager.text("calendar.permission_off.badge"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }

    private var calendarPrimaryActions: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                prepareNewEventDefaults()
                showingAddEvent = true
            } label: {
                Label(localizationManager.text("calendar.add_event"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help(localizationManager.text("calendar.add_event"))

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
                Task { await performToolbarSync() }
            } label: {
                if activeCalendarSyncInProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(localizationManager.text("calendar.sync"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!canUseToolbarSync)
        }
    }

    private var calendarSyncPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if googleIntegrationManager.isAnyGoogleServiceConnected {
                if googleIntegrationManager.isSyncing {
                    Label(localizationManager.text("calendar.google_sync.in_progress"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = googleIntegrationManager.lastSyncError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let lastSyncDate = googleIntegrationManager.lastSyncDate {
                    Label(localizationManager.format("calendar.google_sync.last_synced", lastSyncDate.formatted(date: .omitted, time: .shortened)), systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                if calendarAutoSync.isSyncing {
                    Label(localizationManager.text("calendar.apple_sync.in_progress"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = calendarAutoSync.lastSyncError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let lastSyncDate = calendarAutoSync.lastSyncDate {
                    Label(localizationManager.format("calendar.apple_sync.last_synced", lastSyncDate.formatted(date: .omitted, time: .shortened)), systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizationManager.text("calendar.auto_sync.title"))
                        .font(.subheadline.weight(.medium))
                    Text(googleIntegrationManager.isAnyGoogleServiceConnected ? localizationManager.text("calendar.auto_sync.google_description") : localizationManager.text("calendar.auto_sync.apple_description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if googleIntegrationManager.isAnyGoogleServiceConnected {
                    Toggle(localizationManager.text("calendar.auto_sync.title"), isOn: $googleIntegrationManager.isAutoSyncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel(localizationManager.text("calendar.auto_sync.google_label"))
                        .accessibilityHint(localizationManager.text("calendar.auto_sync.google_description"))
                } else {
                    Toggle(localizationManager.text("calendar.auto_sync.title"), isOn: $calendarAutoSync.isAutoSyncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityLabel(localizationManager.text("calendar.auto_sync.apple_label"))
                        .accessibilityHint(localizationManager.text("calendar.auto_sync.apple_description"))
                        .disabled(!permissionsManager.isCalendarAuthorized)
                }
            }
        }
    }

    private var activeCalendarSyncInProgress: Bool {
        googleIntegrationManager.isAnyGoogleServiceConnected ? googleIntegrationManager.isSyncing : calendarAutoSync.isSyncing
    }

    private var activeCalendarLoading: Bool {
        googleIntegrationManager.isCalendarConnected ? false : calendarManager.isLoading
    }

    private var canUseToolbarSync: Bool {
        if googleIntegrationManager.isAnyGoogleServiceConnected {
            return !googleIntegrationManager.isSyncing
        }
        return permissionsManager.isCalendarAuthorized && !calendarAutoSync.isSyncing
    }

    private func performToolbarSync() async {
        if googleIntegrationManager.isAnyGoogleServiceConnected {
            await googleIntegrationManager.syncNow()
            await loadEvents()
            return
        }

        permissionsManager.refreshCalendarStatus()
        await calendarAutoSync.syncNow(refreshVisibleEvents: true)
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
    private func eventsContent(maxWidth: CGFloat) -> some View {        if activeCalendarLoading {
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
                    events: displayedCalendarEvents,
                    localEvents: displayedLocalEvents,
                    tasks: displayedTodoItems,
                    onSelectLocalEvent: { event in
                        if planningStore.localEvents.contains(where: { $0.id == event.id }) {
                            selectedLocalEventID = event.id
                        }
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
            events: displayedCalendarEvents,
            localEvents: displayedLocalEvents,
            onSelectLocalEvent: { event in
                if planningStore.localEvents.contains(where: { $0.id == event.id }) {
                    selectedLocalEventID = event.id
                }
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
                aiAssistantErrorMessage = AIService.userFacingErrorMessage(error)
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
        let canSyncCalendar = permissionsManager.isCalendarAuthorized && !googleIntegrationManager.isAnyGoogleServiceConnected

        for entry in response.schedule {
            guard let taskID = UUID(uuidString: entry.taskId),
                  let existing = todoStore.items.first(where: { $0.id == taskID }) else {
                continue
            }

            var updated = existing
            updated.dueDate = entry.start
            updated.hasDueTime = true
            updated.durationMinutes = max(max(1, Preset.shortestBuiltIn.durationConfig.workDuration / 60), Int(entry.end.timeIntervalSince(entry.start) / 60))
            updated.syncToCalendar = canSyncCalendar && entry.calendarWritable
            updated.aiOrigin = .calendarSchedule
            updated.pomodoroPresetID = entry.pomodoroPreset
            updated.plannedPomodoroCount = entry.pomodoros
            updated.modifiedAt = Date()
            todoStore.updateItem(updated)

            guard canSyncCalendar else {
                ClientLog.debug("[CalendarView] Calendar access is off; scheduled task locally only")
                continue
            }

            guard entry.calendarWritable else {
                ClientLog.debug("[CalendarView] Skipping read-only schedule block")
                continue
            }

            guard let defaultCalendar else {
                ClientLog.debug("[CalendarView] No writable default calendar available")
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
                ClientLog.debugError("[CalendarView] Failed to save scheduled event", error)
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

    private func createNote(for event: EKEvent) {
        guard canCreateAnotherNote else {
            presentNotesPaywall()
            return
        }
        guard let snapshot = planningStore.upsertCalendarEventSnapshot(event) else { return }
        createNote(for: snapshot)
    }

    private func createNote(for item: PlanningItem) {
        guard canCreateAnotherNote else {
            presentNotesPaywall()
            return
        }
        let note = noteStore.addNote(
            title: localizationManager.format("workspace.notes.linked_title", item.title),
            source: .event,
            linkedEventID: item.id
        )
        openNote(note)
    }

    private func createNote(for item: TodoItem) {
        guard canCreateAnotherNote else {
            presentNotesPaywall()
            return
        }
        let note = noteStore.addNote(
            title: localizationManager.format("workspace.notes.linked_title", item.title),
            source: .task,
            linkedTaskID: item.id
        )
        openNote(note)
    }

    private var canCreateAnotherNote: Bool {
        featureGate.canCreateUnlimitedNotes
            || noteStore.notes.lazy.filter { !$0.isArchived }.count < 10
    }

    private func presentNotesPaywall() {
        presentUpgradePaywall(
            requiredTier: .plus,
            title: localizationManager.text("workspace.notes.limit.title"),
            message: localizationManager.text("workspace.notes.limit.message")
        )
    }

    private func openNote(_ note: NoteRecord) {
        NotificationCenter.default.post(name: .navigateToThinkingNotes, object: nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .workspaceNoteFocusItem,
                object: nil,
                userInfo: ["noteID": note.id.uuidString]
            )
        }
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
        ClientLog.debug("[CalendarView] Reschedule requested")
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

        let calendarEvents = permissionsManager.isCalendarAuthorized && !googleIntegrationManager.isAnyGoogleServiceConnected
            ? calendarManager.readEvents(from: schedulingStart, to: schedulingRangeEnd)
            : []
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
            ClientLog.debug("[CalendarView] Sending reschedule request")
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
            ClientLog.debugError("[CalendarView] Reschedule request failed", error)
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain,
               nsError.code == FunctionsErrorCode.deadlineExceeded.rawValue {
                rescheduleError = "Scheduling request timed out. Please try again."
            } else {
                rescheduleError = AIService.userFacingErrorMessage(error)
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
        if googleIntegrationManager.isCalendarConnected {
            return
        }

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

        return ScrollView(.vertical, showsIndicators: false) {
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
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 6) {
                    Text(event.title ?? localizationManager.text("common.untitled"))
                        .font(.headline)
                    if isRescheduled {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                systemEventMenu(for: event)
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

    private func planningEvent(for event: EKEvent) -> PlanningItem? {
        guard let identifier = event.eventIdentifier else { return nil }
        return planningStore.items.first {
            $0.isCalendarEvent && $0.calendarEventIdentifier == identifier
        }
    }

    private func taskCard(_ item: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
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
            .frame(maxWidth: .infinity, alignment: .leading)

            calendarTaskMenu(for: item)
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
        HStack(alignment: .top, spacing: 10) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            localEventMenu(for: item)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06))
        .cornerRadius(8)
    }

    private func systemEventMenu(for event: EKEvent) -> some View {
        Menu {
            Button {
                openSystemEventDetails(event)
            } label: {
                Label(localizationManager.text("common.open_details"), systemImage: "info.circle")
            }

            Button {
                createTask(from: event)
            } label: {
                Label(localizationManager.text("calendar.action.create_task_from_event"), systemImage: "checklist")
            }

            Button {
                createNote(for: event)
            } label: {
                Label(localizationManager.text("workspace.notes.add"), systemImage: "note.text.badge.plus")
            }

            systemGoalLinkMenu(for: event)
            systemEventLocationMenu(for: event)

            Button {
                if let item = calendarSnapshot(for: event) {
                    enableEventTasks(for: item)
                }
            } label: {
                Label(localizationManager.text("calendar.event_tasks.enable_toggle"), systemImage: "checklist.checked")
            }

            Button {
                beginMoveSystemEvent(event)
            } label: {
                Label(localizationManager.text("common.move"), systemImage: "calendar.badge.clock")
            }
            .disabled(!canModify(event))

            Button(role: .destructive) {
                beginDeleteSystemEvent(event)
            } label: {
                Label(localizationManager.text("common.delete"), systemImage: "trash")
            }
            .disabled(!canModify(event))
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func localEventMenu(for item: PlanningItem) -> some View {
        Menu {
            Button {
                selectedLocalEventID = item.id
            } label: {
                Label(localizationManager.text("common.open_details"), systemImage: "info.circle")
            }

            Button {
                createTask(from: item)
            } label: {
                Label(localizationManager.text("calendar.action.create_task_from_event"), systemImage: "checklist")
            }

            Button {
                createNote(for: item)
            } label: {
                Label(localizationManager.text("workspace.notes.add"), systemImage: "note.text.badge.plus")
            }

            goalLinkMenu(for: item)
            eventLocationMenu(for: item)

            Button {
                enableEventTasks(for: item)
            } label: {
                Label(localizationManager.text("calendar.event_tasks.enable_toggle"), systemImage: "checklist.checked")
            }

            Button {
                beginMoveLocalEvent(item)
            } label: {
                Label(localizationManager.text("common.move"), systemImage: "calendar.badge.clock")
            }

            Button {
                duplicateLocalEvent(item)
            } label: {
                Label(localizationManager.text("common.duplicate"), systemImage: "plus.square.on.square")
            }
            .disabled(item.source != .local)

            Button(role: .destructive) {
                beginDeleteLocalEvent(item)
            } label: {
                Label(localizationManager.text("common.delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func calendarTaskMenu(for item: TodoItem) -> some View {
        Menu {
            Button {
                selectedTaskDetailID = item.id
            } label: {
                Label(localizationManager.text("common.open_details"), systemImage: "info.circle")
            }

            Button {
                createNote(for: item)
            } label: {
                Label(localizationManager.text("workspace.notes.add"), systemImage: "note.text.badge.plus")
            }

            taskGoalLinkMenu(for: item)
            calendarTaskLocationMenu(for: item)

            Button {
                beginMoveTask(item)
            } label: {
                Label(localizationManager.text("common.move"), systemImage: "calendar.badge.clock")
            }

            Button {
                createLocalEvent(from: item)
            } label: {
                Label(localizationManager.text("calendar.action.create_event_from_task"), systemImage: "calendar.badge.plus")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func goalLinkMenu(for item: PlanningItem?) -> some View {
        if let item, !goalStore.goals.isEmpty {
            Menu {
                ForEach(goalStore.goals) { goal in
                    Button(goal.outcome) {
                        _ = goalStore.addLink(goalID: goal.id, kind: .event, targetID: item.id.uuidString)
                    }
                    .disabled(goalStore.hasLink(goalID: goal.id, kind: .event, targetID: item.id.uuidString))
                }
            } label: {
                Label(localizationManager.text("workspace.action.link_to_goal"), systemImage: "target")
            }
        } else {
            Button {
            } label: {
                Label(localizationManager.text("workspace.action.link_to_goal"), systemImage: "target")
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    private func systemGoalLinkMenu(for event: EKEvent) -> some View {
        if !goalStore.goals.isEmpty {
            Menu {
                ForEach(goalStore.goals) { goal in
                    Button(goal.outcome) {
                        guard let item = calendarSnapshot(for: event) else { return }
                        _ = goalStore.addLink(goalID: goal.id, kind: .event, targetID: item.id.uuidString)
                    }
                    .disabled(isSystemEventLinked(event, to: goal))
                }
            } label: {
                Label(localizationManager.text("workspace.action.link_to_goal"), systemImage: "target")
            }
        } else {
            Button {
            } label: {
                Label(localizationManager.text("workspace.action.link_to_goal"), systemImage: "target")
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    private func taskGoalLinkMenu(for item: TodoItem) -> some View {
        if !goalStore.goals.isEmpty {
            Menu {
                ForEach(goalStore.goals) { goal in
                    Button(goal.outcome) {
                        _ = goalStore.addLink(goalID: goal.id, kind: .task, targetID: item.id.uuidString)
                    }
                    .disabled(goalStore.hasLink(goalID: goal.id, kind: .task, targetID: item.id.uuidString))
                }
            } label: {
                Label(localizationManager.text("workspace.action.link_to_goal"), systemImage: "target")
            }
        } else {
            Button {
            } label: {
                Label(localizationManager.text("workspace.action.link_to_goal"), systemImage: "target")
            }
            .disabled(true)
        }
    }

    @ViewBuilder
    private func systemEventLocationMenu(for event: EKEvent) -> some View {
        let snapshot = event.eventIdentifier.flatMap { identifier in
            planningStore.items.first { $0.calendarEventIdentifier == identifier }
        }
        locationMenu(
            currentLocationID: snapshot?.locationID,
            assignTitle: snapshot?.locationID == nil ? localizationManager.text("workspace.location.pin") : localizationManager.text("workspace.location.change"),
            onPickLocation: {
                guard let identifier = event.eventIdentifier else { return }
                locationPickerContext = CalendarLocationPickerContext(
                    kind: .systemEvent(identifier),
                    currentLocationID: snapshot?.locationID,
                    title: snapshot?.locationID == nil ? localizationManager.text("workspace.location.pin") : localizationManager.text("workspace.location.change")
                )
            },
            onClear: {
                guard let item = calendarSnapshot(for: event) else { return }
                planningStore.setLocation(itemID: item.id, locationID: nil)
            }
        )
    }

    @ViewBuilder
    private func eventLocationMenu(for item: PlanningItem) -> some View {
        locationMenu(
            currentLocationID: item.locationID,
            assignTitle: item.locationID == nil ? localizationManager.text("workspace.location.pin") : localizationManager.text("workspace.location.change"),
            onPickLocation: {
                locationPickerContext = CalendarLocationPickerContext(
                    kind: .localEvent(item.id),
                    currentLocationID: item.locationID,
                    title: item.locationID == nil ? localizationManager.text("workspace.location.pin") : localizationManager.text("workspace.location.change")
                )
            },
            onClear: {
                planningStore.setLocation(itemID: item.id, locationID: nil)
            }
        )
    }

    @ViewBuilder
    private func calendarTaskLocationMenu(for item: TodoItem) -> some View {
        locationMenu(
            currentLocationID: item.locationID,
            assignTitle: item.locationID == nil ? localizationManager.text("workspace.location.pin") : localizationManager.text("workspace.location.change"),
            onPickLocation: {
                locationPickerContext = CalendarLocationPickerContext(
                    kind: .task(item.id),
                    currentLocationID: item.locationID,
                    title: item.locationID == nil ? localizationManager.text("workspace.location.pin") : localizationManager.text("workspace.location.change")
                )
            },
            onClear: {
                todoStore.setLocation(itemID: item.id, locationID: nil)
            }
        )
    }

    @ViewBuilder
    private func locationMenu(
        currentLocationID: UUID?,
        assignTitle: String,
        onPickLocation: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        Menu {
            Button {
                onPickLocation()
            } label: {
                Label(assignTitle, systemImage: "mappin.and.ellipse")
            }

            Button {
                onClear()
            } label: {
                Label(localizationManager.text("workspace.location.clear"), systemImage: "mappin.slash")
            }
            .disabled(currentLocationID == nil)

            Button {
                NotificationCenter.default.post(name: .navigateToWorkspaceMap, object: currentLocationID)
            } label: {
                Label(localizationManager.text("workspace.location.show_on_map"), systemImage: "map")
            }
            .disabled(currentLocationID == nil)
        } label: {
            Label(localizationManager.text("common.location"), systemImage: "location")
        }
    }

    private func assignTaskLocation(_ locationID: UUID, to item: TodoItem) {
        if item.locationID == nil,
           !canUseUnlimitedTaskLocations,
           todoStore.items.filter({ $0.locationID != nil }).count >= LocationStore.freeTaskLocationLimit {
            presentCalendarTaskLocationLimitPaywall()
            return
        }
        todoStore.setLocation(itemID: item.id, locationID: locationID)
    }

    private func assignPickedLocation(_ locationID: UUID, for context: CalendarLocationPickerContext) {
        switch context.kind {
        case .systemEvent(let identifier):
            guard let event = calendarManager.events.first(where: { $0.eventIdentifier == identifier }),
                  let item = calendarSnapshot(for: event) else { return }
            planningStore.setLocation(itemID: item.id, locationID: locationID)
        case .localEvent(let id):
            planningStore.setLocation(itemID: id, locationID: locationID)
        case .task(let id):
            guard let item = todoStore.items.first(where: { $0.id == id }) else { return }
            assignTaskLocation(locationID, to: item)
        }
    }

    private func canCreateLocation(for context: CalendarLocationPickerContext) -> Bool {
        switch context.kind {
        case .task(let id):
            guard let item = todoStore.items.first(where: { $0.id == id }) else { return false }
            return item.locationID != nil
                || canUseUnlimitedTaskLocations
                || todoStore.items.filter({ $0.locationID != nil }).count < LocationStore.freeTaskLocationLimit
        case .systemEvent, .localEvent:
            return true
        }
    }

    private func presentCalendarTaskLocationLimitPaywall() {
        presentUpgradePaywall(
            requiredTier: .plus,
            title: localizationManager.text("location.paywall.unlimited_task_locations_title"),
            message: localizationManager.format("location.paywall.unlimited_task_locations_message", LocationStore.freeTaskLocationLimit)
        )
    }

    private func locationNotificationCount(for locationID: UUID?) -> Int {
        guard let locationID else { return 1 }
        return max(1, todoStore.items.filter { $0.locationID == locationID && !$0.isCompleted }.count)
    }

    private var canUseUnlimitedTaskLocations: Bool {
        switch featureGate.tier {
        case .plus, .pro, .developer:
            return true
        case .free, .beta, .expired:
            return false
        }
    }

    private var canUseLocationTagsAndNotifications: Bool {
        switch featureGate.tier {
        case .plus, .pro, .developer:
            return true
        case .free, .beta, .expired:
            return false
        }
    }

    private func calendarSnapshot(for event: EKEvent) -> PlanningItem? {
        planningStore.upsertCalendarEventSnapshot(event)
    }

    private func isSystemEventLinked(_ event: EKEvent, to goal: GoalRecord) -> Bool {
        guard let item = planningEvent(for: event) else { return false }
        return goalStore.hasLink(goalID: goal.id, kind: .event, targetID: item.id.uuidString)
    }

    private func canModify(_ event: EKEvent) -> Bool {
        event.calendar?.allowsContentModifications == true
    }

    private func openSystemEventDetails(_ event: EKEvent) {
        guard let item = calendarSnapshot(for: event) else { return }
        selectedLocalEventID = item.id
    }

    private func createTask(from event: EKEvent) {
        let duration = max(15, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
        let task = TodoItem(
            title: event.title ?? localizationManager.text("common.untitled"),
            descriptionMarkdown: event.notes,
            dueDate: event.startDate,
            hasDueTime: !event.isAllDay,
            durationMinutes: duration,
            syncToCalendar: false
        )
        todoStore.addItem(task)
    }

    private func createTask(from item: PlanningItem) {
        let start = item.startDate
        let duration = max(15, Int((item.endDate ?? start ?? Date()).timeIntervalSince(start ?? Date()) / 60))
        let task = TodoItem(
            title: item.title,
            descriptionMarkdown: item.notes,
            dueDate: start,
            hasDueTime: start != nil,
            durationMinutes: duration,
            syncToCalendar: false
        )
        todoStore.addItem(task)
    }

    private func createLocalEvent(from task: TodoItem) {
        guard let start = task.dueDate else { return }
        let duration = task.durationMinutes ?? 30
        let item = planningStore.addLocalEvent(
            title: task.title,
            notes: task.notes,
            startDate: start,
            endDate: start.addingTimeInterval(Double(duration * 60))
        )
        Task {
            await googleIntegrationManager.syncLocalCalendarEvent(item, planningStore: planningStore)
        }
    }

    private func enableEventTasks(for item: PlanningItem) {
        guard featureGate.canUseEventTasks else {
            presentLockedFeatureInfo(
                featureName: localizationManager.text("calendar.event_tasks.section_title"),
                description: localizationManager.text("calendar.event_tasks.plus_required"),
                requiredTier: .plus
            )
            return
        }
        planningStore.setEventTaskMode(for: item.id, enabled: true)
        selectedLocalEventID = item.id
    }

    private func duplicateLocalEvent(_ item: PlanningItem) {
        guard let duplicate = planningStore.duplicateLocalEvent(item) else { return }
        Task {
            await googleIntegrationManager.syncLocalCalendarEvent(duplicate, planningStore: planningStore)
        }
    }

    private func beginMoveSystemEvent(_ event: EKEvent) {
        guard let identifier = event.eventIdentifier else { return }
        moveTargetDate = event.startDate
        pendingMoveAction = PendingCalendarMove(
            title: event.title ?? localizationManager.text("common.untitled"),
            kind: .systemEvent(identifier)
        )
    }

    private func beginMoveLocalEvent(_ item: PlanningItem) {
        moveTargetDate = item.startDate ?? Date()
        pendingMoveAction = PendingCalendarMove(title: item.title, kind: .localEvent(item.id))
    }

    private func beginMoveTask(_ item: TodoItem) {
        moveTargetDate = item.dueDate ?? Date()
        pendingMoveAction = PendingCalendarMove(title: item.title, kind: .task(item.id))
    }

    private func beginDeleteSystemEvent(_ event: EKEvent) {
        guard let identifier = event.eventIdentifier else { return }
        pendingDeleteAction = PendingCalendarDelete(
            title: event.title ?? localizationManager.text("common.untitled"),
            kind: .systemEvent(identifier)
        )
    }

    private func beginDeleteLocalEvent(_ item: PlanningItem) {
        pendingDeleteAction = PendingCalendarDelete(title: item.title, kind: .localEvent(item.id))
    }

    private func confirmPendingMove(_ action: PendingCalendarMove) async {
        defer { pendingMoveAction = nil }
        switch action.kind {
        case .systemEvent(let identifier):
            do {
                try await calendarManager.moveEvents(with: [identifier], to: moveTargetDate)
                await loadEvents()
            } catch {
                batchEventWarning = localizationManager.format("calendar.error.move_all_failed", error.localizedDescription)
            }
        case .localEvent(let id):
            guard let item = planningStore.items.first(where: { $0.id == id }) else { return }
            planningStore.moveEvent(item, to: moveTargetDate)
            if let updated = planningStore.items.first(where: { $0.id == id }) {
                await googleIntegrationManager.syncLocalCalendarEvent(updated, planningStore: planningStore)
            }
        case .task(let id):
            guard let item = todoStore.items.first(where: { $0.id == id }) else { return }
            var updated = item
            updated.dueDate = moveTargetDate
            updated.hasDueTime = true
            updated.modifiedAt = Date()
            todoStore.updateItem(updated)
        }
    }

    private func confirmPendingDelete(_ action: PendingCalendarDelete) async {
        switch action.kind {
        case .systemEvent(let identifier):
            do {
                try await calendarManager.deleteEvents(with: [identifier])
                await loadEvents()
            } catch {
                batchEventWarning = localizationManager.format("calendar.error.delete_all_failed", error.localizedDescription)
            }
        case .localEvent(let id):
            guard let item = displayedLocalEvents.first(where: { $0.id == id }) else { return }
            await googleIntegrationManager.deleteGoogleCalendarEventIfNeeded(item)
            planningStore.deleteTask(item)
        }
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
            ClientLog.debugError("[CalendarView] Move events failed", error)
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
            ClientLog.debugError("[CalendarView] Delete events failed", error)
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

    private var isGoogleVideoDemoModeEnabled: Bool {
        DeveloperDemoMode.isGoogleVideoDemoModeEnabled(tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private var displayedCalendarEvents: [EKEvent] {
        if isGoogleVideoDemoModeEnabled || googleIntegrationManager.isCalendarConnected {
            return []
        }
        return calendarManager.events.filter {
            DeveloperDemoMode.isSystemEventVisible(
                identifier: $0.eventIdentifier,
                tier: featureGate.tier,
                storedValue: googleVideoDemoMode
            )
        }
    }

    private var displayedLocalEvents: [PlanningItem] {
        let events: [PlanningItem]
        if googleIntegrationManager.isCalendarConnected {
            events = planningStore.localEvents + displayedGoogleSyncedEvents
        } else {
            events = planningStore.localEvents
        }
        return deduplicatedPlanningEvents(
            DeveloperDemoMode.visiblePlanningItems(events, tier: featureGate.tier, storedValue: googleVideoDemoMode)
        )
    }

    private var displayedTodoItems: [TodoItem] {
        DeveloperDemoMode.visibleTasks(todoStore.items, tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private var displayedPendingTodoItems: [TodoItem] {
        DeveloperDemoMode.visibleTasks(todoStore.pendingItems, tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private var displayedGoogleSyncedEvents: [PlanningItem] {
        deduplicatedPlanningEvents(googleIntegrationManager.calendarEvents + planningStore.googleSyncedEvents)
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    private func deduplicatedPlanningEvents(_ events: [PlanningItem]) -> [PlanningItem] {
        var seen = Set<String>()
        return events.filter { event in
            let key = event.googleSyncIdentifier ?? event.id.uuidString
            return seen.insert(key).inserted
        }
    }

    private func events(for day: Date) -> [EKEvent] {
        let calendar = Calendar.current
        return displayedCalendarEvents
            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func localEvents(for day: Date) -> [PlanningItem] {
        let calendar = Calendar.current
        return displayedLocalEvents
            .filter { item in
                guard let start = item.startDate else { return false }
                return calendar.isDate(start, inSameDayAs: day)
            }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
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
        return displayedTodoItems.filter { item in
            guard !item.isCompleted else { return false }
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
        let canSyncCalendar = permissionsManager.isCalendarAuthorized && !googleIntegrationManager.isAnyGoogleServiceConnected
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
            updated.syncToCalendar = canSyncCalendar && entry.calendarWritable
            updated.aiOrigin = .calendarSchedule
            updated.pomodoroPresetID = entry.pomodoroPreset
            updated.plannedPomodoroCount = entry.pomodoros
            updated.modifiedAt = Date()
            todoStore.updateItem(updated)

            guard canSyncCalendar else {
                ClientLog.debug("[CalendarView] Calendar access is off; scheduled task locally only")
                continue
            }

            guard entry.calendarWritable else {
                ClientLog.debug("[CalendarView] Skipping read-only schedule block")
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
                ClientLog.debug("[CalendarView] No writable default calendar available")
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
                ClientLog.debugError("[CalendarView] Failed to save scheduled event", error)
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
        newEventLocationID = nil
        
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

        let item = planningStore.addLocalEvent(
            title: trimmedTitle,
            notes: newEventNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newEventNotes,
            startDate: newEventStart,
            endDate: endDate,
            locationID: newEventLocationID
        )
        await googleIntegrationManager.syncLocalCalendarEvent(item, planningStore: planningStore)
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
                Task {
                    await googleIntegrationManager.syncLocalCalendarEvent(newValue, planningStore: planningStore)
                }
            }
        )
    }
}

private struct AddEventSheet: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @ObservedObject var locationStore: LocationStore
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var durationMinutes: Int
    @Binding var notes: String
    @Binding var locationID: UUID?

    let canUseLocationNotifications: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var showingLocationPicker = false
    
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

                locationPickerRow
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
        .sheet(isPresented: $showingLocationPicker) {
            WorkLocationPickerSheet(
                locationStore: locationStore,
                title: locationID == nil ? "Choose Location" : "Change Location",
                canCreateNewLocation: true,
                canUseLocationNotifications: canUseLocationNotifications,
                notificationTaskCount: 1,
                onCreateLimitReached: {
                    showingLocationPicker = false
                },
                onCancel: {
                    showingLocationPicker = false
                },
                onSelect: { selectedLocationID in
                    locationID = selectedLocationID
                    showingLocationPicker = false
                }
            )
        }
    }

    private var locationPickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("common.location"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label(selectedLocationName, systemImage: locationID == nil ? "mappin" : "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(locationID == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(locationID == nil ? L("common.choose") : L("common.change")) {
                    showingLocationPicker = true
                }
                .buttonStyle(.bordered)

                Button(L("common.clear")) {
                    locationID = nil
                }
                .buttonStyle(.bordered)
                .disabled(locationID == nil)
            }
        }
    }

    private var selectedLocationName: String {
        locationStore.location(id: locationID)?.name ?? L("workspace.location.none")
    }
}

private struct CalendarMoveSheet: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    let title: String
    @Binding var targetDate: Date
    let onCancel: () -> Void
    let onMove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizationManager.text("common.move"))
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            DatePicker(localizationManager.text("common.move_to"), selection: $targetDate, displayedComponents: [.date])

            HStack {
                Button(localizationManager.text("common.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button(localizationManager.text("common.move"), action: onMove)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct CalendarTaskDetailSheet: View {
    let task: TodoItem
    let onClose: () -> Void

    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.title3.weight(.semibold))
                    if let dueDate = task.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: task.hasDueTime ? .shortened : .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(localizationManager.text("common.close"), action: onClose)
                    .buttonStyle(.bordered)
            }

            if let notes = task.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(localizationManager.text("common.notes_optional"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let durationMinutes = task.durationMinutes {
                Label("\(durationMinutes)m", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 460)
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
            planningStore: PlanningStore(),
            goalStore: GoalStore(),
            noteStore: NoteStore(),
            locationStore: LocationStore(),
            calendarAutoSync: CalendarAutoSync(permissionsManager: .shared)
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
        guard planningStore.items.contains(where: { $0.id == eventID && $0.isCalendarEvent && !$0.isTask }) else {
            return nil
        }

        return Binding(
            get: {
                planningStore.items.first(where: { $0.id == eventID && $0.isCalendarEvent && !$0.isTask })
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
            errorMessage = AIService.userFacingErrorMessage(error)
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

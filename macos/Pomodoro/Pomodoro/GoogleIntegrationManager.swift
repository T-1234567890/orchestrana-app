import AppKit
import Combine
import FirebaseCore
import Foundation
import GoogleSignIn

@MainActor
final class GoogleIntegrationManager: ObservableObject {
    static let shared = GoogleIntegrationManager()

    enum GoogleService {
        case calendar
        case tasks

        var scopes: [String] {
            switch self {
            case .calendar:
                return [Self.calendarScope]
            case .tasks:
                return [Self.tasksScope]
            }
        }

        private static let calendarScope = "https://www.googleapis.com/auth/calendar"
        private static let tasksScope = "https://www.googleapis.com/auth/tasks"
    }

    @Published private(set) var isCalendarConnected: Bool
    @Published private(set) var isTasksConnected: Bool
    @Published var isAutoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoSyncEnabled, forKey: Self.autoSyncKey)
            configureAutoSync()
        }
    }
    @Published private(set) var isSyncing = false
    @Published private(set) var isFetchingCalendarEvents = false
    @Published private(set) var calendarEvents: [PlanningItem] = []
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastSyncError: String?

    private weak var todoStore: TodoStore?
    private weak var planningStore: PlanningStore?
    private var itemChangeCancellable: AnyCancellable?
    private var planningItemChangeCancellable: AnyCancellable?
    private var periodicAutoSyncTask: Task<Void, Never>?
    private var changeTriggeredAutoSyncTask: Task<Void, Never>?
    private var retryBackoffTask: Task<Void, Never>?
    private var restoreSessionTask: Task<Void, Never>?
    private var autoSyncRetryAttempt = 0
    private var suppressChangeTriggeredSyncUntil = Date.distantPast
    private let apiClient = GoogleAPIClient()

    private static let calendarConnectedKey = "com.pomodoro.google.calendarConnected"
    private static let tasksConnectedKey = "com.pomodoro.google.tasksConnected"
    private static let autoSyncKey = "com.pomodoro.google.autoSyncEnabled"
    private static let lastSyncKey = "com.pomodoro.google.lastSyncDate"
    private static let calendarEventsCacheKey = "com.pomodoro.google.calendarEventsCache"

    private let periodicSyncIntervalSeconds: TimeInterval = 900
    private let changeDebounceSeconds: TimeInterval = 20
    private let syncChangeSuppressionSeconds: TimeInterval = 10
    private let maxBackoffDelaySeconds: TimeInterval = 300
    private let completedTaskOutboundLimit = 10

    var isAnyGoogleServiceConnected: Bool {
        isCalendarConnected || isTasksConnected
    }

    private init() {
        let defaults = UserDefaults.standard
        self.isCalendarConnected = defaults.bool(forKey: Self.calendarConnectedKey)
        self.isTasksConnected = defaults.bool(forKey: Self.tasksConnectedKey)
        self.isAutoSyncEnabled = defaults.bool(forKey: Self.autoSyncKey)
        self.lastSyncDate = defaults.object(forKey: Self.lastSyncKey) as? Date
        if isCalendarConnected,
           let cachedCalendarEvents = Self.cachedCalendarEvents(from: defaults) {
            self.calendarEvents = cachedCalendarEvents
        }
    }

    deinit {
        periodicAutoSyncTask?.cancel()
        changeTriggeredAutoSyncTask?.cancel()
        retryBackoffTask?.cancel()
        restoreSessionTask?.cancel()
    }

    func setTodoStore(_ store: TodoStore) {
        todoStore = store
        observeLocalItemChanges()
        restoreGoogleSessionIfNeeded()
        configureAutoSync()
    }

    func setPlanningStore(_ store: PlanningStore) {
        planningStore = store
        observeLocalPlanningChanges()
    }

    func connect(_ service: GoogleService) async throws {
        try await authorize(scopes: service.scopes)
        switch service {
        case .calendar:
            setCalendarConnected(true)
        case .tasks:
            setTasksConnected(true)
        }
        if isAutoSyncEnabled {
            scheduleChangeTriggeredAutoSync(immediate: true)
        }
    }

    func connectCalendar() async {
        await connectService(.calendar)
    }

    func connectTasks() async {
        await connectService(.tasks)
    }

    func connectAllServices() async {
        do {
            let scopes = Array(Set(GoogleService.calendar.scopes + GoogleService.tasks.scopes))
            try await authorize(scopes: scopes)
            setCalendarConnected(true)
            setTasksConnected(true)
            lastSyncError = nil
            if isAutoSyncEnabled {
                scheduleChangeTriggeredAutoSync(immediate: true)
            }
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    func disconnectCalendar() {
        setCalendarConnected(false)
    }

    func disconnectTasks() {
        setTasksConnected(false)
    }

    func disconnectAllServices() {
        setCalendarConnected(false)
        setTasksConnected(false)
    }

    func syncNow() async {
        await triggerSync(reason: "manual", retryOnFailure: false)
    }

    func deleteGoogleTaskIfNeeded(_ item: TodoItem) async {
        guard isTasksConnected,
              let googleID = GoogleExternalID.googleTaskID(from: item.reminderIdentifier) else {
            return
        }

        do {
            let token = try await accessToken()
            let taskListID = try await taskListID(containingTaskID: googleID, accessToken: token)
            try await apiClient.deleteTask(taskListID: taskListID, taskID: googleID, accessToken: token)
            lastSyncError = nil
        } catch {
            lastSyncError = "Google Task delete failed: \(error.localizedDescription)"
            ClientLog.debugError("[GoogleIntegration] Delete task failed", error)
        }
    }

    func deleteGoogleCalendarEventIfNeeded(for item: TodoItem) async {
        guard isCalendarConnected,
              let googleID = GoogleExternalID.googleCalendarID(from: item.calendarEventIdentifier ?? item.linkedCalendarEventId) else {
            return
        }

        await deleteGoogleCalendarEvent(id: googleID)
    }

    func deleteGoogleCalendarEventIfNeeded(_ item: PlanningItem) async {
        guard isCalendarConnected,
              let googleID = GoogleExternalID.googleCalendarID(from: item.calendarEventIdentifier ?? item.linkedCalendarEventId ?? item.sourceID) else {
            return
        }

        await deleteGoogleCalendarEvent(id: googleID)
    }

    func syncLocalCalendarEvent(_ item: PlanningItem, planningStore: PlanningStore) async {
        guard isCalendarConnected,
              item.isCalendarEvent,
              !item.isTask,
              DeveloperDemoMode.visiblePlanningItems(
                [item],
                tier: FeatureGate.shared.tier,
                storedValue: UserDefaults.standard.bool(forKey: DeveloperDemoMode.googleVideoDemoModeKey)
              ).isEmpty == false else {
            return
        }

        do {
            let token = try await accessToken()
            let externalID = ExternalID.eventId(for: item.id)
            let googleID = GoogleExternalID.googleCalendarID(from: item.calendarEventIdentifier ?? item.linkedCalendarEventId ?? item.sourceID)
            let event = try await updateOrCreateCalendarEvent(
                item: item,
                knownGoogleID: googleID,
                externalID: externalID,
                accessToken: token
            )
            planningStore.linkToGoogleCalendarEvent(itemID: item.id, googleID: event.id)
            replaceCachedCalendarEvent(Self.planningItem(from: event))
            lastSyncError = nil
        } catch {
            lastSyncError = "Google Calendar event sync failed: \(error.localizedDescription)"
            ClientLog.debugError("[GoogleIntegration] Sync local calendar event failed", error)
        }
    }

    func refreshCalendarEvents(from start: Date, to end: Date) async {
        guard isCalendarConnected else {
            clearCachedCalendarEvents()
            return
        }

        isFetchingCalendarEvents = true
        defer { isFetchingCalendarEvents = false }

        do {
            let token = try await accessToken()
            let remoteEvents = try await apiClient.fetchCalendarEvents(
                from: start,
                to: end,
                accessToken: token
            )
            updateCachedCalendarEvents(remoteEvents.compactMap(Self.planningItem(from:)))
            lastSyncError = nil
        } catch {
            lastSyncError = "Google Calendar refresh failed: \(error.localizedDescription)"
        }
    }

    func restoreGoogleSessionIfNeeded() {
        guard isAnyGoogleServiceConnected else { return }
        guard GIDSignIn.sharedInstance.currentUser == nil else { return }
        guard restoreSessionTask == nil else { return }

        restoreSessionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.restoreSessionTask = nil }
            do {
                let user = try await self.restorePreviousGoogleUser()
                try self.validateConnectedScopes(for: user)
                self.lastSyncError = nil
            } catch {
                self.clearPersistedConnectionAfterRestoreFailure(error)
            }
        }
    }

    private func connectService(_ service: GoogleService) async {
        do {
            try await connect(service)
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    private func observeLocalItemChanges() {
        itemChangeCancellable?.cancel()
        guard let store = todoStore else { return }
        itemChangeCancellable = store.$items
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleChangeTriggeredAutoSync()
            }
    }

    private func observeLocalPlanningChanges() {
        planningItemChangeCancellable?.cancel()
        guard let store = planningStore else { return }
        planningItemChangeCancellable = store.$items
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleChangeTriggeredAutoSync()
            }
    }

    private func configureAutoSync() {
        guard isAutoSyncEnabled, isAnyGoogleServiceConnected else {
            stopAutoSync()
            return
        }
        startAutoSyncIfNeeded()
    }

    private func startAutoSyncIfNeeded() {
        guard periodicAutoSyncTask == nil else { return }
        periodicAutoSyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(periodicSyncIntervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.triggerSync(reason: "periodic", retryOnFailure: true)
            }
        }
    }

    private func stopAutoSync() {
        periodicAutoSyncTask?.cancel()
        periodicAutoSyncTask = nil
        changeTriggeredAutoSyncTask?.cancel()
        changeTriggeredAutoSyncTask = nil
        retryBackoffTask?.cancel()
        retryBackoffTask = nil
        autoSyncRetryAttempt = 0
    }

    private func scheduleChangeTriggeredAutoSync(immediate: Bool = false) {
        guard isAutoSyncEnabled, isAnyGoogleServiceConnected else { return }
        guard shouldHandleChangeTriggeredSync() else { return }
        changeTriggeredAutoSyncTask?.cancel()
        changeTriggeredAutoSyncTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: UInt64(changeDebounceSeconds * 1_000_000_000))
            }
            guard !Task.isCancelled, self.shouldHandleChangeTriggeredSync() else { return }
            await self.triggerSync(reason: "change", retryOnFailure: true)
        }
    }

    private func triggerSync(reason: String, retryOnFailure: Bool) async {
        guard isAnyGoogleServiceConnected else { return }
        guard !isSyncing else { return }

        let succeeded = await performSync(reason: reason)
        if succeeded {
            resetBackoff()
        } else if retryOnFailure {
            scheduleBackoffRetry()
        }
    }

    private func performSync(reason: String) async -> Bool {
        beginSyncOperation()
        defer { endSyncOperation() }

        do {
            guard let store = todoStore else { return true }
            if isTasksConnected {
                try await syncGoogleTasks(store: store)
            }
            if isCalendarConnected {
                try await syncGoogleCalendar(store: store, planningStore: planningStore)
            }
            lastSyncDate = Date()
            if let lastSyncDate {
                UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
            }
            lastSyncError = nil
            store.objectWillChange.send()
            return true
        } catch {
            lastSyncError = "Google \(reason) sync failed: \(error.localizedDescription)"
            return false
        }
    }

    private func syncGoogleTasks(store: TodoStore) async throws {
        let token = try await accessToken()
        let taskLists = try await apiClient.fetchTaskLists(accessToken: token)
        let taskListID = try apiClient.defaultTaskListID(from: taskLists)
        var remoteTasks: [GoogleTask] = []
        var remoteTaskListByID: [String: String] = [:]
        for taskList in taskLists {
            let tasks = try await apiClient.fetchTasks(taskListID: taskList.id, accessToken: token)
            remoteTasks.append(contentsOf: tasks)
            for task in tasks {
                remoteTaskListByID[task.id] = taskList.id
            }
        }
        var remoteByID: [String: GoogleTask] = [:]
        for remote in remoteTasks {
            remoteByID[remote.id] = remote
        }
        let recentRemoteCompletedIDs = Set(
            remoteTasks
                .filter { !$0.deleted && $0.isCompleted }
                .sorted { ($0.updatedDate ?? .distantPast) > ($1.updatedDate ?? .distantPast) }
                .prefix(completedTaskOutboundLimit)
                .map(\.id)
        )

        for remote in remoteTasks where !remote.deleted {
            if remote.isCompleted && !recentRemoteCompletedIDs.contains(remote.id) {
                continue
            }
            if let local = store.items.first(where: { GoogleExternalID.googleTaskID(from: $0.reminderIdentifier) == remote.id }) {
                let remoteModified = remote.updatedDate ?? .distantPast
                let lastSyncedAt = local.lastSyncedAt ?? .distantPast
                guard remoteModified > lastSyncedAt,
                      remoteModified >= local.lastModified else { continue }
                var updated = local
                updated.title = remote.title.isEmpty ? "Untitled Task" : remote.title
                updated.notes = remote.notes
                updated.isCompleted = remote.isCompleted
                updated.dueDate = remote.dueDate
                updated.hasDueTime = false
                updated.reminderIdentifier = GoogleExternalID.task(remote.id)
                updated.lastSyncedAt = Date()
                updated.lastModified = remoteModified
                updated.syncStatus = .synced
                store.updateItem(updated)
            } else {
                let newTask = TodoItem(
                    title: remote.title.isEmpty ? "Untitled Task" : remote.title,
                    notes: remote.notes,
                    isCompleted: remote.isCompleted,
                    dueDate: remote.dueDate,
                    hasDueTime: false,
                    reminderIdentifier: GoogleExternalID.task(remote.id),
                    lastSyncedAt: Date(),
                    syncStatus: .synced
                )
                store.addItem(newTask)
            }
        }

        let outboundSourceItems = syncVisibleItems(from: store.items)
        let recentCompletedTaskIDs = Set(
            outboundSourceItems
                .filter { $0.isCompleted }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(completedTaskOutboundLimit)
                .map(\.id)
        )
        let outboundItems = outboundSourceItems.filter { item in
            guard item.isCompleted else { return true }
            return recentCompletedTaskIDs.contains(item.id)
        }

        for item in outboundItems {
            if let googleID = GoogleExternalID.googleTaskID(from: item.reminderIdentifier),
               let remote = remoteByID[googleID],
               !remote.deleted {
                let targetTaskListID = remoteTaskListByID[googleID] ?? taskListID
                let updated = try await apiClient.updateTask(
                    taskListID: targetTaskListID,
                    taskID: googleID,
                    item: item,
                    accessToken: token
                )
                remoteByID[updated.id] = updated
                markTaskSynced(item, googleID: updated.id, store: store)
            } else {
                let created = try await apiClient.createTask(
                    taskListID: taskListID,
                    item: item,
                    accessToken: token
                )
                remoteByID[created.id] = created
                markTaskSynced(item, googleID: created.id, store: store)
            }
        }
    }

    private func syncGoogleCalendar(store: TodoStore, planningStore: PlanningStore?) async throws {
        let token = try await accessToken()
        let visibleTaskItems = syncVisibleItems(from: store.items)
        let visiblePlanningEvents = syncVisiblePlanningEvents(from: planningStore?.localEvents ?? [])
        let (rangeStart, rangeEnd) = calendarSyncWindow(
            taskItems: visibleTaskItems,
            planningEvents: visiblePlanningEvents
        )
        let allRemoteEvents = try await apiClient.fetchCalendarEvents(
            from: rangeStart,
            to: rangeEnd,
            accessToken: token
        )
        updateCachedCalendarEvents(allRemoteEvents.compactMap(Self.planningItem(from:)))

        let remoteEvents = allRemoteEvents.filter { $0.orchestranaExternalID != nil }
        var remoteByID = Dictionary(uniqueKeysWithValues: remoteEvents.map { ($0.id, $0) })
        var remoteByExternalID: [String: GoogleCalendarEvent] = [:]
        for event in remoteEvents {
            if let externalID = event.orchestranaExternalID {
                remoteByExternalID[externalID] = event
            }
        }

        for item in visibleTaskItems where item.syncToCalendar {
            guard item.dueDate != nil else { continue }
            let externalID = item.externalId.isEmpty ? ExternalID.taskId(for: item.id) : item.externalId
            let googleID = GoogleExternalID.googleCalendarID(from: item.calendarEventIdentifier)
            let existing = googleID.flatMap { remoteByID[$0] } ?? remoteByExternalID[externalID]

            if let existing {
                let remoteModified = existing.updatedDate ?? .distantPast
                if remoteModified > item.lastModified {
                    var updated = item
                    updated.title = existing.summary.isEmpty ? item.title : existing.summary
                    updated.notes = existing.description
                    updated.dueDate = existing.startDate ?? item.dueDate
                    updated.hasDueTime = !existing.isAllDay
                    updated.durationMinutes = existing.durationMinutes ?? item.durationMinutes
                    updated.calendarEventIdentifier = GoogleExternalID.calendar(existing.id)
                    updated.linkedCalendarEventId = GoogleExternalID.calendar(existing.id)
                    updated.lastSyncedAt = Date()
                    updated.lastModified = remoteModified
                    updated.syncStatus = .synced
                    store.updateItem(updated)
                } else {
                    let updated = try await updateOrCreateCalendarEvent(
                        item: item,
                        knownGoogleID: existing.id,
                        externalID: externalID,
                        accessToken: token
                    )
                    remoteByID[updated.id] = updated
                    remoteByExternalID[externalID] = updated
                    markCalendarSynced(item, googleID: updated.id, store: store)
                }
            } else {
                let created = try await updateOrCreateCalendarEvent(
                    item: item,
                    knownGoogleID: googleID,
                    externalID: externalID,
                    accessToken: token
                )
                remoteByID[created.id] = created
                remoteByExternalID[externalID] = created
                markCalendarSynced(item, googleID: created.id, store: store)
            }
        }

        guard let planningStore else { return }
        for item in visiblePlanningEvents {
            guard item.startDate != nil else { continue }
            let externalID = ExternalID.eventId(for: item.id)
            let googleID = GoogleExternalID.googleCalendarID(
                from: item.calendarEventIdentifier ?? item.linkedCalendarEventId ?? item.sourceID
            )
            let existing = googleID.flatMap { remoteByID[$0] } ?? remoteByExternalID[externalID]
            let upserted = try await updateOrCreateCalendarEvent(
                item: item,
                knownGoogleID: existing?.id ?? googleID,
                externalID: externalID,
                accessToken: token
            )
            remoteByID[upserted.id] = upserted
            remoteByExternalID[externalID] = upserted
            planningStore.linkToGoogleCalendarEvent(itemID: item.id, googleID: upserted.id)
            replaceCachedCalendarEvent(Self.planningItem(from: upserted))
        }
    }

    private func syncVisibleItems(from items: [TodoItem]) -> [TodoItem] {
        DeveloperDemoMode.visibleTasks(
            items,
            tier: FeatureGate.shared.tier,
            storedValue: UserDefaults.standard.bool(forKey: DeveloperDemoMode.googleVideoDemoModeKey)
        )
    }

    private func syncVisiblePlanningEvents(from items: [PlanningItem]) -> [PlanningItem] {
        DeveloperDemoMode.visiblePlanningItems(
            items.filter { $0.source == .local && $0.isCalendarEvent && !$0.isTask },
            tier: FeatureGate.shared.tier,
            storedValue: UserDefaults.standard.bool(forKey: DeveloperDemoMode.googleVideoDemoModeKey)
        )
    }

    private func calendarSyncWindow(
        taskItems: [TodoItem],
        planningEvents: [PlanningItem]
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let fallbackStart = calendar.startOfDay(for: Date())
        let fallbackEnd = calendar.date(byAdding: .day, value: 7, to: fallbackStart) ?? fallbackStart
        let dates = taskItems
            .filter(\.syncToCalendar)
            .compactMap(\.dueDate) + planningEvents.flatMap { [$0.startDate, $0.endDate].compactMap { $0 } }
        guard let minDate = dates.min(), let maxDate = dates.max() else {
            return (fallbackStart, fallbackEnd)
        }
        let start = min(fallbackStart, calendar.startOfDay(for: minDate))
        let paddedStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let paddedEnd = calendar.date(byAdding: .day, value: 1, to: max(maxDate, fallbackEnd)) ?? fallbackEnd
        return (paddedStart, paddedEnd)
    }

    private func updateOrCreateCalendarEvent(
        item: TodoItem,
        knownGoogleID: String?,
        externalID: String,
        accessToken: String
    ) async throws -> GoogleCalendarEvent {
        if let knownGoogleID {
            do {
                return try await apiClient.updateCalendarEvent(
                    eventID: knownGoogleID,
                    item: item,
                    externalID: externalID,
                    accessToken: accessToken
                )
            } catch GoogleIntegrationError.http(let statusCode, _) where statusCode == 404 || statusCode == 410 {
                return try await apiClient.createCalendarEvent(
                    item: item,
                    externalID: externalID,
                    accessToken: accessToken
                )
            }
        }
        return try await apiClient.createCalendarEvent(
            item: item,
            externalID: externalID,
            accessToken: accessToken
        )
    }

    private func updateOrCreateCalendarEvent(
        item: PlanningItem,
        knownGoogleID: String?,
        externalID: String,
        accessToken: String
    ) async throws -> GoogleCalendarEvent {
        if let knownGoogleID {
            do {
                return try await apiClient.updateCalendarEvent(
                    eventID: knownGoogleID,
                    item: item,
                    externalID: externalID,
                    accessToken: accessToken
                )
            } catch GoogleIntegrationError.http(let statusCode, _) where statusCode == 404 || statusCode == 410 {
                return try await apiClient.createCalendarEvent(
                    item: item,
                    externalID: externalID,
                    accessToken: accessToken
                )
            }
        }
        return try await apiClient.createCalendarEvent(
            item: item,
            externalID: externalID,
            accessToken: accessToken
        )
    }

    private func deleteGoogleCalendarEvent(id googleID: String) async {
        do {
            let token = try await accessToken()
            try await apiClient.deleteCalendarEvent(eventID: googleID, accessToken: token)
            removeCachedCalendarEvent(googleID: googleID)
            lastSyncError = nil
        } catch {
            lastSyncError = "Google Calendar event delete failed: \(error.localizedDescription)"
            ClientLog.debugError("[GoogleIntegration] Delete calendar event failed", error)
        }
    }

    private func taskListID(containingTaskID googleID: String, accessToken: String) async throws -> String {
        let taskLists = try await apiClient.fetchTaskLists(accessToken: accessToken)
        for taskList in taskLists {
            let tasks = try await apiClient.fetchTasks(taskListID: taskList.id, accessToken: accessToken)
            if tasks.contains(where: { $0.id == googleID }) {
                return taskList.id
            }
        }
        return try apiClient.defaultTaskListID(from: taskLists)
    }

    private func markTaskSynced(_ item: TodoItem, googleID: String, store: TodoStore) {
        guard let current = store.items.first(where: { $0.id == item.id }) else { return }
        var updated = current
        updated.reminderIdentifier = GoogleExternalID.task(googleID)
        updated.lastSyncedAt = Date()
        updated.syncStatus = .synced
        store.updateItem(updated)
    }

    private func markCalendarSynced(_ item: TodoItem, googleID: String, store: TodoStore) {
        guard let current = store.items.first(where: { $0.id == item.id }) else { return }
        let wrappedID = GoogleExternalID.calendar(googleID)
        var updated = current
        updated.calendarEventIdentifier = wrappedID
        updated.linkedCalendarEventId = wrappedID
        updated.lastSyncedAt = Date()
        updated.lastModified = Date()
        updated.syncStatus = .synced
        store.updateItem(updated)
    }

    private func authorize(scopes: [String]) async throws {
        try configureGoogleSignIn()
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first(where: { $0.canBecomeMain }) else {
            throw AuthManagerError.missingPresentingWindow
        }

        if let user = GIDSignIn.sharedInstance.currentUser {
            _ = try await user.addScopes(scopes, presenting: window)
        } else {
            _ = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: window,
                hint: nil,
                additionalScopes: scopes
            )
        }
    }

    private func accessToken() async throws -> String {
        let user = try await currentOrRestoredGoogleUser()
        let refreshedUser = try await user.refreshTokensIfNeeded()
        let token = refreshedUser.accessToken.tokenString
        guard !token.isEmpty else {
            throw GoogleIntegrationError.missingAccessToken
        }
        return token
    }

    private func currentOrRestoredGoogleUser() async throws -> GIDGoogleUser {
        if let user = GIDSignIn.sharedInstance.currentUser {
            try validateConnectedScopes(for: user)
            return user
        }
        let user = try await restorePreviousGoogleUser()
        try validateConnectedScopes(for: user)
        return user
    }

    private func restorePreviousGoogleUser() async throws -> GIDGoogleUser {
        try configureGoogleSignIn()
        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let user else {
                    continuation.resume(throwing: GoogleIntegrationError.notConnected)
                    return
                }
                continuation.resume(returning: user)
            }
        }
    }

    private func configureGoogleSignIn() throws {
        guard FirebaseApp.app() != nil else {
            throw AuthManagerError.firebaseNotConfigured
        }
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AuthManagerError.missingGoogleClientID
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    private func validateConnectedScopes(for user: GIDGoogleUser) throws {
        let grantedScopes = Set(user.grantedScopes ?? [])
        if isCalendarConnected {
            for scope in GoogleService.calendar.scopes where !grantedScopes.contains(scope) {
                throw GoogleIntegrationError.missingRequiredScope(scope)
            }
        }
        if isTasksConnected {
            for scope in GoogleService.tasks.scopes where !grantedScopes.contains(scope) {
                throw GoogleIntegrationError.missingRequiredScope(scope)
            }
        }
    }

    private func clearPersistedConnectionAfterRestoreFailure(_ error: Error) {
        setCalendarConnected(false)
        setTasksConnected(false)
        GIDSignIn.sharedInstance.signOut()
        lastSyncError = "Google connection expired. Connect Google again to resume syncing."
        ClientLog.debugError("[GoogleIntegration] Stored Google connection failed validation", error)
    }

    private func setCalendarConnected(_ value: Bool) {
        isCalendarConnected = value
        UserDefaults.standard.set(value, forKey: Self.calendarConnectedKey)
        if !value {
            clearCachedCalendarEvents()
        }
        configureAutoSync()
    }

    private func setTasksConnected(_ value: Bool) {
        isTasksConnected = value
        UserDefaults.standard.set(value, forKey: Self.tasksConnectedKey)
        configureAutoSync()
    }

    private func scheduleBackoffRetry() {
        guard isAutoSyncEnabled, isAnyGoogleServiceConnected else { return }
        retryBackoffTask?.cancel()
        autoSyncRetryAttempt += 1
        let delay = min(pow(2.0, Double(max(autoSyncRetryAttempt - 1, 0))) * 30, maxBackoffDelaySeconds)
        retryBackoffTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.triggerSync(reason: "retry", retryOnFailure: true)
        }
    }

    private func resetBackoff() {
        autoSyncRetryAttempt = 0
        retryBackoffTask?.cancel()
        retryBackoffTask = nil
    }

    private func beginSyncOperation() {
        changeTriggeredAutoSyncTask?.cancel()
        changeTriggeredAutoSyncTask = nil
        suppressChangeTriggeredSyncUntil = Date().addingTimeInterval(syncChangeSuppressionSeconds)
        isSyncing = true
    }

    private func endSyncOperation() {
        suppressChangeTriggeredSyncUntil = Date().addingTimeInterval(syncChangeSuppressionSeconds)
        isSyncing = false
    }

    private func shouldHandleChangeTriggeredSync() -> Bool {
        !isSyncing && Date() >= suppressChangeTriggeredSyncUntil
    }

    private func updateCachedCalendarEvents(_ events: [PlanningItem]) {
        calendarEvents = events
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.calendarEventsCacheKey)
        }
    }

    private func replaceCachedCalendarEvent(_ event: PlanningItem?) {
        guard let event else { return }
        let identity = event.googleSyncIdentifier ?? event.id.uuidString
        calendarEvents.removeAll { ($0.googleSyncIdentifier ?? $0.id.uuidString) == identity }
        calendarEvents.append(event)
        calendarEvents.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        if let data = try? JSONEncoder().encode(calendarEvents) {
            UserDefaults.standard.set(data, forKey: Self.calendarEventsCacheKey)
        }
    }

    private func removeCachedCalendarEvent(googleID: String) {
        let wrappedID = GoogleExternalID.calendar(googleID)
        calendarEvents.removeAll { event in
            event.sourceID == wrappedID
                || event.calendarEventIdentifier == wrappedID
                || event.linkedCalendarEventId == wrappedID
        }
        if let data = try? JSONEncoder().encode(calendarEvents) {
            UserDefaults.standard.set(data, forKey: Self.calendarEventsCacheKey)
        }
    }

    private func clearCachedCalendarEvents() {
        calendarEvents = []
        UserDefaults.standard.removeObject(forKey: Self.calendarEventsCacheKey)
    }

    private static func cachedCalendarEvents(from defaults: UserDefaults) -> [PlanningItem]? {
        guard let data = defaults.data(forKey: calendarEventsCacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode([PlanningItem].self, from: data)
    }

    private static func planningItem(from event: GoogleCalendarEvent) -> PlanningItem? {
        guard event.status != "cancelled",
              let startDate = event.startDate else {
            return nil
        }

        return PlanningItem(
            title: event.summary.isEmpty ? "Untitled Event" : event.summary,
            notes: event.description,
            startDate: startDate,
            endDate: event.isAllDay ? nil : event.endDate,
            isTask: false,
            isCalendarEvent: true,
            source: .calendar,
            sourceType: .task,
            sourceID: GoogleExternalID.calendar(event.id),
            calendarEventIdentifier: GoogleExternalID.calendar(event.id),
            linkedCalendarEventId: GoogleExternalID.calendar(event.id),
            hasTaskMode: false
        )
    }
}

enum GoogleIntegrationError: LocalizedError {
    case notConnected
    case missingAccessToken
    case missingRequiredScope(String)
    case invalidResponse
    case noTaskList
    case http(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Google service is not connected."
        case .missingAccessToken:
            return "Google did not return an access token."
        case let .missingRequiredScope(scope):
            return "Google did not grant the required scope: \(scope)."
        case .invalidResponse:
            return "Google returned an invalid response."
        case .noTaskList:
            return "No Google Tasks list is available."
        case let .http(statusCode, message):
            return message ?? "Google API request failed with status \(statusCode)."
        }
    }
}

private enum GoogleExternalID {
    private static let taskPrefix = "google-task:"
    private static let calendarPrefix = "google-calendar:"

    static func task(_ id: String) -> String {
        "\(taskPrefix)\(id)"
    }

    static func calendar(_ id: String) -> String {
        "\(calendarPrefix)\(id)"
    }

    static func googleTaskID(from value: String?) -> String? {
        guard let value, value.hasPrefix(taskPrefix) else { return nil }
        return String(value.dropFirst(taskPrefix.count))
    }

    static func googleCalendarID(from value: String?) -> String? {
        guard let value, value.hasPrefix(calendarPrefix) else { return nil }
        return String(value.dropFirst(calendarPrefix.count))
    }
}

private final class GoogleAPIClient {
    private let session: URLSession
    private let isoFormatter = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(session: URLSession = .shared) {
        self.session = session
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func defaultTaskListID(accessToken: String) async throws -> String {
        let taskLists = try await fetchTaskLists(accessToken: accessToken)
        return try defaultTaskListID(from: taskLists)
    }

    func defaultTaskListID(from taskLists: [GoogleTaskList]) throws -> String {
        if let defaultList = taskLists.first(where: { $0.title.localizedCaseInsensitiveContains("task") }) {
            return defaultList.id
        }
        guard let first = taskLists.first else {
            throw GoogleIntegrationError.noTaskList
        }
        return first.id
    }

    func fetchTaskLists(accessToken: String) async throws -> [GoogleTaskList] {
        var allItems: [GoogleTaskList] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
            var queryItems = [URLQueryItem(name: "maxResults", value: "100")]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            let response: GoogleTaskListsResponse = try await send(
                url: components.url!,
                method: "GET",
                accessToken: accessToken
            )
            allItems.append(contentsOf: response.items)
            pageToken = response.nextPageToken
        } while pageToken != nil

        return allItems
    }

    func fetchTasks(taskListID: String, accessToken: String) async throws -> [GoogleTask] {
        var allItems: [GoogleTask] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/lists/\(taskListID.urlPathEncoded)/tasks")!
            var queryItems = [
                URLQueryItem(name: "showCompleted", value: "true"),
                URLQueryItem(name: "showHidden", value: "true"),
                URLQueryItem(name: "showDeleted", value: "true"),
                URLQueryItem(name: "maxResults", value: "100")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            let response: GoogleTasksResponse = try await send(
                url: components.url!,
                method: "GET",
                accessToken: accessToken
            )
            allItems.append(contentsOf: response.items)
            pageToken = response.nextPageToken
        } while pageToken != nil

        return allItems
    }

    func createTask(taskListID: String, item: TodoItem, accessToken: String) async throws -> GoogleTask {
        try await send(
            url: URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(taskListID.urlPathEncoded)/tasks")!,
            method: "POST",
            accessToken: accessToken,
            body: GoogleTaskMutation(from: item)
        )
    }

    func updateTask(taskListID: String, taskID: String, item: TodoItem, accessToken: String) async throws -> GoogleTask {
        try await send(
            url: URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(taskListID.urlPathEncoded)/tasks/\(taskID.urlPathEncoded)")!,
            method: "PATCH",
            accessToken: accessToken,
            body: GoogleTaskMutation(from: item)
        )
    }

    func deleteTask(taskListID: String, taskID: String, accessToken: String) async throws {
        try await sendVoid(
            url: URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(taskListID.urlPathEncoded)/tasks/\(taskID.urlPathEncoded)")!,
            method: "DELETE",
            accessToken: accessToken
        )
    }

    func fetchCalendarEvents(from start: Date, to end: Date, accessToken: String) async throws -> [GoogleCalendarEvent] {
        var allItems: [GoogleCalendarEvent] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
            var queryItems = [
                URLQueryItem(name: "timeMin", value: standardISODate(start)),
                URLQueryItem(name: "timeMax", value: standardISODate(end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "maxResults", value: "250")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            let response: GoogleCalendarEventsResponse = try await send(
                url: components.url!,
                method: "GET",
                accessToken: accessToken
            )
            allItems.append(contentsOf: response.items)
            pageToken = response.nextPageToken
        } while pageToken != nil

        return allItems
    }

    func createCalendarEvent(item: TodoItem, externalID: String, accessToken: String) async throws -> GoogleCalendarEvent {
        try await send(
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!,
            method: "POST",
            accessToken: accessToken,
            body: GoogleCalendarEventMutation(item: item, externalID: externalID)
        )
    }

    func createCalendarEvent(item: PlanningItem, externalID: String, accessToken: String) async throws -> GoogleCalendarEvent {
        try await send(
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!,
            method: "POST",
            accessToken: accessToken,
            body: GoogleCalendarEventMutation(item: item, externalID: externalID)
        )
    }

    func updateCalendarEvent(eventID: String, item: TodoItem, externalID: String, accessToken: String) async throws -> GoogleCalendarEvent {
        try await send(
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventID.urlPathEncoded)")!,
            method: "PATCH",
            accessToken: accessToken,
            body: GoogleCalendarEventMutation(item: item, externalID: externalID)
        )
    }

    func updateCalendarEvent(eventID: String, item: PlanningItem, externalID: String, accessToken: String) async throws -> GoogleCalendarEvent {
        try await send(
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventID.urlPathEncoded)")!,
            method: "PATCH",
            accessToken: accessToken,
            body: GoogleCalendarEventMutation(item: item, externalID: externalID)
        )
    }

    func deleteCalendarEvent(eventID: String, accessToken: String) async throws {
        try await sendVoid(
            url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventID.urlPathEncoded)")!,
            method: "DELETE",
            accessToken: accessToken
        )
    }

    private func send<Response: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        accessToken: String,
        body: Body? = Optional<EmptyBody>.none
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleIntegrationError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GoogleIntegrationError.http(statusCode: httpResponse.statusCode, message: errorMessage(from: data))
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GoogleIntegrationError.invalidResponse
        }
    }

    private func sendVoid(url: URL, method: String, accessToken: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleIntegrationError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 410 else {
            throw GoogleIntegrationError.http(statusCode: httpResponse.statusCode, message: errorMessage(from: data))
        }
    }

    private func standardISODate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func errorMessage(from data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data) else {
            return String(data: data, encoding: .utf8)
        }
        return envelope.error.message
    }
}

private struct EmptyBody: Encodable {}

private struct GoogleTaskListsResponse: Decodable {
    let items: [GoogleTaskList]
    let nextPageToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([GoogleTaskList].self, forKey: .items) ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }

    private enum CodingKeys: String, CodingKey {
        case items, nextPageToken
    }
}

private struct GoogleTaskList: Decodable {
    let id: String
    let title: String
}

private struct GoogleTasksResponse: Decodable {
    let items: [GoogleTask]
    let nextPageToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([GoogleTask].self, forKey: .items) ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }

    private enum CodingKeys: String, CodingKey {
        case items, nextPageToken
    }
}

private struct GoogleTask: Decodable {
    let id: String
    let title: String
    let notes: String?
    let status: String
    let due: String?
    let updated: String?
    let deleted: Bool

    var isCompleted: Bool {
        status == "completed"
    }

    var dueDate: Date? {
        guard let due else { return nil }
        return Self.dueDateFormatter.date(from: String(due.prefix(10)))
            ?? ISO8601DateFormatter().date(from: due)
    }

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var updatedDate: Date? {
        guard let updated else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: updated) ?? standard.date(from: updated)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "needsAction"
        due = try container.decodeIfPresent(String.self, forKey: .due)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, status, due, updated, deleted
    }
}

private struct GoogleTaskMutation: Encodable {
    let title: String
    let notes: String?
    let status: String
    let due: String?

    init(from item: TodoItem) {
        title = item.title
        notes = item.notes
        status = item.isCompleted ? "completed" : "needsAction"
        if let dueDate = item.dueDate {
            due = Self.dueDateFormatter.string(from: dueDate)
        } else {
            due = nil
        }
    }

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'00:00:00.000'Z'"
        return formatter
    }()
}

private struct GoogleCalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEvent]
    let nextPageToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([GoogleCalendarEvent].self, forKey: .items) ?? []
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }

    private enum CodingKeys: String, CodingKey {
        case items, nextPageToken
    }
}

private struct GoogleCalendarEvent: Decodable {
    struct DateValue: Decodable {
        let date: String?
        let dateTime: String?
    }

    struct ExtendedProperties: Decodable {
        let `private`: [String: String]?
    }

    let id: String
    let summary: String
    let status: String
    let description: String?
    let start: DateValue?
    let end: DateValue?
    let updated: String?
    let extendedProperties: ExtendedProperties?

    var orchestranaExternalID: String? {
        extendedProperties?.private?["orchestranaExternalId"]
    }

    var isAllDay: Bool {
        start?.date != nil
    }

    var startDate: Date? {
        parseDateValue(start)
    }

    var endDate: Date? {
        parseDateValue(end)
    }

    var durationMinutes: Int? {
        guard let startDate, let endDate else { return nil }
        return max(1, Int(endDate.timeIntervalSince(startDate) / 60))
    }

    var updatedDate: Date? {
        guard let updated else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: updated) ?? standard.date(from: updated)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "confirmed"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        start = try container.decodeIfPresent(DateValue.self, forKey: .start)
        end = try container.decodeIfPresent(DateValue.self, forKey: .end)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
        extendedProperties = try container.decodeIfPresent(ExtendedProperties.self, forKey: .extendedProperties)
    }

    private func parseDateValue(_ value: DateValue?) -> Date? {
        guard let value else { return nil }
        if let dateTime = value.dateTime {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            return fractional.date(from: dateTime) ?? standard.date(from: dateTime)
        }
        if let date = value.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: date)
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, summary, status, description, start, end, updated, extendedProperties
    }
}

private struct GoogleCalendarEventMutation: Encodable {
    struct DateValue: Encodable {
        let date: String?
        let dateTime: String?
        let timeZone: String?
    }

    struct ExtendedProperties: Encodable {
        let `private`: [String: String]
    }

    let summary: String
    let description: String?
    let start: DateValue
    let end: DateValue
    let extendedProperties: ExtendedProperties

    init(item: TodoItem, externalID: String) {
        summary = item.title
        description = item.notes
        extendedProperties = ExtendedProperties(private: [
            "orchestranaManaged": "true",
            "orchestranaExternalId": externalID
        ])

        let calendar = Calendar.current
        let timeZoneID = TimeZone.current.identifier
        if let dueDate = item.dueDate {
            if item.hasDueTime {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime]
                start = DateValue(date: nil, dateTime: formatter.string(from: dueDate), timeZone: timeZoneID)
                let endDate = dueDate.addingTimeInterval(Double((item.durationMinutes ?? 30) * 60))
                end = DateValue(date: nil, dateTime: formatter.string(from: endDate), timeZone: timeZoneID)
            } else {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy-MM-dd"
                let startOfDay = calendar.startOfDay(for: dueDate)
                let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
                start = DateValue(date: formatter.string(from: startOfDay), dateTime: nil, timeZone: nil)
                end = DateValue(date: formatter.string(from: endOfDay), dateTime: nil, timeZone: nil)
            }
        } else {
            let now = Date()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            start = DateValue(date: nil, dateTime: formatter.string(from: now), timeZone: timeZoneID)
            end = DateValue(date: nil, dateTime: formatter.string(from: now.addingTimeInterval(30 * 60)), timeZone: timeZoneID)
        }
    }

    init(item: PlanningItem, externalID: String) {
        summary = item.title
        description = item.notes
        extendedProperties = ExtendedProperties(private: [
            "orchestranaManaged": "true",
            "orchestranaExternalId": externalID
        ])

        let timeZoneID = TimeZone.current.identifier
        let startDate = item.startDate ?? Date()
        let endDate = item.endDate ?? startDate.addingTimeInterval(30 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        start = DateValue(date: nil, dateTime: formatter.string(from: startDate), timeZone: timeZoneID)
        end = DateValue(date: nil, dateTime: formatter.string(from: max(endDate, startDate.addingTimeInterval(60))), timeZone: timeZoneID)
    }
}

private struct GoogleErrorEnvelope: Decodable {
    struct GoogleError: Decodable {
        let message: String?
    }

    let error: GoogleError
}

private extension String {
    var urlPathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}

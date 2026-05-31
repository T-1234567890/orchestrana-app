import Foundation
import Combine
import EventKit

/// Task-centric sync wrapper that delegates all EventKit work to SyncEngine.
@MainActor
final class RemindersSync: ObservableObject {
    private let permissionsManager: PermissionsManager
    private let syncEngine: SyncEngine
    private weak var todoStore: TodoStore?
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncError: String?
    @Published var lastSyncDate: Date?
    @Published var isAutoSyncEnabled: Bool {
        didSet {
            persistAutoSyncPreference()
            configureAutoSyncBehavior()
        }
    }

    private let autoSyncDefaultsKey = "com.pomodoro.remindersAutoSyncEnabled"
    private var itemChangeCancellable: AnyCancellable?
    private var periodicAutoSyncTask: Task<Void, Never>?
    private var changeTriggeredSyncTask: Task<Void, Never>?
    private var remindersChangeSyncTask: Task<Void, Never>?
    private var retryBackoffTask: Task<Void, Never>?
    private var eventStoreChangeCancellable: AnyCancellable?
    private var autoSyncRetryAttempt = 0
    private var suppressChangeTriggeredSyncUntil = Date.distantPast

    private let periodicSyncIntervalSeconds: TimeInterval = 300
    private let changeDebounceSeconds: TimeInterval = 1.5
    private let syncChangeSuppressionSeconds: TimeInterval = 5
    private let maxBackoffDelaySeconds: TimeInterval = 60
    
    init(permissionsManager: PermissionsManager, syncEngine: SyncEngine? = nil) {
        self.permissionsManager = permissionsManager
        self.syncEngine = syncEngine ?? SyncEngine(permissionsManager: permissionsManager)
        self.isAutoSyncEnabled = UserDefaults.standard.bool(forKey: autoSyncDefaultsKey)
    }

    deinit {
        periodicAutoSyncTask?.cancel()
        changeTriggeredSyncTask?.cancel()
        remindersChangeSyncTask?.cancel()
        retryBackoffTask?.cancel()
    }
    
    func setTodoStore(_ store: TodoStore) {
        todoStore = store
        syncEngine.attachTodoStore(store)
        observeLocalItemChanges()
        observeReminderStoreChanges()
        configureAutoSyncBehavior()
    }
    
    // MARK: - Sync Operations
    
    var isSyncAvailable: Bool {
        permissionsManager.isRemindersAuthorized && !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected
    }
    
    /// Sync a single task by invoking the unified reminders sync.
    func syncTask(_ item: TodoItem) async throws {
        guard !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else {
            lastSyncError = "Apple Reminders sync is paused while Google services are connected."
            return
        }
        beginSyncOperation()
        defer { endSyncOperation() }
        
        do {
            let reminderId = try await syncEngine.syncReminder(for: item)
            todoStore?.linkToReminder(itemId: item.id, remindersId: reminderId)
            lastSyncError = nil
            lastSyncDate = Date()
            resetAutoSyncBackoff()
        } catch {
            lastSyncError = error.localizedDescription
            throw error
        }
    }
    
    /// Unified sync for all tasks (delegates to SyncEngine).
    func syncAllTasks() async {
        guard !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else {
            lastSyncError = "Apple Reminders sync is paused while Google services are connected."
            return
        }
        beginSyncOperation()
        defer { endSyncOperation() }
        
        do {
            try await syncEngine.syncTasksWithReminders()
            lastSyncError = nil
            lastSyncDate = Date()
            resetAutoSyncBackoff()
            DispatchQueue.main.async {
                self.todoStore?.objectWillChange.send()
            }
        } catch {
            lastSyncError = error.localizedDescription
        }
    }

    /// Re-read Apple Reminders and push linked local updates back out.
    func resynchronizeReminders() async {
        await syncAllTasks()
    }

    /// Re-read one linked Apple Reminder into its local task.
    func resynchronizeTaskFromReminder(_ item: TodoItem) async throws {
        guard !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else {
            lastSyncError = "Apple Reminders sync is paused while Google services are connected."
            return
        }
        guard item.reminderIdentifier != nil else { return }

        beginSyncOperation()
        defer { endSyncOperation() }

        do {
            try await syncEngine.resyncTaskFromReminder(item)
            lastSyncError = nil
            lastSyncDate = Date()
            resetAutoSyncBackoff()
            DispatchQueue.main.async {
                self.todoStore?.objectWillChange.send()
            }
        } catch {
            lastSyncError = error.localizedDescription
            throw error
        }
    }
    
    /// Remove Reminder link (does not delete remote)
    func unsyncFromReminders(_ item: TodoItem) {
        guard item.reminderIdentifier != nil else { return }
        todoStore?.unlinkFromReminder(itemId: item.id)
    }
    
    /// Delete reminder from Apple Reminders via SyncEngine.
    func deleteReminder(_ item: TodoItem) async throws {
        guard !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else {
            lastSyncError = "Apple Reminders sync is paused while Google services are connected."
            return
        }
        beginSyncOperation()
        defer { endSyncOperation() }

        try await syncEngine.deleteReminder(for: item)
        todoStore?.unlinkFromReminder(itemId: item.id)
    }

    // MARK: - Auto Sync

    private func observeLocalItemChanges() {
        itemChangeCancellable?.cancel()
        guard let store = todoStore else { return }

        itemChangeCancellable = store.$items
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleChangeTriggeredAutoSync()
            }
    }

    private func observeReminderStoreChanges() {
        eventStoreChangeCancellable?.cancel()
        eventStoreChangeCancellable = NotificationCenter.default
            .publisher(for: .EKEventStoreChanged)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleReminderStoreChangeSync()
            }
    }

    private func configureAutoSyncBehavior() {
        guard isAutoSyncEnabled, !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else {
            stopAutoSync()
            return
        }
        startAutoSyncIfNeeded()
        scheduleChangeTriggeredAutoSync(immediate: true)
    }

    private func startAutoSyncIfNeeded() {
        guard periodicAutoSyncTask == nil else { return }
        periodicAutoSyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let nanoseconds = UInt64(periodicSyncIntervalSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                await self.triggerAutoSync(reason: "periodic")
            }
        }
    }

    private func stopAutoSync() {
        periodicAutoSyncTask?.cancel()
        periodicAutoSyncTask = nil
        changeTriggeredSyncTask?.cancel()
        changeTriggeredSyncTask = nil
        remindersChangeSyncTask?.cancel()
        remindersChangeSyncTask = nil
        retryBackoffTask?.cancel()
        retryBackoffTask = nil
        autoSyncRetryAttempt = 0
    }

    private func scheduleChangeTriggeredAutoSync(immediate: Bool = false) {
        guard isAutoSyncEnabled else { return }
        guard !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else { return }
        guard shouldHandleChangeTriggeredSync() else { return }
        changeTriggeredSyncTask?.cancel()
        changeTriggeredSyncTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                let nanoseconds = UInt64(changeDebounceSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled, self.shouldHandleChangeTriggeredSync() else { return }
            await self.triggerAutoSync(reason: "change")
        }
    }

    private func scheduleReminderStoreChangeSync() {
        guard isAutoSyncEnabled else { return }
        guard !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else { return }
        guard isSyncAvailable else { return }
        guard shouldHandleChangeTriggeredSync() else { return }
        remindersChangeSyncTask?.cancel()
        remindersChangeSyncTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(changeDebounceSeconds * 1_000_000_000))
            guard !Task.isCancelled, self.shouldHandleChangeTriggeredSync() else { return }
            await self.resynchronizeReminders()
        }
    }

    private func triggerAutoSync(reason: String) async {
        guard isAutoSyncEnabled else { return }
        guard !GoogleIntegrationManager.shared.isAnyGoogleServiceConnected else {
            lastSyncError = "Apple Reminders sync is paused while Google services are connected."
            return
        }
        guard isSyncAvailable else {
            lastSyncError = LocalizationManager.shared.text("tasks.sync.auto_requires_reminders_access")
            return
        }
        guard !isSyncing else { return }

        let succeeded = await performAutoSync(mode: reason)
        if succeeded {
            resetAutoSyncBackoff()
        } else {
            scheduleBackoffRetry()
        }
    }

    private func performAutoSync(mode: String) async -> Bool {
        beginSyncOperation()
        defer { endSyncOperation() }

        do {
            try await syncEngine.syncTasksWithReminders()
            lastSyncError = nil
            lastSyncDate = Date()
            todoStore?.objectWillChange.send()
            return true
        } catch {
            lastSyncError = LocalizationManager.shared.format("tasks.sync.auto_failed_format", mode, error.localizedDescription)
            return false
        }
    }

    private func scheduleBackoffRetry() {
        guard isAutoSyncEnabled else { return }
        retryBackoffTask?.cancel()
        autoSyncRetryAttempt += 1
        let delay = min(pow(2.0, Double(max(autoSyncRetryAttempt - 1, 0))), maxBackoffDelaySeconds)
        retryBackoffTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self.triggerAutoSync(reason: "retry")
        }
    }

    private func resetAutoSyncBackoff() {
        autoSyncRetryAttempt = 0
        retryBackoffTask?.cancel()
        retryBackoffTask = nil
    }

    private func beginSyncOperation() {
        remindersChangeSyncTask?.cancel()
        remindersChangeSyncTask = nil
        changeTriggeredSyncTask?.cancel()
        changeTriggeredSyncTask = nil
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

    private func persistAutoSyncPreference() {
        UserDefaults.standard.set(isAutoSyncEnabled, forKey: autoSyncDefaultsKey)
    }
}

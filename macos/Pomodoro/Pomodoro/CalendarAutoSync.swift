import Foundation
import Combine
import EventKit

@MainActor
final class CalendarAutoSync: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncError: String?
    @Published var lastSyncDate: Date?
    @Published var isAutoSyncEnabled: Bool {
        didSet {
            persistAutoSyncPreference()
            configureAutoSyncBehavior()
        }
    }

    private let permissionsManager: PermissionsManager
    private let syncEngine: SyncEngine
    private weak var todoStore: TodoStore?
    private var visibleRefreshHandler: (() async -> Void)?
    private var eventStoreChangeCancellable: AnyCancellable?
    private var periodicAutoSyncTask: Task<Void, Never>?
    private var changeTriggeredSyncTask: Task<Void, Never>?
    private var visibleRefreshTask: Task<Void, Never>?
    private var retryBackoffTask: Task<Void, Never>?
    private var autoSyncRetryAttempt = 0
    private var suppressChangeTriggeredSyncUntil = Date.distantPast

    private let autoSyncDefaultsKey = "com.pomodoro.calendarAutoSyncEnabled"
    private let periodicSyncIntervalSeconds: TimeInterval = 300
    private let changeDebounceSeconds: TimeInterval = 1.5
    private let syncChangeSuppressionSeconds: TimeInterval = 5
    private let maxBackoffDelaySeconds: TimeInterval = 60

    init(permissionsManager: PermissionsManager, syncEngine: SyncEngine? = nil) {
        self.permissionsManager = permissionsManager
        self.syncEngine = syncEngine ?? SyncEngine(permissionsManager: permissionsManager)
        self.isAutoSyncEnabled = UserDefaults.standard.bool(forKey: autoSyncDefaultsKey)
        observeCalendarStoreChanges()
        configureAutoSyncBehavior()
    }

    deinit {
        periodicAutoSyncTask?.cancel()
        changeTriggeredSyncTask?.cancel()
        visibleRefreshTask?.cancel()
        retryBackoffTask?.cancel()
    }

    func setTodoStore(_ store: TodoStore) {
        todoStore = store
        syncEngine.attachTodoStore(store)
    }

    func setVisibleRefreshHandler(_ handler: @escaping () async -> Void) {
        visibleRefreshHandler = handler
    }

    func visibleRangeDidChange() {
        scheduleVisibleRefresh(immediate: true)
        guard isAutoSyncEnabled else { return }
        scheduleChangeTriggeredAutoSync(reason: "visible-range")
    }

    func syncNow(refreshVisibleEvents: Bool = true) async {
        await triggerSync(reason: "manual", refreshVisibleEvents: refreshVisibleEvents, retryOnFailure: false)
    }

    private func observeCalendarStoreChanges() {
        eventStoreChangeCancellable = NotificationCenter.default
            .publisher(for: .EKEventStoreChanged)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleVisibleRefresh()
                self.scheduleChangeTriggeredAutoSync(reason: "calendar-change")
            }
    }

    private func configureAutoSyncBehavior() {
        guard isAutoSyncEnabled else {
            stopAutoSync()
            return
        }
        startAutoSyncIfNeeded()
        scheduleChangeTriggeredAutoSync(reason: "enabled", immediate: true)
    }

    private func startAutoSyncIfNeeded() {
        guard periodicAutoSyncTask == nil else { return }
        periodicAutoSyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(periodicSyncIntervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.triggerSync(reason: "periodic", refreshVisibleEvents: true, retryOnFailure: true)
            }
        }
    }

    private func stopAutoSync() {
        periodicAutoSyncTask?.cancel()
        periodicAutoSyncTask = nil
        changeTriggeredSyncTask?.cancel()
        changeTriggeredSyncTask = nil
        retryBackoffTask?.cancel()
        retryBackoffTask = nil
        autoSyncRetryAttempt = 0
    }

    private func scheduleVisibleRefresh(immediate: Bool = false) {
        guard permissionsManager.isCalendarAuthorized else { return }
        visibleRefreshTask?.cancel()
        visibleRefreshTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: UInt64(changeDebounceSeconds * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self.visibleRefreshHandler?()
        }
    }

    private func scheduleChangeTriggeredAutoSync(reason: String, immediate: Bool = false) {
        guard isAutoSyncEnabled else { return }
        guard permissionsManager.isCalendarAuthorized else { return }
        guard shouldHandleChangeTriggeredSync() else { return }
        changeTriggeredSyncTask?.cancel()
        changeTriggeredSyncTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: UInt64(changeDebounceSeconds * 1_000_000_000))
            }
            guard !Task.isCancelled, self.shouldHandleChangeTriggeredSync() else { return }
            await self.triggerSync(reason: reason, refreshVisibleEvents: true, retryOnFailure: true)
        }
    }

    private func triggerSync(reason: String, refreshVisibleEvents: Bool, retryOnFailure: Bool) async {
        guard permissionsManager.isCalendarAuthorized else {
            lastSyncError = "Calendar access is required for auto-sync."
            return
        }
        guard !isSyncing else { return }

        let succeeded = await performSync(reason: reason, refreshVisibleEvents: refreshVisibleEvents)
        if succeeded {
            resetAutoSyncBackoff()
        } else if retryOnFailure {
            scheduleBackoffRetry()
        }
    }

    private func performSync(reason: String, refreshVisibleEvents: Bool) async -> Bool {
        beginSyncOperation()
        defer { endSyncOperation() }

        do {
            try await syncEngine.syncCalendarEvents()
            lastSyncError = nil
            lastSyncDate = Date()
            todoStore?.objectWillChange.send()
            if refreshVisibleEvents {
                await visibleRefreshHandler?()
            }
            return true
        } catch {
            lastSyncError = "Calendar \(reason) sync failed: \(error.localizedDescription)"
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
            await self.triggerSync(reason: "retry", refreshVisibleEvents: true, retryOnFailure: true)
        }
    }

    private func resetAutoSyncBackoff() {
        autoSyncRetryAttempt = 0
        retryBackoffTask?.cancel()
        retryBackoffTask = nil
    }

    private func beginSyncOperation() {
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

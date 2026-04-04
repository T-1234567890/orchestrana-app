//
//  AppState.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import Combine
import SwiftUI
import UserNotifications
import EventKit

final class AppState: ObservableObject {
    let pomodoro: PomodoroTimerEngine
    let countdown: CountdownTimerEngine
    let ambientNoiseEngine: AmbientNoiseEngine
    let nowPlayingRouter: NowPlayingRouter

    @Published var durationConfig: DurationConfig {
        didSet {
            updatePomodoroConfiguration()
            durationConfig.save(to: userDefaults)
        }
    }

    @Published var presetSelection: PresetSelection {
        didSet {
            savePresetSelection()
        }
    }

    @Published private(set) var pomodoroMode: PomodoroTimerEngine.Mode
    @Published private(set) var pomodoroCurrentMode: PomodoroTimerEngine.CurrentMode
    @Published private(set) var currentPlanTitle: String?
    @Published private(set) var currentPlanPomodoros: Int?
    @Published private(set) var currentPlanPresetID: String?
    @Published private(set) var dailyStats: DailyStats
    @Published var notificationPreference: NotificationPreference {
        didSet {
            saveNotificationPreference()
            requestNotificationAuthorizationIfNeeded()
        }
    }
    @Published var notificationDeliveryStyle: NotificationDeliveryStyle {
        didSet {
            saveNotificationDeliveryStyle()
            requestNotificationAuthorizationIfNeeded()
        }
    }
    @Published var reminderPreference: ReminderPreference {
        didSet {
            saveReminderPreference()
            requestNotificationAuthorizationIfNeeded()
        }
    }
    // UI-only flag: Flow Mode is a presentation context, not a data/pomodoro state.
    // This is intentionally not persisted and must not trigger timer resets.
    @Published var isInFlowMode: Bool = false
    @Published private(set) var transitionPopup: TransitionPopup?
    @Published private(set) var notificationPopup: NotificationPopup?

    private var cancellables: Set<AnyCancellable> = []
    private let userDefaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter
    private var pomodoroDidReachZero = false
    private var countdownDidReachZero = false
    private var pomodoroReminderSent = false
    private var countdownReminderSent = false
    private var lastPomodoroState: TimerState?
    private var lastCountdownState: TimerState?
    private var lastBreakMode: PomodoroTimerEngine.CurrentMode?
    private var currentFocusDurationSeconds: Int?
    private var currentBreakDurationSeconds: Int?
    private var hasRequestedNotificationAuthorization: Bool = false
    private let eventStore = SharedEventStore.shared.eventStore
    private var pendingExecutionQueue: [PlanExecutionEntry] = []
    private var activeExecutionEntry: PlanExecutionEntry?

    struct PlanExecutionEntry: Identifiable, Equatable {
        let id: UUID
        let title: String
        let pomodoros: Int
        let pomodoroPresetID: String?
    }

    // Designated initializer - no default arguments to avoid linker symbol issues
    @MainActor
    init(
        pomodoro: PomodoroTimerEngine,
        countdown: CountdownTimerEngine,
        durationConfig: DurationConfig,
        userDefaults: UserDefaults,
        ambientNoiseEngine: AmbientNoiseEngine
    ) {
        self.pomodoro = pomodoro
        self.countdown = countdown
        self.ambientNoiseEngine = ambientNoiseEngine
        self.nowPlayingRouter = NowPlayingRouter(startPolling: false)
        self.durationConfig = durationConfig
        self.presetSelection = Self.loadPresetSelection(from: userDefaults, durationConfig: durationConfig)
        self.pomodoroMode = pomodoro.mode
        self.pomodoroCurrentMode = pomodoro.currentMode
        self.dailyStats = Self.loadDailyStats(from: userDefaults)
        self.userDefaults = userDefaults
        self.notificationCenter = UNUserNotificationCenter.current()
        self.notificationPreference = NotificationPreference(
            rawValue: userDefaults.string(forKey: DefaultsKey.notificationPreference) ?? ""
        ) ?? .off
        self.notificationDeliveryStyle = NotificationDeliveryStyle(
            rawValue: userDefaults.string(forKey: DefaultsKey.notificationDeliveryStyle) ?? ""
        ) ?? .system
        self.reminderPreference = ReminderPreference(
            rawValue: userDefaults.string(forKey: DefaultsKey.reminderPreference) ?? ""
        ) ?? .off
        self.lastPomodoroState = pomodoro.state
        self.lastCountdownState = countdown.state
        self.hasRequestedNotificationAuthorization = userDefaults.bool(
            forKey: DefaultsKey.notificationAuthorizationRequested
        )

        pomodoro.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        pomodoro.$mode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.pomodoroMode = mode
            }
            .store(in: &cancellables)

        pomodoro.$currentMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.pomodoroCurrentMode = mode
            }
            .store(in: &cancellables)

        countdown.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        pomodoro.$remainingSeconds
            .removeDuplicates()
            .sink { [weak self] seconds in
                self?.handlePomodoroRemaining(seconds)
            }
            .store(in: &cancellables)

        pomodoro.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.handlePomodoroStateChange(state)
            }
            .store(in: &cancellables)

        countdown.$remainingSeconds
            .removeDuplicates()
            .sink { [weak self] seconds in
                self?.handleCountdownRemaining(seconds)
            }
            .store(in: &cancellables)

        countdown.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.handleCountdownStateChange(state)
            }
            .store(in: &cancellables)

        updatePomodoroConfiguration()
        refreshDailyStatsForCurrentDay()
        requestNotificationAuthorizationIfNeeded()
    }

    // Convenience initializer with explicit UserDefaults forwarding
    @MainActor
    convenience init(
        pomodoro: PomodoroTimerEngine,
        countdown: CountdownTimerEngine,
        userDefaults: UserDefaults,
        ambientNoiseEngine: AmbientNoiseEngine
    ) {
        let storedConfig = DurationConfig.load(from: userDefaults)
        self.init(
            pomodoro: pomodoro,
            countdown: countdown,
            durationConfig: storedConfig,
            userDefaults: userDefaults,
            ambientNoiseEngine: ambientNoiseEngine
        )
    }

    // Convenience initializer with explicit standard UserDefaults
    @MainActor
    convenience init(
        pomodoro: PomodoroTimerEngine,
        countdown: CountdownTimerEngine
    ) {
        self.init(
            pomodoro: pomodoro,
            countdown: countdown,
            userDefaults: .standard,
            ambientNoiseEngine: AmbientNoiseEngine()
        )
    }

    // Parameterless convenience initializer with explicit defaults
    @MainActor
    convenience init() {
        self.init(
            pomodoro: PomodoroTimerEngine(),
            countdown: CountdownTimerEngine()
        )
    }

    private func updatePomodoroConfiguration() {
        pomodoro.updateConfiguration(
            durationConfig: durationConfig
        )
        countdown.updateConfiguration(durationConfig: durationConfig)
    }

    func applyPresetSelection(_ selection: PresetSelection) {
        switch selection {
        case .preset(let preset):
            selectPreset(preset)
        case .custom:
            presetSelection = .custom
        }
    }

    func selectPreset(_ preset: Preset) {
        Task { @MainActor [weak self] in
            self?.presetSelection = .preset(preset)
            self?.durationConfig = preset.durationConfig
        }
    }

    func applyCustomDurationConfig(_ config: DurationConfig) {
        presetSelection = .custom
        durationConfig = config
    }

    func startPomodoro() {
        pomodoro.start()
    }

    func previewPomodoroSession(durationConfig: DurationConfig) {
        pomodoro.updateConfiguration(durationConfig: durationConfig)
    }

    func startPomodoroSession(durationConfig: DurationConfig) {
        pomodoro.updateConfiguration(durationConfig: durationConfig)
        pomodoro.start()
    }

    func applyPlan(title: String, pomodoroCount: Int, pomodoroPresetID: String? = nil) {
        currentPlanTitle = title
        currentPlanPomodoros = max(1, pomodoroCount)
        currentPlanPresetID = pomodoroPresetID
    }

    func startExecutionPlan(_ entries: [PlanExecutionEntry]) {
        guard let first = entries.first else { return }
        pendingExecutionQueue = Array(entries.dropFirst())
        activeExecutionEntry = first
        pomodoro.reset()
        applyExecutionPreset(first.pomodoroPresetID)
        applyPlan(title: first.title, pomodoroCount: first.pomodoros, pomodoroPresetID: first.pomodoroPresetID)
        pomodoro.start()
    }

    func clearExecutionPlan() {
        pendingExecutionQueue = []
        activeExecutionEntry = nil
        currentPlanTitle = nil
        currentPlanPomodoros = nil
        currentPlanPresetID = nil
    }

    func startOrPausePomodoro() {
        switch pomodoro.state {
        case .idle:
            pomodoro.start()
        case .running, .breakRunning:
            pomodoro.pause()
        case .paused, .breakPaused:
            pomodoro.resume()
        }
    }

    func togglePomodoroPause() {
        switch pomodoro.state {
        case .running, .breakRunning:
            pomodoro.pause()
        case .paused, .breakPaused:
            pomodoro.resume()
        case .idle:
            break
        }
    }

    func resetPomodoro() {
        pomodoro.reset()
        clearExecutionPlan()
        updatePomodoroConfiguration()
    }

    func startBreak() {
        pomodoro.startBreak()
    }

    func skipBreak() {
        pomodoro.skipBreak()
    }

    func startCountdown() {
        countdown.start()
    }

    func toggleCountdownPause() {
        switch countdown.state {
        case .running:
            countdown.pause()
        case .paused:
            countdown.resume()
        case .idle, .breakRunning, .breakPaused:
            break
        }
    }

    func resetCountdown() {
        countdown.reset()
    }

    private enum DefaultsKey {
        static let notificationPreference = "notification.preference"
        static let reminderPreference = "notification.reminderPreference"
        static let notificationDeliveryStyle = "notification.deliveryStyle"
        static let dailyStats = "dailyStats.current"
        static let presetSelection = "durationConfig.presetSelection"
        static let notificationAuthorizationRequested = "notification.authorizationRequested"
    }

    private func saveNotificationPreference() {
        userDefaults.set(notificationPreference.rawValue, forKey: DefaultsKey.notificationPreference)
    }

    private func saveNotificationDeliveryStyle() {
        userDefaults.set(notificationDeliveryStyle.rawValue, forKey: DefaultsKey.notificationDeliveryStyle)
    }

    private func saveReminderPreference() {
        userDefaults.set(reminderPreference.rawValue, forKey: DefaultsKey.reminderPreference)
    }

    private func savePresetSelection() {
        let value: String
        switch presetSelection {
        case .preset(let preset):
            value = preset.id
        case .custom:
            value = Self.customPresetSelectionValue
        }
        userDefaults.set(value, forKey: DefaultsKey.presetSelection)
    }

    private static let customPresetSelectionValue = "custom"

    private static func loadPresetSelection(
        from userDefaults: UserDefaults,
        durationConfig: DurationConfig
    ) -> PresetSelection {
        guard let storedValue = userDefaults.string(forKey: DefaultsKey.presetSelection) else {
            return PresetSelection.selection(for: durationConfig)
        }
        if storedValue == customPresetSelectionValue {
            return .custom
        }
        if let preset = Preset.builtIn.first(where: { $0.id == storedValue }) {
            return .preset(preset)
        }
        return PresetSelection.selection(for: durationConfig)
    }

    private static func loadDailyStats(from userDefaults: UserDefaults) -> DailyStats {
        guard let data = userDefaults.data(forKey: DefaultsKey.dailyStats) else {
            return DailyStats()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let stats = try? decoder.decode(DailyStats.self, from: data) {
            return stats
        }
        return DailyStats()
    }

    private func saveDailyStats(_ stats: DailyStats) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(stats) else { return }
        userDefaults.set(data, forKey: DefaultsKey.dailyStats)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard notificationDeliveryStyle == .system else { return }
        guard notificationPreference != .off || reminderPreference != .off else { return }
        guard hasRequestedNotificationAuthorization == false else { return }
        hasRequestedNotificationAuthorization = true
        userDefaults.set(true, forKey: DefaultsKey.notificationAuthorizationRequested)

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            guard settings.authorizationStatus == .notDetermined else { return }

            self.notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in
            }
        }
    }

    func requestSystemNotificationAuthorization(
        completion: @escaping (UNAuthorizationStatus) -> Void
    ) {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            if settings.authorizationStatus == .notDetermined {
                self.userDefaults.set(true, forKey: DefaultsKey.notificationAuthorizationRequested)
                self.hasRequestedNotificationAuthorization = true
                self.notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in
                    self.notificationCenter.getNotificationSettings { updatedSettings in
                        DispatchQueue.main.async {
                            completion(updatedSettings.authorizationStatus)
                        }
                    }
                }
            } else {
                self.hasRequestedNotificationAuthorization = true
                DispatchQueue.main.async {
                    completion(settings.authorizationStatus)
                }
            }
        }
    }

    @MainActor
    func requestCalendarAndReminderAccessIfNeeded() async {
        let calendarStatus = EKEventStore.authorizationStatus(for: .event)
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)

        if calendarStatus == .notDetermined {
            if #available(macOS 14, *) {
                _ = try? await eventStore.requestFullAccessToEvents()
            } else {
                _ = try? await eventStore.requestAccess(to: .event)
            }
        }
        if reminderStatus == .notDetermined {
            if #available(macOS 14, *) {
                _ = try? await eventStore.requestFullAccessToReminders()
            } else {
                _ = try? await eventStore.requestAccess(to: .reminder)
            }
        }
    }

    var calendarReminderPermissionStatusText: String {
        let l10n = LocalizationManager.shared
        let cal = EKEventStore.authorizationStatus(for: .event)
        let rem = EKEventStore.authorizationStatus(for: .reminder)
        switch (cal, rem) {
        case (.authorized, .authorized):
            return l10n.text("permissions.status.calendar_and_reminders_enabled")
        case (.authorized, _):
            return l10n.text("permissions.status.calendar_enabled_reminders_optional")
        case (_, .authorized):
            return l10n.text("permissions.status.reminders_enabled_calendar_optional")
        default:
            return l10n.text("permissions.status.access_not_granted")
        }
    }

    private func handlePomodoroRemaining(_ seconds: Int) {
        if seconds == 0 {
            if pomodoro.state == .running || pomodoro.state == .breakRunning {
                pomodoroDidReachZero = true
            }
            return
        }

        sendPomodoroReminderIfNeeded(remainingSeconds: seconds)
    }

    private func handlePomodoroStateChange(_ state: TimerState) {
        let previousState = lastPomodoroState ?? .idle

        switch state {
        case .running:
            if previousState == .idle {
                pomodoroDidReachZero = false
                pomodoroReminderSent = false
                currentFocusDurationSeconds = durationConfig.workDuration
                refreshDailyStatsForCurrentDay()
            }
            if previousState == .breakRunning || previousState == .breakPaused {
                currentFocusDurationSeconds = durationConfig.workDuration
            }
        case .breakRunning:
            if previousState == .running || previousState == .paused {
                if pomodoroDidReachZero {
                    sendPomodoroCompletionNotification()
                    showTransitionPopup(message: transitionMessageForBreakStart())
                    logFocusSessionIfNeeded()
                    advanceExecutionPlanAfterCompletedSession()
                }
                pomodoroDidReachZero = false
            }

            if previousState != .breakPaused {
                pomodoroReminderSent = false
                currentBreakDurationSeconds = breakDurationSeconds(for: pomodoro.currentMode)
            }
            lastBreakMode = pomodoro.currentMode
        case .idle:
            if previousState == .running || previousState == .paused {
                if !pomodoroDidReachZero {
                    logFocusSessionIfNeeded(completed: false, interruptionCount: 1)
                }
            }
            if previousState == .breakRunning || previousState == .breakPaused {
                if pomodoroDidReachZero {
                    sendBreakCompletionNotification()
                    logBreakSessionIfNeeded(completed: true)
                } else {
                    logBreakSessionIfNeeded(completed: false, interruptionCount: 1)
                }
                pomodoroDidReachZero = false
            }
            currentBreakDurationSeconds = nil
            currentFocusDurationSeconds = nil
        case .paused, .breakPaused:
            break
        }

        lastPomodoroState = state
    }

    private func advanceExecutionPlanAfterCompletedSession() {
        guard let current = activeExecutionEntry else { return }
        let remainingPomodoros = max(0, (currentPlanPomodoros ?? current.pomodoros) - 1)

        if remainingPomodoros > 0 {
            currentPlanPomodoros = remainingPomodoros
            return
        }

        if let next = pendingExecutionQueue.first {
            pendingExecutionQueue.removeFirst()
            activeExecutionEntry = next
            applyExecutionPreset(next.pomodoroPresetID)
            applyPlan(title: next.title, pomodoroCount: next.pomodoros, pomodoroPresetID: next.pomodoroPresetID)
            return
        }

        clearExecutionPlan()
        pomodoro.skipBreak()
    }

    private func applyExecutionPreset(_ presetID: String?) {
        guard let preset = Preset.matching(id: presetID) else { return }
        presetSelection = .preset(preset)
        durationConfig = preset.durationConfig
    }

    private func handleCountdownRemaining(_ seconds: Int) {
        if seconds == 0 {
            if countdown.state == .running {
                countdownDidReachZero = true
            }
            return
        }

        sendCountdownReminderIfNeeded(remainingSeconds: seconds)
    }

    private func handleCountdownStateChange(_ state: TimerState) {
        let previousState = lastCountdownState ?? .idle

        switch state {
        case .running:
            if previousState == .idle {
                countdownDidReachZero = false
                countdownReminderSent = false
            }
        case .idle:
            if previousState == .running || previousState == .paused {
                if countdownDidReachZero {
                    sendCountdownCompletionNotification()
                }
                countdownDidReachZero = false
            }
        case .paused, .breakRunning, .breakPaused:
            break
        }

        lastCountdownState = state
    }

    private func sendPomodoroReminderIfNeeded(remainingSeconds: Int) {
        let l10n = LocalizationManager.shared
        let reminderLeadTime = reminderPreference.leadTimeSeconds
        guard reminderLeadTime > 0, !pomodoroReminderSent else { return }
        guard remainingSeconds == reminderLeadTime else { return }
        guard pomodoro.state == .running || pomodoro.state == .breakRunning else { return }

        let title = pomodoro.currentMode == .work
            ? l10n.text("notification.pomodoro_ending_soon")
            : l10n.text("notification.break_ending_soon")
        let body = l10n.text("notification.one_minute_remaining")
        sendNotification(title: title, body: body)
        pomodoroReminderSent = true
    }

    private func sendCountdownReminderIfNeeded(remainingSeconds: Int) {
        let l10n = LocalizationManager.shared
        let reminderLeadTime = reminderPreference.leadTimeSeconds
        guard reminderLeadTime > 0, !countdownReminderSent else { return }
        guard remainingSeconds == reminderLeadTime else { return }
        guard countdown.state == .running else { return }

        sendNotification(
            title: l10n.text("notification.countdown_ending_soon"),
            body: l10n.text("notification.one_minute_remaining")
        )
        countdownReminderSent = true
    }

    private func sendPomodoroCompletionNotification() {
        let l10n = LocalizationManager.shared
        sendNotification(
            title: decoratedTitle(l10n.text("notification.focus_complete"), emoji: "🍅"),
            body: l10n.text("notification.time_for_break")
        )
    }

    private func sendBreakCompletionNotification() {
        let l10n = LocalizationManager.shared
        let title: String
        switch lastBreakMode {
        case .longBreak:
            title = decoratedTitle(l10n.text("notification.long_break_complete"), emoji: "☕️")
        case .break:
            title = decoratedTitle(l10n.text("notification.break_complete"), emoji: "☕️")
        case .work, .idle, nil:
            title = decoratedTitle(l10n.text("notification.break_complete"), emoji: "☕️")
        }
        sendNotification(title: title, body: l10n.text("notification.ready_to_focus_again"))
    }

    private func sendCountdownCompletionNotification() {
        let l10n = LocalizationManager.shared
        sendNotification(
            title: decoratedTitle(l10n.text("notification.countdown_complete"), emoji: "⏳"),
            body: l10n.text("notification.time_is_up")
        )
    }

    private func decoratedTitle(_ title: String, emoji: String?) -> String {
        guard let emoji else { return title }
        return "\(emoji) \(title)"
    }

    private func transitionMessageForBreakStart() -> String {
        let l10n = LocalizationManager.shared
        switch pomodoro.currentMode {
        case .longBreak:
            return l10n.text("transition.long_break_starting")
        case .break:
            return l10n.text("transition.break_starting")
        case .work, .idle:
            return l10n.text("transition.break_starting")
        }
    }

    private func showTransitionPopup(message: String) {
        let popup = TransitionPopup(id: UUID(), message: message)
        DispatchQueue.main.async {
            self.transitionPopup = popup
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            guard self.transitionPopup?.id == popup.id else { return }
            self.transitionPopup = nil
        }
    }

    private func sendNotification(title: String, body: String) {
        guard notificationPreference != .off else { return }
        if notificationDeliveryStyle == .inApp {
            showNotificationPopup(title: title, body: body)
            return
        }

        notificationCenter.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if self.notificationPreference == .sound {
                content.sound = .default
            }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: trigger
            )
            self.notificationCenter.add(request)
        }
    }

    private func showNotificationPopup(title: String, body: String) {
        let popup = NotificationPopup(id: UUID(), title: title, body: body)
        DispatchQueue.main.async {
            self.notificationPopup = popup
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self else { return }
            guard self.notificationPopup?.id == popup.id else { return }
            self.notificationPopup = nil
        }
    }

    private func refreshDailyStatsForCurrentDay() {
        updateDailyStats { stats in
            stats.ensureCurrentDay()
        }
    }

    private func logFocusSessionIfNeeded(completed: Bool = true, interruptionCount: Int? = nil) {
        let durationSeconds = elapsedPomodoroSessionDurationSeconds(
            plannedDurationSeconds: currentFocusDurationSeconds,
            remainingSeconds: pomodoro.remainingSeconds,
            completed: completed
        )
        guard durationSeconds > 0 else { return }
        let endTime = Date()
        let startTime = endTime.addingTimeInterval(TimeInterval(-durationSeconds))
        updateDailyStats { stats in
            stats.logFocusSession(durationSeconds: durationSeconds, completed: completed)
        }
        // Local-only session record to power insights; no server or cloud dependency.
        appendSessionRecord(
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSeconds,
            taskId: nil,
            sessionType: .focus,
            completed: completed,
            interruptionCount: interruptionCount
        )
    }

    private func logBreakSessionIfNeeded(completed: Bool = true, interruptionCount: Int? = nil) {
        let durationSeconds = elapsedPomodoroSessionDurationSeconds(
            plannedDurationSeconds: currentBreakDurationSeconds,
            remainingSeconds: pomodoro.remainingSeconds,
            completed: completed
        )
        guard durationSeconds > 0 else { return }
        let endTime = Date()
        let startTime = endTime.addingTimeInterval(TimeInterval(-durationSeconds))
        updateDailyStats { stats in
            stats.logBreakSession(durationSeconds: durationSeconds, completed: completed)
        }
        appendSessionRecord(
            startTime: startTime,
            endTime: endTime,
            durationSeconds: durationSeconds,
            taskId: nil,
            sessionType: .break,
            completed: completed,
            interruptionCount: interruptionCount
        )
    }

    private func appendSessionRecord(
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        taskId: UUID?,
        sessionType: SessionType,
        completed: Bool,
        interruptionCount: Int?
    ) {
        Task { @MainActor in
            SessionRecordStore.shared.appendRecord(
                startTime: startTime,
                endTime: endTime,
                durationSeconds: durationSeconds,
                taskId: taskId,
                sessionType: sessionType,
                completed: completed,
                interruptionCount: interruptionCount
            )
        }
    }

    private func elapsedPomodoroSessionDurationSeconds(
        plannedDurationSeconds: Int?,
        remainingSeconds: Int,
        completed: Bool
    ) -> Int {
        guard let plannedDurationSeconds, plannedDurationSeconds > 0 else { return 0 }
        if completed {
            return plannedDurationSeconds
        }
        return max(0, plannedDurationSeconds - max(0, remainingSeconds))
    }

    private func updateDailyStats(_ update: (inout DailyStats) -> Void) {
        var updatedStats = dailyStats
        update(&updatedStats)
        dailyStats = updatedStats
        saveDailyStats(updatedStats)
    }

    private func breakDurationSeconds(for mode: PomodoroTimerEngine.CurrentMode) -> Int? {
        switch mode {
        case .break:
            return durationConfig.shortBreakDuration
        case .longBreak:
            return durationConfig.longBreakDuration
        case .work, .idle:
            return nil
        }
    }
}

extension AppState {
    struct TransitionPopup: Identifiable, Equatable {
        let id: UUID
        let message: String
    }

    struct NotificationPopup: Identifiable, Equatable {
        let id: UUID
        let title: String
        let body: String
    }
}

//
//  MainWindowView.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import EventKit
import SwiftUI
import UserNotifications
import Charts
import FirebaseFunctions

@MainActor
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var musicController: MusicController
    @EnvironmentObject private var audioSourceStore: AudioSourceStore
    @EnvironmentObject private var languageManager: LanguageManager
    @EnvironmentObject private var appTypography: AppTypography
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var flowWindowManager: FlowWindowManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var featureGate = FeatureGate.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @State private var workMinutesText = ""
    @State private var shortBreakMinutesText = ""
    @State private var longBreakMinutesText = ""
    @State private var countdownMinutesText = ""
    @State private var countdownSecondsText = ""
    @State private var dashboardPresetSelection: PresetSelection = .preset(Preset.shortestBuiltIn)
    @State private var dashboardWorkMinutes: Int = 25
    @State private var dashboardShortBreakMinutes: Int = 5
    @State private var dashboardLongBreakMinutes: Int = 15
    @State private var dashboardLongBreakInterval: Int = 4
    @FocusState private var focusedField: DurationField?
    @State private var longBreakIntervalValue: Int = 4
    @State private var sidebarSelection: SidebarItem = .dashboard
    @State private var pomodoroStatePulse = false
    @State private var countdownStatePulse = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    @State private var remindersStatus: EKAuthorizationStatus = .notDetermined
    @ObservedObject private var productivityAnalyticsStore = ProductivityAnalyticsStore.shared
    @State private var weeklyFocusPoints: [DailyFocusPoint] = []
    @State private var dailyCompletionPoints: [DailyFocusPoint] = []
    @State private var focusByHourPoints: [FocusHourPoint] = []
    @State private var sessionLengthDistributionPoints: [SessionLengthDistributionPoint] = []
    @State private var todayFocusMinutes: Int = 0
    @State private var completionRate: Double = 0
    @State private var summarySnapshot: ProductivityAnalyticsSnapshot?
    private let eventStore = SharedEventStore.shared.eventStore
    @State private var lastNonFlowSelection: SidebarItem = .dashboard
    // Slider micro-interactions
    @State private var ambientSliderEditing = false
    @State private var ambientSliderHover = false
    @State private var systemSliderHover = false
    @State private var isCheckingPlans = false
    @State private var plansPaywallContext: SubscriptionPaywallContext?
    @State private var plansErrorMessage: String?
    @State private var showPlansModePicker = false
    @State private var availablePlanModes: [YourPlansMode] = []
    @State private var showPlanTaskPicker = false
    @State private var selectablePlannedTaskEntries: [AppState.PlanExecutionEntry] = []
    @State private var insightHubResult: AIService.ProductivityInsightResult?
    @State private var isInsightHubLoading = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedSettingsPane: SettingsPane = .general
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @State private var settingsSearchText = ""
    @State private var showSettingsPlansSheet = false
    
    // New: Calendar, Reminders, and Todo system
    @StateObject private var permissionsManager = PermissionsManager.shared
    @StateObject private var todoStore = TodoStore()
    @StateObject private var planningStore = PlanningStore()
    @StateObject private var remindersSync = RemindersSync(permissionsManager: PermissionsManager.shared)
    @StateObject private var calendarManager = CalendarManager(permissionsManager: PermissionsManager.shared)

    private enum YourPlansMode: String, Identifiable {
        case plannedTasks
        case todayCalendarPlan

        var id: String { rawValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            MainInterfaceBackground()
            navigationShell
            popupOverlay
        }
        .sheet(item: $plansPaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: subscriptionStore
            )
        }
        .sheet(isPresented: $showSettingsPlansSheet) {
            SettingsPlansSheet(
                featureGate: featureGate,
                subscriptionStore: subscriptionStore
            )
        }
        .sheet(isPresented: $showPlanTaskPicker) {
            PlanTaskSelectionSheet(
                entries: selectablePlannedTaskEntries,
                onSelect: { entry in
                    startPlannedTaskExecution(with: entry)
                }
            )
        }
        .alert("Your Plans", isPresented: Binding(
            get: { plansErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    plansErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                plansErrorMessage = nil
            }
        } message: {
            Text(plansErrorMessage ?? "")
        }
        .confirmationDialog("Your Plans", isPresented: $showPlansModePicker, titleVisibility: .visible) {
            if availablePlanModes.contains(.plannedTasks) {
                Button("Run Planned Tasks") {
                    runYourPlans(.plannedTasks)
                }
            }
            if availablePlanModes.contains(.todayCalendarPlan) {
                Button("Run Today's Schedule") {
                    runYourPlans(.todayCalendarPlan)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose which AI-generated plan to run.")
        }
        .animation(reduceMotion ? .linear(duration: 0.2) : .easeInOut(duration: 0.25),
                   value: appState.transitionPopup?.id)
        .animation(reduceMotion ? .linear(duration: 0.2) : .easeInOut(duration: 0.25),
                   value: appState.notificationPopup?.id)
    }

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            ForEach(SidebarItem.visibleItems) { item in
                Label(languageManager.text(item.localizationKey), systemImage: item.systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .safeAreaPadding(.top, 10)
    }

    private var detailView: some View {
        ZStack {
            switch sidebarSelection {
            case .dashboard:
                dashboardView
            case .workspace:
                workspaceView
            case .tasks:
                tasksView
            case .calendar:
                calendarView
            case .insights:
                insightsView
            case .settings:
                settingsView
            case .flow:
                flowModeView
            }
        }
        .id(sidebarSelection)
        .transition(sectionTransition)
        .animation(sectionTransitionAnimation, value: sidebarSelection)
        .background(Color.clear)
    }

    private var pomodoroView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(titleForPomodoroMode(appState.pomodoroMode))
                    .font(.system(.headline, design: .default))
                    .foregroundStyle(.secondary)
                Text(formattedTime(appState.pomodoro.remainingSeconds))
                    .font(.system(size: 72, weight: .heavy, design: .default).monospacedDigit())
                    .scaleEffect(pomodoroStatePulse ? 1.0 : 0.98)
                    .opacity(pomodoroStatePulse ? 1.0 : 0.94)
                    .contentTransition(.numericText())
                    // Flow-mode-inspired gentle tick dissolve to keep time feeling fluid.
                    .animation(mainTimerUpdateAnimation, value: appState.pomodoro.remainingSeconds)
                    .animation(timerStateAnimation, value: pomodoroStatePulse)
                Text(languageManager.format("timer.state_format", labelForPomodoroState(appState.pomodoro.state)))
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(languageManager.text("timer.preset"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                Picker(languageManager.text("timer.preset"), selection: presetSelectionBinding) {
                    ForEach(Preset.builtIn) { preset in
                        Text(preset.name)
                            .tag(PresetSelection.preset(preset))
                    }
                    Text(languageManager.text("timer.custom"))
                        .tag(PresetSelection.custom)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(languageManager.text("timer.durations"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                DurationInputRow(
                    title: languageManager.text("timer.work"),
                    text: $workMinutesText,
                    field: .work,
                    focusedField: $focusedField,
                    isFocused: focusedField == .work
                ) {
                    commitDuration(.work)
                }

                DurationInputRow(
                    title: languageManager.text("timer.short_break"),
                    text: $shortBreakMinutesText,
                    field: .shortBreak,
                    focusedField: $focusedField,
                    isFocused: focusedField == .shortBreak
                ) {
                    commitDuration(.shortBreak)
                }

                DurationInputRow(
                    title: languageManager.text("timer.long_break"),
                    text: $longBreakMinutesText,
                    field: .longBreak,
                    focusedField: $focusedField,
                    isFocused: focusedField == .longBreak
                ) {
                    commitDuration(.longBreak)
                }

                LongBreakIntervalRow(
                    interval: $longBreakIntervalValue
                ) {
                    updateDurationConfig(longBreakInterval: longBreakIntervalValue)
                }
            }

            HStack(spacing: 10) {
                let actions = pomodoroActions(for: appState.pomodoro.state)
                ActionButton(languageManager.text("common.start"), isEnabled: actions.canStart) {
                    appState.pomodoro.start()
                }
                ActionButton(languageManager.text("common.pause"), isEnabled: actions.canPause) {
                    appState.pomodoro.pause()
                }
                ActionButton(languageManager.text("common.resume"), isEnabled: actions.canResume) {
                    appState.pomodoro.resume()
                }
                ActionButton(languageManager.text("common.reset")) {
                    appState.pomodoro.reset()
                }
                ActionButton(languageManager.text("timer.skip_break"), isEnabled: actions.canSkipBreak) {
                    appState.pomodoro.skipBreak()
                }
                Button {
                    Task {
                        await checkSubscription()
                    }
                } label: {
                    if isCheckingPlans {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Your Plans")
                        }
                    } else {
                        Text("Your Plans")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCheckingPlans)
            }

            if let planTitle = appState.currentPlanTitle,
               let pomodoroCount = appState.currentPlanPomodoros {
                Text("\(planTitle) • \(pomodoroCount) Pomodoros")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 28)
        .padding(.horizontal)
        .padding(.bottom)
        .frame(minWidth: 360, alignment: .leading)
    }

    private var dashboardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeaderView(
                    title: "Dashboard",
                    subtitle: "Your timer, daily progress, and focus controls in one place."
                )

                GlassCardView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(titleForPomodoroMode(appState.pomodoroMode))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text(formattedTime(appState.pomodoro.remainingSeconds))
                                    .font(.system(size: 68, weight: .heavy, design: .rounded).monospacedDigit())
                                    .contentTransition(.numericText())
                                Text(languageManager.format("timer.state_format", labelForPomodoroState(appState.pomodoro.state)))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 10) {
                                Button {
                                    Task {
                                        await checkSubscription()
                                    }
                                } label: {
                                    if isCheckingPlans {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Your Plans")
                                        }
                                    } else {
                                        Text("Your Plans")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isCheckingPlans)
                            }
                        }

                        HStack(spacing: 10) {
                            let actions = pomodoroActions(for: appState.pomodoro.state)
                            ActionButton(languageManager.text("common.start"), isEnabled: actions.canStart) {
                                startDashboardPomodoro()
                            }
                            ActionButton(languageManager.text("common.pause"), isEnabled: actions.canPause) {
                                appState.pomodoro.pause()
                            }
                            ActionButton(languageManager.text("common.resume"), isEnabled: actions.canResume) {
                                appState.pomodoro.resume()
                            }
                            ActionButton(languageManager.text("common.reset")) {
                                appState.resetPomodoro()
                                previewDashboardPomodoroIfIdle()
                            }
                            ActionButton(languageManager.text("timer.skip_break"), isEnabled: actions.canSkipBreak) {
                                appState.pomodoro.skipBreak()
                            }
                        }

                        dashboardPomodoroConfigurationPanel
                    }
                }

                AdaptiveMetricGrid {
                    MetricCard(
                        title: languageManager.text("summary.today_focus"),
                        value: languageManager.format("summary.today_focus_minutes_short", todayFocusMinutes),
                        caption: "\(weeklyFocusPoints.reduce(0) { $0 + $1.minutes }) min this week"
                    )
                    MetricCard(
                        title: languageManager.text("summary.completion"),
                        value: "\(Int((completionRate * 100).rounded()))%",
                        caption: "Task completion"
                    )
                    MetricCard(
                        title: "Sessions",
                        value: "\(summarySnapshot?.dailyAggregates.reduce(0) { $0 + $1.totalSessions } ?? 0)",
                        caption: "Tracked in analytics",
                        tint: .green
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    DashboardPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeaderView(
                                title: languageManager.text("timer.countdown"),
                                subtitle: "Keep a simple deadline visible and adjustable without leaving the dashboard."
                            )
                            Text(formattedTime(appState.countdown.remainingSeconds))
                                .font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                            countdownConfigurationPanel
                            countdownActionsRow
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }

                    DashboardPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeaderView(
                                title: "Audio",
                                subtitle: "Ambient sound and now-playing controls stay available here."
                            )
                            nowPlayingSection
                            Divider()
                            sourceSelector
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            refreshSummaryMetrics()
        }
        .onChange(of: todoStore.items) { _, _ in
            refreshSummaryMetrics()
        }
        .onChange(of: productivityAnalyticsStore.dailyAggregates) { _, _ in
            refreshSummaryMetrics()
        }
    }

    private var navigationShell: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        .onAppear {
            syncDurationTexts()
            syncLongBreakInterval()
            syncDashboardPomodoroSessionDefaults()
            todoStore.attachPlanningStore(planningStore)
            remindersSync.setTodoStore(todoStore)
        }
        .onChange(of: appState.durationConfig) { _, _ in
            syncDurationTexts()
            syncLongBreakInterval()
            syncDashboardPomodoroSessionDefaults()
        }
        .onChange(of: sidebarSelection) { oldValue, newValue in
            if newValue == .flow {
                if oldValue != .flow {
                    lastNonFlowSelection = oldValue
                }
            } else {
                lastNonFlowSelection = newValue
            }

            if newValue == .settings {
                Task { @MainActor in
                    await featureGate.refreshSubscriptionStatusIfNeeded()
                }
            }

            if newValue == .dashboard || newValue == .insights {
                refreshSummaryMetrics()
            }
        }
        .onChange(of: focusedField) { _, newValue in
            guard newValue == nil else { return }
            commitDuration(.work)
            commitDuration(.shortBreak)
            commitDuration(.longBreak)
            commitDuration(.countdown)
            commitDuration(.countdownSeconds)
        }
        .onChange(of: appState.pomodoro.state) { oldValue, newValue in
            triggerPomodoroStateAnimation(from: oldValue, to: newValue)
        }
        .onChange(of: appState.countdown.state) { oldValue, newValue in
            triggerCountdownStateAnimation(from: oldValue, to: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToFlow)) { _ in
            withAnimation {
                splitViewVisibility = .all
                sidebarSelection = .flow
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPomodoro)) { _ in
            withAnimation {
                splitViewVisibility = .all
                sidebarSelection = .dashboard
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCountdown)) { _ in
            withAnimation {
                splitViewVisibility = .all
                sidebarSelection = .dashboard
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTasks)) { _ in
            withAnimation {
                splitViewVisibility = .all
                sidebarSelection = .tasks
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToCalendar)) { _ in
            withAnimation {
                splitViewVisibility = .all
                sidebarSelection = .calendar
            }
        }
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.2)) {
            splitViewVisibility = splitViewVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    @ViewBuilder
    private var popupOverlay: some View {
        if appState.transitionPopup != nil || appState.notificationPopup != nil {
            VStack(spacing: 8) {
                if let popup = appState.transitionPopup {
                    TransitionPopupView(message: popup.message)
                }
                if let popup = appState.notificationPopup {
                    InAppNotificationView(title: popup.title, message: popup.body)
                }
            }
            .padding(.top, 12)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            .allowsHitTesting(false)
        }
    }

    private var flowModeView: some View {
        FlowModeView(
            showsBackgroundLayer: false,
            isFullscreenPresentation: false,
            exitAction: {
                withAnimation {
                    sidebarSelection = lastNonFlowSelection
                }
            }
        )
    }

    private var countdownView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(languageManager.text("timer.countdown"))
                    .font(.system(.headline, design: .default))
                    .foregroundStyle(.secondary)
                Text(formattedTime(appState.countdown.remainingSeconds))
                    .font(.system(size: 72, weight: .heavy, design: .default).monospacedDigit())
                    .scaleEffect(countdownStatePulse ? 1.0 : 0.98)
                    .opacity(countdownStatePulse ? 1.0 : 0.94)
                    .contentTransition(.numericText())
                    .animation(mainTimerUpdateAnimation, value: appState.countdown.remainingSeconds)
                    .animation(timerStateAnimation, value: countdownStatePulse)
                Text(languageManager.format("timer.state_format", labelForPomodoroState(appState.countdown.state)))
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(languageManager.text("timer.duration"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                DurationInputRow(
                    title: languageManager.text("timer.countdown"),
                    text: $countdownMinutesText,
                    field: .countdown,
                    focusedField: $focusedField,
                    isFocused: focusedField == .countdown
                ) {
                    commitDuration(.countdown)
                }
            }

            HStack(spacing: 10) {
                let actions = countdownActions(for: appState.countdown.state)
                ActionButton(languageManager.text("common.start"), isEnabled: actions.canStart) {
                    appState.countdown.start()
                }
                ActionButton(languageManager.text("common.pause"), isEnabled: actions.canPause) {
                    appState.countdown.pause()
                }
                ActionButton(languageManager.text("common.resume"), isEnabled: actions.canResume) {
                    appState.countdown.resume()
                }
                ActionButton(languageManager.text("common.reset")) {
                    appState.countdown.reset()
                }
            }
        }
        .padding(.top, 28)
        .padding(.horizontal)
        .padding(.bottom)
        .frame(minWidth: 360, alignment: .leading)
    }
    
    private var tasksView: some View {
        TodoListView(
            todoStore: todoStore,
            planningStore: planningStore,
            remindersSync: remindersSync,
            permissionsManager: permissionsManager
        )
    }

    private var calendarView: some View {
        CalendarView(
            calendarManager: calendarManager,
            permissionsManager: permissionsManager,
            todoStore: todoStore,
            planningStore: planningStore
        )
    }

    private var audioAndMusicView: some View {
        VStack(alignment: .leading, spacing: 16) {
            nowPlayingSection
            Divider()
                .padding(.vertical, 4)
            sourceSelector
        }
        .padding(.top, 28)
        .padding(.horizontal)
        .padding(.bottom)
        .frame(minWidth: 360, alignment: .leading)
    }

    private var insightsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeaderView(
                    title: "Insights",
                    subtitle: "A single place for analytics and guided AI assistance."
                )

                GlassCardView {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(
                            title: languageManager.text("main.summary.title"),
                            subtitle: "Baseline performance signals and longer-term trends."
                        )
                        summarySection
                        summaryFocusTiles
                    }
                }

                if hasInsightContent {
                    GlassCardView {
                        insightsAIQuickActions
                    }
                } else {
                    GlassCardView {
                        insightEmptyStateCallToAction
                    }
                }

                AdaptivePageGrid {
                    GlassCardView {
                        weeklyFocusChart
                    }
                    GlassCardView { dailyCompletionTrendChart }
                    GlassCardView { focusBreakRatioCard }
                    GlassCardView { focusByHourChart }
                    GlassCardView { sessionLengthDistributionChart }
                    GlassCardView { completionSection }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            refreshSummaryMetrics()
        }
        .onChange(of: todoStore.items) { _, _ in
            refreshSummaryMetrics()
        }
        .onChange(of: productivityAnalyticsStore.dailyAggregates) { _, _ in
            refreshSummaryMetrics()
        }
    }

    private var workspaceView: some View {
        VStack(spacing: 14) {
            Text("Workspace Coming soon")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Your future thinking workspace is coming.")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(currentAppearanceMode.secondaryTextColor(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var aiWorkspaceSection: some View {
        AdaptivePageGrid(minimumWidth: 260) {
            AIActionCard(
                icon: "list.bullet.rectangle.portrait",
                title: "Task AI",
                description: "Break down work, draft task details, and build focused plans without scattering AI actions across the app."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Includes task breakdown, task planning, and description generation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Tasks") {
                        withAnimation {
                            sidebarSelection = .tasks
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            AIActionCard(
                icon: "calendar.badge.clock",
                title: "Schedule AI",
                description: "Use one scheduling surface for calendar-based planning and rescheduling instead of separate scattered entry points."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Includes calendar scheduling and rescheduling.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Calendar") {
                        withAnimation {
                            sidebarSelection = .calendar
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            AIActionCard(
                icon: "waveform.and.magnifyingglass",
                title: "Insight AI",
                description: "Generate weekly overviews, deeper analysis, and metric-level explanations from your local productivity data."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let insightHubResult {
                        TaskMarkdownView(markdown: insightHubResult.text, lineLimit: 4)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Includes weekly overview, deep analysis, and metric explanations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    insightAIButtons
                }
            }
        }
    }

    private var insightsAIQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Insight AI")
                        .font(.headline)
                    Text("Run analysis here, or open Workspace for the full AI toolset.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    insightAIButtons

                    Button("Open Workspace") {
                        withAnimation {
                            sidebarSelection = .workspace
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let insightHubResult {
                TaskMarkdownView(markdown: insightHubResult.text)
                    .font(.subheadline)
                    .foregroundStyle(currentAppearanceMode.secondaryTextColor(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .appRoundedSurface(
                        mode: currentAppearanceMode,
                        cornerRadius: 12,
                        glassMaterial: .thinMaterial,
                        standardLevel: .inset,
                        showsShadow: false
                    )
            }
        }
    }

    private var insightEmptyStateCallToAction: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(currentAppearanceMode.secondaryTextColor(for: colorScheme))
                .frame(width: 36, height: 36)
                .appRoundedSurface(
                    mode: currentAppearanceMode,
                    cornerRadius: 12,
                    glassMaterial: .thinMaterial,
                    standardLevel: .inset,
                    showsShadow: false
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("Come back after a little more focus")
                    .font(.headline)
                Text("Start a focus session or add a few tasks first. Once you have some activity here, Insight AI will be ready with overviews and analysis.")
                    .font(.subheadline)
                    .foregroundStyle(currentAppearanceMode.secondaryTextColor(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Start Focusing") {
                withAnimation {
                    sidebarSelection = .dashboard
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var insightAIButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await runInsightWeeklyOverview()
                }
            } label: {
                if isInsightHubLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Generate Overview")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isInsightHubLoading)

            Button("Run Deep Analysis") {
                Task {
                    await runInsightDeepAnalysis()
                }
            }
            .buttonStyle(.bordered)
            .disabled(isInsightHubLoading)

            Menu("Explain Metric") {
                ForEach([
                    AIService.ProductivityInsightMetric.focusQualityScore,
                    .consistencyScore,
                    .focusByHour,
                    .breakFocusRatio
                ], id: \.rawValue) { metric in
                    Button(metric.displayName) {
                        Task {
                            await runInsightMetricAnalysis(metric)
                        }
                    }
                }
            }
            .disabled(isInsightHubLoading)
        }
    }

    private var settingsView: some View {
        HStack(alignment: .top, spacing: 24) {
            settingsSidebar

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeaderView(
                        title: selectedSettingsPane.title,
                        subtitle: selectedSettingsPane.subtitle
                    )

                    settingsPaneContent
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 24)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshPermissionStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Notifications") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openCalendarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openRemindersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }

    private func handleNotificationAccessRequest() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    Task { @MainActor in
                        refreshPermissionStatuses()
                    }
                }
            }
            Task { @MainActor in
                openNotificationSettings()
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Search Settings", text: $settingsSearchText)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(filteredSettingsPanes) { pane in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedSettingsPane = pane
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: pane.systemImage)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pane.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(pane.shortDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedSettingsPane == pane ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedSettingsPane == pane ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 250)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .appRoundedSurface(
            mode: currentAppearanceMode,
            cornerRadius: 18,
            glassMaterial: .regularMaterial,
            standardLevel: .panel,
            showsShadow: currentAppearanceMode == .standard
        )
    }

    @ViewBuilder
    private var settingsPaneContent: some View {
        switch selectedSettingsPane {
        case .general:
            AdaptivePageGrid(minimumWidth: 360, spacing: 20) {
                settingsGeneralModule
                settingsAppearanceModule
            }
        case .timerFocus:
            AdaptivePageGrid(minimumWidth: 360, spacing: 20) {
                settingsTimerPresetModule
                settingsTimerDurationsModule
                settingsCountdownModule
            }
        case .notifications:
            AdaptivePageGrid(minimumWidth: 360, spacing: 20) {
                settingsNotificationPreferencesModule
                settingsPermissionsModule
            }
        case .aiFeatures:
            AdaptivePageGrid(minimumWidth: 360, spacing: 20) {
                settingsAISubscriptionModule
                settingsAIFeaturesModule
            }
        case .account:
            AdaptivePageGrid(minimumWidth: 360, spacing: 20) {
                settingsAccountModule
                settingsPoliciesModule
            }
        }
    }

    private var settingsGeneralModule: some View {
        SettingsModuleCard(
            title: "General",
            description: "Core app behavior and defaults that affect everyday use."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                settingsLabeledControl(title: "Language", description: "Choose how the app should present text.") {
                    Picker(languageManager.text("settings.language.picker.label"), selection: $languageManager.currentLanguage) {
                        Text(languageManager.text("settings.language.system"))
                            .tag(LanguageManager.AppLanguage.auto)
                        Text(languageManager.text("settings.language.english"))
                            .tag(LanguageManager.AppLanguage.english)
                        Text(languageManager.text("settings.language.chinese"))
                            .tag(LanguageManager.AppLanguage.chinese)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }

                settingsLabeledControl(
                    title: languageManager.text("settings.onboarding.title"),
                    description: languageManager.text("settings.onboarding.description")
                ) {
                    Button(languageManager.text("settings.onboarding.reopen")) {
                        onboardingState.reopen()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var settingsAppearanceModule: some View {
        SettingsModuleCard(
            title: "Appearance",
            description: "Keep the interface clean, readable, and consistent with macOS."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                settingsLabeledControl(
                    title: languageManager.text("settings.appearance.font.title"),
                    description: languageManager.text("settings.appearance.font.description")
                ) {
                    Picker(languageManager.text("settings.appearance.font.title"), selection: $appTypography.style) {
                        ForEach(AppTypography.Style.allCases) { style in
                            Text(style.title(using: languageManager)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }

                Divider()

                settingsLabeledControl(
                    title: languageManager.text("settings.appearance.mode.title"),
                    description: languageManager.text("settings.appearance.mode.description")
                ) {
                    Picker(languageManager.text("settings.appearance.mode.title"), selection: appearanceModeSelection) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(title(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                settingsInfoRow(title: "Style", value: "System materials and native controls")
                settingsInfoRow(title: "Layout", value: "Adaptive modules that expand with window size")
            }
        }
    }

    private var appearanceModeSelection: Binding<AppearanceMode> {
        Binding(
            get: {
                currentAppearanceMode
            },
            set: { newValue in
                appearanceModeRawValue = newValue.rawValue
            }
        )
    }

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode.resolved(from: appearanceModeRawValue)
    }

    private func title(for mode: AppearanceMode) -> String {
        switch mode {
        case .glass:
            return languageManager.text("settings.appearance.mode.glass")
        case .standard:
            return languageManager.text("settings.appearance.mode.standard")
        }
    }

    private var settingsTimerPresetModule: some View {
        SettingsModuleCard(
            title: "Timer & Focus",
            description: "Set the default Pomodoro rhythm used when the dashboard is not overriding the current session."
        ) {
            settingsLabeledControl(title: languageManager.text("timer.preset"), description: "Switch between built-in focus presets or a custom schedule.") {
                Picker(languageManager.text("timer.preset"), selection: presetSelectionBinding) {
                    ForEach(Preset.builtIn) { preset in
                        Text(preset.name)
                            .tag(PresetSelection.preset(preset))
                    }
                    Text(languageManager.text("timer.custom"))
                        .tag(PresetSelection.custom)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var settingsTimerDurationsModule: some View {
        SettingsModuleCard(
            title: "Pomodoro Durations",
            description: "Adjust the default work and break lengths saved for the app."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                DurationInputRow(
                    title: languageManager.text("timer.work"),
                    text: $workMinutesText,
                    field: .work,
                    focusedField: $focusedField,
                    isFocused: focusedField == .work
                ) {
                    commitDuration(.work)
                }

                Divider()

                DurationInputRow(
                    title: languageManager.text("timer.short_break"),
                    text: $shortBreakMinutesText,
                    field: .shortBreak,
                    focusedField: $focusedField,
                    isFocused: focusedField == .shortBreak
                ) {
                    commitDuration(.shortBreak)
                }

                Divider()

                DurationInputRow(
                    title: languageManager.text("timer.long_break"),
                    text: $longBreakMinutesText,
                    field: .longBreak,
                    focusedField: $focusedField,
                    isFocused: focusedField == .longBreak
                ) {
                    commitDuration(.longBreak)
                }

                Divider()

                LongBreakIntervalRow(
                    interval: $longBreakIntervalValue
                ) {
                    updateDurationConfig(longBreakInterval: longBreakIntervalValue)
                }
            }
        }
    }

    private var settingsCountdownModule: some View {
        SettingsModuleCard(
            title: "Countdown Default",
            description: "Set the default countdown used across the app, with quick preset shortcuts."
        ) {
            countdownConfigurationPanel
        }
    }

    private var settingsNotificationPreferencesModule: some View {
        SettingsModuleCard(
            title: "Notifications",
            description: "Choose how reminders are delivered and when the app should surface them."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                settingsLabeledControl(title: languageManager.text("main.delivery"), description: "Decide how timer alerts should reach you.") {
                    Picker(languageManager.text("main.delivery"), selection: $appState.notificationDeliveryStyle) {
                        ForEach(NotificationDeliveryStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                settingsLabeledControl(title: languageManager.text("settings.notifications.title"), description: "Control whether focus notifications are shown.") {
                    Picker(languageManager.text("settings.notifications.title"), selection: $appState.notificationPreference) {
                        ForEach(NotificationPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                settingsLabeledControl(title: languageManager.text("main.reminder"), description: "Choose how reminder follow-ups should behave.") {
                    Picker(languageManager.text("main.reminder"), selection: $appState.reminderPreference) {
                        ForEach(ReminderPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var settingsPermissionsModule: some View {
        SettingsModuleCard(
            title: "Permissions & Sync",
            description: "Review system access for notifications, calendar, and reminders."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                settingsPermissionRow(
                    title: "Notifications",
                    status: notificationStatusText(notificationStatus),
                    statusColor: notificationStatusColor(notificationStatus),
                    buttonTitle: notificationStatus == .authorized ? "Open Settings" : "Enable",
                    action: handleNotificationAccessRequest
                )

                Divider()

                settingsPermissionRow(
                    title: "Calendar",
                    status: eventStatusText(calendarStatus),
                    statusColor: eventStatusColor(calendarStatus),
                    buttonTitle: eventStatusColor(calendarStatus) == .green ? "Open Settings" : "Enable",
                    action: handleCalendarAccessRequest
                )

                Divider()

                settingsPermissionRow(
                    title: "Reminders",
                    status: eventStatusText(remindersStatus),
                    statusColor: eventStatusColor(remindersStatus),
                    buttonTitle: eventStatusColor(remindersStatus) == .green ? "Open Settings" : "Enable",
                    action: handleRemindersAccessRequest
                )
            }
        }
    }

    private var settingsAISubscriptionModule: some View {
        SettingsModuleCard(
            title: "AI & Subscription",
            description: "Review your current plan, usage window, and restore purchases when needed."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                settingsInfoRow(title: "Current Plan", value: currentPlanLabel)

                if let resetAt = featureGate.allowanceResetAt {
                    settingsInfoRow(title: "Usage Resets", value: formattedSettingsDate(resetAt))
                }

                if let subscriptionEndAt = featureGate.subscriptionEndAt,
                   featureGate.tier == .plus || featureGate.tier == .pro {
                    settingsInfoRow(title: "Subscription Ends", value: formattedSettingsDate(subscriptionEndAt))
                }

                if subscriptionStore.isServerVerificationPending {
                    Text("App Store subscription found. Server verification is still required before AI and premium server features unlock.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        await subscriptionStore.restorePurchases()
                    }
                } label: {
                    if subscriptionStore.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restore & Sync Subscription")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(subscriptionStore.isRestoring)

                Button("Manage Subscription") {
                    showSettingsPlansSheet = true
                }
                .buttonStyle(.borderedProminent)

                if let errorMessage = subscriptionStore.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let productLoadErrorMessage = subscriptionStore.productLoadErrorMessage,
                   !productLoadErrorMessage.isEmpty {
                    Text(productLoadErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var settingsAIFeaturesModule: some View {
        SettingsModuleCard(
            title: "AI Access & Features",
            description: "See what your tier unlocks, then open the subscription sheet when you need full plan details."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if !featureGate.aiUsageProgressItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(featureGate.aiUsageProgressItems, id: \.title) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(item.usedPercentage)% used")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: item.usedRatio)
                                    .tint(usageColor(for: item.usedRatio))
                            }
                        }
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plan Comparison")
                            .font(.subheadline.weight(.semibold))
                        Text("Open the subscription pop-up to compare Free, Plus, and Pro in detail.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Compare Plans") {
                        showSettingsPlansSheet = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var settingsAccountModule: some View {
        SettingsModuleCard(
            title: "Account",
            description: "Manage sign-in state and cloud-connected access from one place."
        ) {
            CloudSettingsSection()
                .environmentObject(authViewModel)
                .environmentObject(LocalizationManager.shared)
        }
    }

    private var settingsPoliciesModule: some View {
        SettingsModuleCard(
            title: "Privacy & Policies",
            description: "Open the product policy page in your browser."
        ) {
            Button {
                guard let url = URL(string: "https://orchestrana.app/policies.html") else {
                    return
                }
                NSWorkspace.shared.open(url)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text("Open Privacy & Policies")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
        }
    }

    private func settingsLabeledControl<Content: View>(
        title: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
        }
    }

    private func settingsPermissionRow(
        title: String,
        status: String,
        statusColor: Color,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
        }
    }

    private func usageColor(for ratio: Double) -> Color {
        switch ratio {
        case ..<0.6:
            return .accentColor
        case ..<0.8:
            return .yellow
        default:
            return .red
        }
    }

    private var filteredSettingsPanes: [SettingsPane] {
        let query = settingsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return SettingsPane.allCases
        }
        let filtered = SettingsPane.allCases.filter { pane in
            pane.title.lowercased().contains(query)
                || pane.shortDescription.lowercased().contains(query)
        }
        return filtered.isEmpty ? SettingsPane.allCases : filtered
    }

    private var currentPlanLabel: String {
        switch featureGate.tier {
        case .free:
            return "Free"
        case .plus:
            return "Plus"
        case .pro:
            return "Pro"
        case .developer:
            return "Developer"
        case .beta:
            return "Beta"
        case .expired:
            return "Expired"
        }
    }

    private func formattedSettingsDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    private func handleCalendarAccessRequest() {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarStatus = status
        if status == .notDetermined {
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { _, _ in
                    DispatchQueue.main.async {
                        refreshPermissionStatuses()
                    }
                }
            } else {
                eventStore.requestAccess(to: .event) { _, _ in
                    DispatchQueue.main.async {
                        refreshPermissionStatuses()
                    }
                }
            }
        }
        openCalendarSettings()
    }

    // MARK: - Audio UI

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(languageManager.text("audio.now_playing"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)

            if appState.nowPlayingRouter.isAvailable {
                HStack(alignment: .center, spacing: 14) {
                    externalArtwork(
                        ExternalMedia(
                            title: appState.nowPlayingRouter.title,
                            artist: appState.nowPlayingRouter.artist,
                            album: nil,
                            artwork: appState.nowPlayingRouter.artwork,
                            source: .unknown
                        )
                    )
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.nowPlayingRouter.title)
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Text(appState.nowPlayingRouter.artist)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(appState.nowPlayingRouter.sourceName)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 160, alignment: .leading)
                    .layoutPriority(1)

                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            appState.nowPlayingRouter.previousTrack()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!appState.nowPlayingRouter.isAvailable)

                        Button {
                            appState.nowPlayingRouter.playPause()
                        } label: {
                            Image(systemName: appState.nowPlayingRouter.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                        .disabled(!appState.nowPlayingRouter.isAvailable)

                        Button {
                            appState.nowPlayingRouter.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!appState.nowPlayingRouter.isAvailable)
                    }
                }
            } else {
                switch audioSourceStore.audioSource {
                case .ambient(let type):
                    HStack(alignment: .center, spacing: 14) {
                        ambientIcon(for: type)
                            .font(.system(size: 30, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(type.displayName)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                            Text(languageManager.text("audio.ambient_local"))
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 160, alignment: .leading)
                        .layoutPriority(1)

                        Spacer()

                        Button {
                            audioSourceStore.togglePlayPause()
                        } label: {
                            Image(systemName: musicController.playbackState == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageManager.text("audio.volume"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: ambientVolumeBinding, in: 0...1, onEditingChanged: { editing in
                                if reduceMotion {
                                    ambientSliderEditing = editing
                                } else {
                                    withAnimation(.easeOut(duration: 0.2)) { ambientSliderEditing = editing }
                                }
                            })
                            .controlSize(.small)
                            .frame(height: 24)
                            // Smooth fill animation to avoid abrupt jumps.
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: musicController.focusVolume)
                            // Tactile scale while dragging; small enough to avoid layout shift.
                            .scaleEffect(ambientSliderEditing ? 1.03 : 1.0, anchor: .center)
                            // Subtle hover lift in line with macOS controls.
                            .opacity((ambientSliderHover || ambientSliderEditing) ? 1.0 : 0.95)
                            .onHover { hovering in
                                if reduceMotion {
                                    ambientSliderHover = hovering
                                } else {
                                    withAnimation(.easeOut(duration: 0.18)) { ambientSliderHover = hovering }
                                }
                            }
                        }
                        .frame(width: 200)
                    }

                case .external(let media):
                    HStack(alignment: .center, spacing: 14) {
                        externalArtwork(media)
                            .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(media.title)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                            Text(media.artist)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(media.source.displayName)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 160, alignment: .leading)
                        .layoutPriority(1)

                        Spacer()

                        Button {
                            audioSourceStore.togglePlayPause()
                        } label: {
                            Image(systemName: "playpause.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.accentColor))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageManager.text("audio.volume.system"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: .constant(Double(musicController.focusVolume)), in: 0...1, onEditingChanged: { _ in })
                                .controlSize(.small)
                                .frame(height: 24)
                                .disabled(true)
                                // Soft hover feedback without altering layout or color palette.
                                .opacity(systemSliderHover ? 1.0 : 0.92)
                                .onHover { hovering in
                                    if reduceMotion {
                                        systemSliderHover = hovering
                                    } else {
                                        withAnimation(.easeOut(duration: 0.18)) { systemSliderHover = hovering }
                                    }
                                }
                        }
                        .frame(width: 200)
                    }

                case .off:
                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Image(systemName: "music.note")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("No media playing")
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .lineLimit(1)
                            Text(languageManager.text("audio.start_external_hint"))
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(minWidth: 160, alignment: .leading)
                        .layoutPriority(1)

                        Spacer()

                        HStack(spacing: 10) {
                            Image(systemName: "backward.fill")
                            Image(systemName: "play.fill")
                            Image(systemName: "forward.fill")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            appState.nowPlayingRouter.startPollingIfNeeded()
        }
    }

    private var sourceSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(languageManager.text("audio.source"))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                selectorButton(
                    title: languageManager.text("audio.source.external"),
                    isActive: externalActive,
                    isDisabled: !externalActive,
                    action: { }
                )

                ForEach(FocusSoundType.allCases.filter { $0 != .off }, id: \.self) { type in
                    selectorButton(
                        title: type.displayName,
                        isActive: currentAmbient == type,
                        isDisabled: externalActive,
                        action: { audioSourceStore.selectAmbient(type) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func selectorButton(title: String, isActive: Bool, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? Color.accentColor : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
    }

    private var countdownConfigurationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                countdownDurationField(
                    title: "Minutes",
                    text: $countdownMinutesText,
                    field: .countdown,
                    width: 72
                )

                countdownDurationField(
                    title: "Seconds",
                    text: $countdownSecondsText,
                    field: .countdownSeconds,
                    width: 72
                )

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ForEach([25, 50, 90], id: \.self) { preset in
                    Button("\(preset) min") {
                        applyCountdownPreset(minutes: preset)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var countdownActionsRow: some View {
        HStack(spacing: 10) {
            let actions = countdownActions(for: appState.countdown.state)
            ActionButton(languageManager.text("common.start"), isEnabled: actions.canStart) {
                appState.countdown.start()
            }
            ActionButton(languageManager.text("common.pause"), isEnabled: actions.canPause) {
                appState.countdown.pause()
            }
            ActionButton(languageManager.text("common.resume"), isEnabled: actions.canResume) {
                appState.countdown.resume()
            }
            ActionButton(languageManager.text("common.reset")) {
                appState.countdown.reset()
            }
        }
    }

    private func miniStatPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metricSummaryCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(currentAppearanceMode == .glass ? tint : tint.opacity(0.10))
        )
        .appRoundedSurface(
            mode: currentAppearanceMode,
            cornerRadius: 10,
            glassMaterial: .thinMaterial,
            standardLevel: .inset,
            showsShadow: false
        )
    }

    private func countdownDurationField(
        title: String,
        text: Binding<String>,
        field: DurationField,
        width: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .focused($focusedField, equals: field)
                .onSubmit {
                    commitDuration(field)
                }
        }
    }

    private var ambientVolumeBinding: Binding<Double> {
        Binding(
            get: { Double(musicController.focusVolume) },
            set: { newValue in
                audioSourceStore.setVolume(Float(newValue))
            }
        )
    }

    private var externalActive: Bool {
        if appState.nowPlayingRouter.isAvailable { return true }
        if case .external = audioSourceStore.audioSource { return true }
        return false
    }

    private var currentAmbient: FocusSoundType? {
        if case .ambient(let type) = audioSourceStore.audioSource {
            return type
        }
        return nil
    }

    @ViewBuilder
    private func externalArtwork(_ media: ExternalMedia) -> some View {
        if let artwork = media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                Image(systemName: "music.note")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ambientIcon(for type: FocusSoundType) -> Image {
        switch type {
        case .white, .off:
            return Image(systemName: "waveform")
        case .brown:
            return Image(systemName: "wind")
        case .rain:
            return Image(systemName: "cloud.rain")
        case .wind:
            return Image(systemName: "wind.circle")
        }
    }

    private func handleRemindersAccessRequest() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        remindersStatus = status
        if status == .notDetermined {
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToReminders { _, _ in
                    DispatchQueue.main.async {
                        refreshPermissionStatuses()
                    }
                }
            } else {
                eventStore.requestAccess(to: .reminder) { _, _ in
                    DispatchQueue.main.async {
                        refreshPermissionStatuses()
                    }
                }
            }
        }
        openRemindersSettings()
    }

    private func refreshPermissionStatuses() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    private func permissionStatusRow(title: String, statusText: String, statusColor: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text("\(title): \(statusText)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return languageManager.text("permission.not_determined")
        case .denied:
            return languageManager.text("permission.denied")
        case .authorized:
            return languageManager.text("permission.authorized")
        case .provisional:
            return languageManager.text("permission.provisional")
        case .ephemeral:
            return languageManager.text("permission.ephemeral")
        @unknown default:
            return languageManager.text("permission.unknown")
        }
    }

    private func notificationStatusColor(_ status: UNAuthorizationStatus) -> Color {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private func eventStatusText(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return languageManager.text("permission.not_determined")
        case .restricted:
            return languageManager.text("permission.restricted")
        case .denied:
            return languageManager.text("permission.denied")
        case .authorized:
            return languageManager.text("permission.authorized")
        case .fullAccess:
            return languageManager.text("permission.full_access")
        case .writeOnly:
            return languageManager.text("permission.write_only")
        @unknown default:
            return languageManager.text("permission.unknown")
        }
    }

    private func eventStatusColor(_ status: EKAuthorizationStatus) -> Color {
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private enum DurationField: Hashable {
        case work
        case shortBreak
        case longBreak
        case countdown
        case countdownSeconds
    }

    private enum SidebarItem: String, CaseIterable, Identifiable {
        case dashboard
        case workspace
        case tasks
        case calendar
        case insights
        case settings
        case flow

        var id: String { rawValue }

        static var visibleItems: [SidebarItem] {
            [.dashboard, .flow, .workspace, .tasks, .calendar, .insights, .settings]
        }

        var localizationKey: String {
            switch self {
            case .dashboard:
                return "main.sidebar.dashboard"
            case .workspace:
                return "main.sidebar.workspace"
            case .tasks:
                return "main.sidebar.tasks"
            case .calendar:
                return "main.sidebar.calendar"
            case .insights:
                return "main.sidebar.insights"
            case .settings:
                return "main.sidebar.settings"
            case .flow:
                return "main.sidebar.flow"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard:
                return "square.grid.2x2"
            case .workspace:
                return "sparkles.rectangle.stack"
            case .tasks:
                return "checklist"
            case .calendar:
                return "calendar"
            case .insights:
                return "chart.line.uptrend.xyaxis"
            case .settings:
                return "gearshape"
            case .flow:
                return "circle.dotted"
            }
        }

        var toolbarTitle: String {
            switch self {
            case .dashboard:
                return "Dashboard"
            case .workspace:
                return "Workspace"
            case .tasks:
                return "Tasks"
            case .calendar:
                return "Calendar"
            case .insights:
                return "Insights"
            case .settings:
                return "Settings"
            case .flow:
                return "Flow Mode"
            }
        }

        var toolbarSubtitle: String {
            switch self {
            case .dashboard:
                return "Focus, timers, and today at a glance"
            case .workspace:
                return "Planning, scheduling, and AI assistance"
            case .tasks:
                return "Capture, organize, and plan work"
            case .calendar:
                return "See your schedule and reschedule intelligently"
            case .insights:
                return "Analytics and AI understanding"
            case .settings:
                return "Preferences, access, and customization"
            case .flow:
                return "Immersive focus workspace"
            }
        }
    }

    private enum SettingsPane: String, CaseIterable, Identifiable {
        case general
        case timerFocus
        case notifications
        case aiFeatures
        case account

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:
                return "General"
            case .timerFocus:
                return "Timer & Focus"
            case .notifications:
                return "Notifications"
            case .aiFeatures:
                return "AI & Features"
            case .account:
                return "Account"
            }
        }

        var subtitle: String {
            switch self {
            case .general:
                return "App-wide defaults, language, and baseline behavior."
            case .timerFocus:
                return "Presets, durations, and countdown defaults for focused work."
            case .notifications:
                return "Delivery preferences and system permissions."
            case .aiFeatures:
                return "Plans, quota visibility, and AI feature access."
            case .account:
                return "Sign-in state, cloud access, and policy links."
            }
        }

        var shortDescription: String {
            switch self {
            case .general:
                return "Defaults and language"
            case .timerFocus:
                return "Presets and durations"
            case .notifications:
                return "Alerts and permissions"
            case .aiFeatures:
                return "Plans and AI"
            case .account:
                return "Profile and cloud"
            }
        }

        var systemImage: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .timerFocus:
                return "timer"
            case .notifications:
                return "bell.badge"
            case .aiFeatures:
                return "sparkles"
            case .account:
                return "person.crop.circle"
            }
        }
    }

    private struct DurationInputRow: View {
        @EnvironmentObject private var languageManager: LanguageManager
        let title: String
        @Binding var text: String
        let field: DurationField
        let focusedField: FocusState<DurationField?>.Binding
        let isFocused: Bool
        let onCommit: () -> Void

        var body: some View {
            HStack {
                Text(title)
                    .font(.system(.body, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    TextField("", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .focused(focusedField, equals: field)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                        .onSubmit {
                            onCommit()
                        }
                    Text(languageManager.text("common.min_short"))
                        .foregroundStyle(.secondary)
                        .font(.system(.callout, design: .rounded))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(languageManager.format("timer.accessibility.minutes_label", title))
            .accessibilityHint(languageManager.text("timer.accessibility.minutes_hint"))
        }
    }

    private struct TransitionPopupView: View {
        @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
        let message: String

        var body: some View {
            let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .appRoundedSurface(
                    mode: appearanceMode,
                    cornerRadius: 999,
                    glassMaterial: .ultraThinMaterial,
                    standardLevel: .overlay
                )
        }
    }

    private struct InAppNotificationView: View {
        @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
        @Environment(\.colorScheme) private var colorScheme
        let title: String
        let message: String

        var body: some View {
            let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(appearanceMode.secondaryTextColor(for: colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .appRoundedSurface(
                mode: appearanceMode,
                cornerRadius: 12,
                glassMaterial: .ultraThinMaterial,
                standardLevel: .overlay
            )
        }
    }

    private struct LongBreakIntervalRow: View {
        @EnvironmentObject private var languageManager: LanguageManager
        @Binding var interval: Int
        let onCommit: () -> Void

        var body: some View {
            HStack {
                Text(languageManager.text("timer.long_break_interval"))
                    .font(.system(.body, design: .rounded))
                Spacer()
                Stepper(value: $interval, in: 1...12) {
                    Text(languageManager.format("timer.long_break_interval.every_sessions", interval))
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .onChange(of: interval) { _, _ in
                    onCommit()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(languageManager.text("timer.long_break_interval"))
            .accessibilityHint(languageManager.text("timer.long_break_interval.hint"))
        }
    }

    private struct ActionButton: View {
        let title: String
        let isEnabled: Bool
        let action: () -> Void
        @State private var isHovering = false
        @GestureState private var isPressing = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
            self.title = title
            self.isEnabled = isEnabled
            self.action = action
        }

        var body: some View {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1.0 : 0.45)
                .scaleEffect(pressScale)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering && isEnabled ? Color.accentColor.opacity(0.08) : .clear)
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isPressing)
                .onHover { hovering in
                    isHovering = hovering
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressing) { _, state, _ in state = true }
                )
        }

        private var pressScale: CGFloat {
            guard isEnabled, !reduceMotion else { return 1.0 }
            return isPressing ? 0.98 : 1.0
        }
    }

    private struct SummaryRow: View {
        let title: String
        let value: String

        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .font(.system(.body, design: .rounded).monospacedDigit())
            }
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let minutes = clampedSeconds / 60
        let remaining = clampedSeconds % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let hours = clampedSeconds / 3600
        let minutes = (clampedSeconds % 3600) / 60
        if hours > 0 {
            return languageManager.format("duration.hours_minutes", hours, minutes)
        }
        return languageManager.format("duration.minutes", minutes)
    }

    private enum SummaryState {
        case empty
        case stats(DailyStats)
    }

    private var summaryState: SummaryState {
        let stats = appState.dailyStats
        if stats.completedSessions == 0 && stats.totalFocusSeconds == 0 && stats.totalBreakSeconds == 0 {
            return .empty
        }
        return .stats(stats)
    }

    private var summarySection: some View {
        Group {
            switch summaryState {
            case .empty:
                Text(languageManager.text("summary.no_sessions_today"))
                    .foregroundStyle(.secondary)
                    .font(.system(.subheadline, design: .rounded))
            case .stats(let stats):
                VStack(alignment: .leading, spacing: 6) {
                    SummaryRow(title: languageManager.text("summary.focus_time"), value: formattedDuration(stats.totalFocusSeconds))
                    SummaryRow(title: languageManager.text("summary.break_time"), value: formattedDuration(stats.totalBreakSeconds))
                    SummaryRow(title: languageManager.text("summary.sessions"), value: "\(stats.completedSessions)")
                }
            }
        }
    }

    private var summaryFocusTiles: some View {
        AdaptiveMetricGrid {
            miniStatPill(
                title: languageManager.text("summary.today_focus"),
                value: languageManager.format("summary.today_focus_minutes_short", todayFocusMinutes)
            )
            miniStatPill(
                title: languageManager.text("summary.completion"),
                value: "\(Int(completionRate * 100))%"
            )
        }
    }
    
    private var weeklyFocusChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            summarySectionHeader(title: languageManager.text("summary.weekly_trend"))
            if weeklyFocusPoints.allSatisfy({ $0.minutes == 0 }) {
                emptyChartCard(message: "Insights will appear after you have data.")
            } else {
                let maxMinutes = weeklyFocusPoints.map(\.minutes).max() ?? 0
                let minMinutes = weeklyFocusPoints.map(\.minutes).min() ?? 0
                Chart(weeklyFocusPoints) { point in
                    LineMark(
                        x: .value(languageManager.text("summary.chart.day"), shortWeekdayFormatter.string(from: point.date)),
                        y: .value(languageManager.text("summary.chart.minutes"), point.minutes)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor)

                    AreaMark(
                        x: .value(languageManager.text("summary.chart.day"), shortWeekdayFormatter.string(from: point.date)),
                        y: .value(languageManager.text("summary.chart.minutes"), point.minutes)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.accentColor.opacity(0.12))

                    if point.minutes == maxMinutes || point.minutes == minMinutes {
                        PointMark(
                            x: .value(languageManager.text("summary.chart.day"), shortWeekdayFormatter.string(from: point.date)),
                            y: .value(languageManager.text("summary.chart.minutes"), point.minutes)
                        )
                        .symbolSize(60)
                        .foregroundStyle(point.minutes == maxMinutes ? Color.green : Color.orange)
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var dailyCompletionTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            summarySectionHeader(title: "Daily Completion Trend")
            if dailyCompletionPoints.allSatisfy({ $0.minutes == 0 }) {
                emptyChartCard(message: "Insights will appear after you have data.")
            } else {
                Chart(dailyCompletionPoints) { point in
                    BarMark(
                        x: .value("Day", shortWeekdayFormatter.string(from: point.date)),
                        y: .value("Completed Sessions", point.minutes)
                    )
                    .foregroundStyle(Color.green.gradient)
                }
                .frame(height: 160)
            }
        }
    }

    private var focusBreakRatioCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            summarySectionHeader(title: "Focus vs Break Ratio")
            if let snapshot = summarySnapshot,
               snapshot.dailyAggregates.contains(where: { $0.totalFocusSeconds > 0 || $0.totalBreakSeconds > 0 }) {
                HStack(spacing: 20) {
                    Chart {
                        SectorMark(
                            angle: .value("Focus", focusRatioValue.focus),
                            innerRadius: .ratio(0.58),
                            angularInset: 2
                        )
                        .foregroundStyle(Color.accentColor.gradient)

                        SectorMark(
                            angle: .value("Break", focusRatioValue.breakTime),
                            innerRadius: .ratio(0.58),
                            angularInset: 2
                        )
                        .foregroundStyle(Color.orange.gradient)
                    }
                    .frame(width: 160, height: 160)

                    VStack(alignment: .leading, spacing: 8) {
                        ratioLegendRow(color: .accentColor, title: "Focus", value: "\(focusRatioPercent.focus)%")
                        ratioLegendRow(color: .orange, title: "Break", value: "\(focusRatioPercent.breakTime)%")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                emptyChartCard(message: "Insights will appear after you have data.")
            }
        }
    }

    private var focusByHourChart: some View {
        return VStack(alignment: .leading, spacing: 8) {
            summarySectionHeader(title: "Focus by Hour")
            if focusByHourPoints.contains(where: { $0.focusSeconds > 0 }) {
                Chart(focusByHourPoints) { point in
                    BarMark(
                        x: .value("Hour", point.hour),
                        y: .value("Minutes", point.focusSeconds / 60)
                    )
                    .foregroundStyle(Color.cyan.gradient)
                }
                .frame(height: 180)
            } else {
                emptyChartCard(message: "Insights will appear after you have data.")
            }
        }
    }

    private var sessionLengthDistributionChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            summarySectionHeader(title: "Session Length Distribution")
            if sessionLengthDistributionPoints.contains(where: { $0.sessionCount > 0 }) {
                Chart(sessionLengthDistributionPoints) { point in
                    BarMark(
                        x: .value("Bucket", point.bucket.title),
                        y: .value("Sessions", point.sessionCount)
                    )
                    .foregroundStyle(Color.pink.gradient)
                }
                .frame(height: 180)
            } else {
                emptyChartCard(message: "Insights will appear after you have data.")
            }
        }
    }

    private func emptyChartCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(currentAppearanceMode.secondaryTextColor(for: colorScheme))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .appRoundedSurface(
                    mode: currentAppearanceMode,
                    cornerRadius: 10,
                    glassMaterial: .thinMaterial,
                    standardLevel: .inset,
                    showsShadow: false
                )
        }
    }
    
    private var completionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            summarySectionHeader(title: languageManager.text("summary.task_completion"))
            
            if todoStore.items.isEmpty {
                emptyChartCard(message: "Insights will appear after you have data.")
            } else {
                let completedCount = todoStore.items.filter { $0.isCompleted }.count
                let total = todoStore.items.count
                let activeCount = max(0, total - completedCount)
                let progressValue = total == 0 ? 0 : Double(completedCount) / Double(total)
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(completedCount)/\(total) completed")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(Int((progressValue * 100).rounded()))%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progressValue)
                            .progressViewStyle(.linear)
                            .tint(.green)
                    }
                    .padding()
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(10)

                    AdaptiveMetricGrid {
                        metricSummaryCard(
                            title: languageManager.text("summary.completion_overview"),
                            value: languageManager.format("summary.completed_count", completedCount),
                            tint: Color.green.opacity(0.08)
                        )
                        metricSummaryCard(
                            title: languageManager.text("summary.current_load"),
                            value: languageManager.format("summary.active_count", activeCount),
                            tint: Color.cyan.opacity(0.08)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summarySectionHeader(title: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var shortWeekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        formatter.locale = languageManager.effectiveLocale
        return formatter
    }

    private var focusRatioValue: (focus: Int, breakTime: Int) {
        let focusSeconds = summarySnapshot?.dailyAggregates.reduce(0) { $0 + $1.totalFocusSeconds } ?? 0
        let breakSeconds = summarySnapshot?.dailyAggregates.reduce(0) { $0 + $1.totalBreakSeconds } ?? 0
        if focusSeconds == 0 && breakSeconds == 0 {
            return (focus: 1, breakTime: 1)
        }
        return (focus: max(0, focusSeconds), breakTime: max(0, breakSeconds))
    }

    private var focusRatioPercent: (focus: Int, breakTime: Int) {
        let ratio = focusRatioValue
        let total = max(1, ratio.focus + ratio.breakTime)
        let focus = Int((Double(ratio.focus) / Double(total) * 100).rounded())
        return (focus: focus, breakTime: max(0, 100 - focus))
    }

    private func ratioLegendRow(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private func refreshSummaryMetrics() {
        let calendar = Calendar.current
        let snapshot: ProductivityAnalyticsSnapshot
        let todayAggregate: DailyProductivityAggregate

        if shouldUseMockInsights {
            snapshot = developerMockInsightsSnapshot(calendar: calendar)
            todayAggregate = developerMockTodayAggregate(calendar: calendar)
        } else {
            snapshot = productivityAnalyticsStore.snapshot(calendar: calendar)
            todayAggregate = productivityAnalyticsStore.aggregate(for: Date(), calendar: calendar)
        }

        summarySnapshot = snapshot
        todayFocusMinutes = todayAggregate.totalFocusSeconds / 60

        weeklyFocusPoints = snapshot.focusTrend7Days.map { point in
            DailyFocusPoint(date: point.date, minutes: Int(point.value.rounded()))
        }
        let aggregateLookup = Dictionary(uniqueKeysWithValues: snapshot.dailyAggregates.map { ($0.dayStart, $0) })
        let today = calendar.startOfDay(for: Date())
        dailyCompletionPoints = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -(6 - offset), to: today)
        }.map { day in
            DailyFocusPoint(
                date: day,
                minutes: aggregateLookup[day]?.completedSessions ?? 0
            )
        }
        focusByHourPoints = snapshot.focusByHour
        sessionLengthDistributionPoints = snapshot.sessionLengthDistribution

        if shouldUseMockInsights {
            completionRate = snapshot.insights.completionRate
        } else {
            let totalTasks = todoStore.items.count
            let completed = todoStore.items.filter { $0.isCompleted }.count
            completionRate = totalTasks == 0 ? 0 : Double(completed) / Double(totalTasks)
        }
    }

    private var shouldUseMockInsights: Bool {
        featureGate.tier == .developer && sidebarSelection == .insights
    }

    private func developerMockTodayAggregate(calendar: Calendar) -> DailyProductivityAggregate {
        let today = calendar.startOfDay(for: Date())
        return developerMockInsightsSnapshot(calendar: calendar).dailyAggregates.first(where: {
            calendar.isDate($0.dayStart, inSameDayAs: today)
        }) ?? DailyProductivityAggregate(dayStart: today)
    }

    private func developerMockInsightsSnapshot(calendar: Calendar) -> ProductivityAnalyticsSnapshot {
        let today = calendar.startOfDay(for: Date())
        let mockDays: [(offset: Int, focusMinutes: Int, breakMinutes: Int, sessions: Int, completed: Int)] = [
            (-6, 92, 18, 4, 3),
            (-5, 138, 24, 5, 4),
            (-4, 74, 12, 3, 2),
            (-3, 164, 28, 6, 5),
            (-2, 126, 22, 5, 4),
            (-1, 151, 26, 6, 5),
            (0, 118, 20, 4, 4)
        ]

        let dailyAggregates = mockDays.compactMap { entry -> DailyProductivityAggregate? in
            guard let date = calendar.date(byAdding: .day, value: entry.offset, to: today) else { return nil }
            return developerMockAggregate(
                dayStart: date,
                focusMinutes: entry.focusMinutes,
                breakMinutes: entry.breakMinutes,
                totalSessions: entry.sessions,
                completedSessions: entry.completed
            )
        }

        let focusTrend7Days = dailyAggregates.map {
            ProductivityTrendPoint(date: $0.dayStart, value: Double($0.totalFocusSeconds / 60))
        }

        let focusTrend30Days: [ProductivityTrendPoint] = (0..<30).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: -(29 - index), to: today) else { return nil }
            let waveform = sin(Double(index) * 0.55) * 28
            let baseline = 104.0 + waveform + Double((index % 4) * 6)
            return ProductivityTrendPoint(date: date, value: max(48, baseline))
        }

        let focusByHour: [FocusHourPoint] = [
            FocusHourPoint(hour: 7, focusSeconds: 0, sessionCount: 0),
            FocusHourPoint(hour: 8, focusSeconds: 2_400, sessionCount: 1),
            FocusHourPoint(hour: 9, focusSeconds: 6_300, sessionCount: 2),
            FocusHourPoint(hour: 10, focusSeconds: 8_400, sessionCount: 3),
            FocusHourPoint(hour: 11, focusSeconds: 5_100, sessionCount: 2),
            FocusHourPoint(hour: 12, focusSeconds: 1_800, sessionCount: 1),
            FocusHourPoint(hour: 13, focusSeconds: 3_600, sessionCount: 1),
            FocusHourPoint(hour: 14, focusSeconds: 7_200, sessionCount: 3),
            FocusHourPoint(hour: 15, focusSeconds: 6_000, sessionCount: 2),
            FocusHourPoint(hour: 16, focusSeconds: 4_500, sessionCount: 2),
            FocusHourPoint(hour: 17, focusSeconds: 2_100, sessionCount: 1),
            FocusHourPoint(hour: 18, focusSeconds: 0, sessionCount: 0)
        ]

        let sessionLengthDistribution: [SessionLengthDistributionPoint] = [
            SessionLengthDistributionPoint(bucket: .under15, sessionCount: 2),
            SessionLengthDistributionPoint(bucket: .between15And25, sessionCount: 8),
            SessionLengthDistributionPoint(bucket: .between25And45, sessionCount: 12),
            SessionLengthDistributionPoint(bucket: .over45, sessionCount: 5)
        ]

        let insights = ProductivityInsights(
            streakDays: 6,
            completionRate: 0.82,
            focusQualityScore: 84,
            shortSessionRatio: 0.12,
            consistencyScore: 78,
            breakFocusRatio: 0.18,
            averageSessionLengthSeconds: 31 * 60,
            longestSessionSeconds: 58 * 60
        )

        return ProductivityAnalyticsSnapshot(
            dailyAggregates: dailyAggregates,
            focusTrend7Days: focusTrend7Days,
            focusTrend30Days: focusTrend30Days,
            focusByHour: focusByHour,
            sessionLengthDistribution: sessionLengthDistribution,
            insights: insights
        )
    }

    private func developerMockAggregate(
        dayStart: Date,
        focusMinutes: Int,
        breakMinutes: Int,
        totalSessions: Int,
        completedSessions: Int
    ) -> DailyProductivityAggregate {
        DailyProductivityAggregate(
            dayStart: dayStart,
            totalFocusSeconds: focusMinutes * 60,
            totalBreakSeconds: breakMinutes * 60,
            totalSessions: totalSessions,
            completedSessions: completedSessions,
            totalSessionSeconds: (focusMinutes + breakMinutes) * 60,
            longestSessionSeconds: max(25 * 60, (focusMinutes * 60) / max(1, totalSessions)),
            totalInterruptions: 2,
            shortSessions: max(0, totalSessions / 4),
            focusSessions: totalSessions,
            breakSessions: max(1, totalSessions / 2),
            focusByHour: developerMockFocusByHour(for: focusMinutes),
            sessionLengthBuckets: developerMockSessionBuckets(for: totalSessions)
        )
    }

    private func developerMockFocusByHour(for focusMinutes: Int) -> [Int] {
        var values = Array(repeating: 0, count: 24)
        values[9] = focusMinutes * 18
        values[10] = focusMinutes * 16
        values[14] = focusMinutes * 14
        values[15] = focusMinutes * 12
        return values
    }

    private func developerMockSessionBuckets(for totalSessions: Int) -> [Int] {
        [
            max(1, totalSessions / 5),
            max(1, totalSessions / 3),
            max(1, totalSessions / 2),
            max(0, totalSessions / 4)
        ]
    }

    private var summaryTaskSummary: AIService.ProductivityTaskSummary {
        AIService.ProductivityTaskSummary.from(items: todoStore.items)
    }

    private var hasInsightContent: Bool {
        let hasAnalyticsData =
            weeklyFocusPoints.contains(where: { $0.minutes > 0 }) ||
            dailyCompletionPoints.contains(where: { $0.minutes > 0 }) ||
            focusByHourPoints.contains(where: { $0.focusSeconds > 0 }) ||
            sessionLengthDistributionPoints.contains(where: { $0.sessionCount > 0 }) ||
            (summarySnapshot?.dailyAggregates.contains(where: { $0.totalFocusSeconds > 0 || $0.totalBreakSeconds > 0 }) ?? false)
        return hasAnalyticsData || !todoStore.items.isEmpty
    }

    private func ensureInsightAIUnlocked(requiredTier: PlanTier = .plus) -> Bool {
        switch featureGate.tier {
        case .free, .expired:
            plansPaywallContext = SubscriptionPaywallContext(
                requiredTier: requiredTier,
                title: "Unlock AI Workspace",
                message: "Upgrade to Plus or Pro to use task, schedule, and insight AI from the new workspace."
            )
            return false
        case .plus, .beta:
            if requiredTier == .pro {
                plansPaywallContext = SubscriptionPaywallContext(
                    requiredTier: .pro,
                    title: "Unlock Deeper Insight AI",
                    message: "Deep analysis is available in Pro."
                )
                return false
            }
            return true
        case .pro, .developer:
            return true
        }
    }

    private func runInsightWeeklyOverview() async {
        await featureGate.refreshSubscriptionStatusIfNeeded()
        let snapshot = summarySnapshot ?? productivityAnalyticsStore.snapshot(calendar: .current)
        guard ensureInsightAIUnlocked(requiredTier: .plus) else { return }
        isInsightHubLoading = true
        let result = await AIService.shared.generateWeeklyOverview(
            snapshot: snapshot,
            taskSummary: summaryTaskSummary
        )
        insightHubResult = result
        isInsightHubLoading = false
    }

    private func runInsightDeepAnalysis() async {
        await featureGate.refreshSubscriptionStatusIfNeeded()
        let snapshot = summarySnapshot ?? productivityAnalyticsStore.snapshot(calendar: .current)
        guard ensureInsightAIUnlocked(requiredTier: .pro) else { return }
        isInsightHubLoading = true
        let result = await AIService.shared.generateDeepAnalysis(
            snapshot: snapshot,
            taskSummary: summaryTaskSummary
        )
        insightHubResult = result
        isInsightHubLoading = false
    }

    private func runInsightMetricAnalysis(_ metric: AIService.ProductivityInsightMetric) async {
        await featureGate.refreshSubscriptionStatusIfNeeded()
        let snapshot = summarySnapshot ?? productivityAnalyticsStore.snapshot(calendar: .current)
        guard ensureInsightAIUnlocked(requiredTier: .plus) else { return }
        isInsightHubLoading = true
        let metricResult = await AIService.shared.analyzeMetric(
            metric,
            snapshot: snapshot,
            taskSummary: summaryTaskSummary
        )
        insightHubResult = metricResult
        isInsightHubLoading = false
    }

    private func labelForPomodoroState(_ state: TimerState) -> String {
        switch state {
        case .idle:
            return languageManager.text("timer.state.idle")
        case .running:
            return languageManager.text("timer.state.running")
        case .paused:
            return languageManager.text("timer.state.paused")
        case .breakRunning:
            return languageManager.text("timer.state.break_running")
        case .breakPaused:
            return languageManager.text("timer.state.break_paused")
        }
    }

    private func titleForPomodoroMode(_ mode: PomodoroTimerEngine.Mode) -> String {
        switch mode {
        case .work:
            return languageManager.text("timer.mode.pomodoro")
        case .breakTime:
            return languageManager.text("timer.mode.break")
        case .longBreak:
            return languageManager.text("timer.mode.long_break")
        }
    }

    private struct PomodoroActionAvailability {
        let canStart: Bool
        let canPause: Bool
        let canResume: Bool
        let canSkipBreak: Bool
    }

    private struct DailyFocusPoint: Identifiable {
        let id = UUID()
        let date: Date
        let minutes: Int
    }

    private struct CountdownActionAvailability {
        let canStart: Bool
        let canPause: Bool
        let canResume: Bool
    }

    private func pomodoroActions(for state: TimerState) -> PomodoroActionAvailability {
        switch state {
        case .idle:
            return PomodoroActionAvailability(
                canStart: true,
                canPause: false,
                canResume: false,
                canSkipBreak: false
            )
        case .running:
            return PomodoroActionAvailability(
                canStart: false,
                canPause: true,
                canResume: false,
                canSkipBreak: false
            )
        case .paused:
            return PomodoroActionAvailability(
                canStart: false,
                canPause: false,
                canResume: true,
                canSkipBreak: false
            )
        case .breakRunning:
            return PomodoroActionAvailability(
                canStart: false,
                canPause: true,
                canResume: false,
                canSkipBreak: true
            )
        case .breakPaused:
            return PomodoroActionAvailability(
                canStart: false,
                canPause: false,
                canResume: true,
                canSkipBreak: true
            )
        }
    }

    private func checkSubscription() async {
        isCheckingPlans = true
        defer { isCheckingPlans = false }

        if AuthViewModel.shared.isAuthenticated {
            await featureGate.refreshSubscriptionStatusIfNeeded()
        }

        guard featureGate.canUseAIPlanning else {
            plansPaywallContext = SubscriptionPaywallContext(
                requiredTier: .plus,
                title: "Your Plans requires Plus",
                message: "Upgrade to Plus or Pro to start Pomodoro sessions from your planned tasks."
            )
            return
        }

        let plannedEntries = plannedTaskEntries()
        let calendarEntries = todayCalendarPlanEntries()

        if plannedEntries.isEmpty && calendarEntries.isEmpty {
            plansErrorMessage = "No runnable AI plans found."
            return
        }

        if !plannedEntries.isEmpty && !calendarEntries.isEmpty {
            availablePlanModes = [.plannedTasks, .todayCalendarPlan]
            showPlansModePicker = true
            return
        }

        runYourPlans(plannedEntries.isEmpty ? .todayCalendarPlan : .plannedTasks)
    }

    private func runYourPlans(_ mode: YourPlansMode) {
        let entries: [AppState.PlanExecutionEntry]
        switch mode {
        case .plannedTasks:
            entries = plannedTaskEntries()
        case .todayCalendarPlan:
            entries = todayCalendarPlanEntries()
        }

        guard !entries.isEmpty else {
            plansErrorMessage = mode == .plannedTasks
                ? "No AI task plans available to run."
                : "No AI calendar plan found for today."
            return
        }

        showPlansModePicker = false
        availablePlanModes = []

        if mode == .plannedTasks {
            selectablePlannedTaskEntries = entries
            showPlanTaskPicker = true
            return
        }

        appState.startExecutionPlan(entries)
    }

    private func startPlannedTaskExecution(with selectedEntry: AppState.PlanExecutionEntry) {
        let reorderedEntries = [selectedEntry] + selectablePlannedTaskEntries.filter { $0.id != selectedEntry.id }
        selectablePlannedTaskEntries = []
        showPlanTaskPicker = false
        appState.startExecutionPlan(reorderedEntries)
    }

    private func plannedTaskEntries() -> [AppState.PlanExecutionEntry] {
        todoStore.pendingItems
            .filter { !$0.isCompleted && $0.aiOrigin == .planning }
            .sorted { left, right in
                let leftOrder = left.aiOrder ?? Int.max
                let rightOrder = right.aiOrder ?? Int.max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                if let leftDue = left.dueDate, let rightDue = right.dueDate, leftDue != rightDue {
                    return leftDue < rightDue
                }
                return left.createdAt < right.createdAt
            }
            .map { item in
                AppState.PlanExecutionEntry(
                    id: item.id,
                    title: item.title,
                    pomodoros: max(1, item.plannedPomodoroCount ?? item.pomodoroEstimate ?? 1),
                    pomodoroPresetID: item.pomodoroPresetID
                )
            }
    }

    private func todayCalendarPlanEntries() -> [AppState.PlanExecutionEntry] {
        let calendar = Calendar.current
        return todoStore.pendingItems
            .filter { item in
                guard !item.isCompleted,
                      item.aiOrigin == .calendarSchedule,
                      let dueDate = item.dueDate else {
                    return false
                }
                return calendar.isDateInToday(dueDate)
            }
            .sorted { ($0.dueDate ?? $0.createdAt) < ($1.dueDate ?? $1.createdAt) }
            .map { item in
                AppState.PlanExecutionEntry(
                    id: item.id,
                    title: item.title,
                    pomodoros: max(1, item.plannedPomodoroCount ?? item.pomodoroEstimate ?? 1),
                    pomodoroPresetID: item.pomodoroPresetID
                )
            }
    }

    private func countdownActions(for state: TimerState) -> CountdownActionAvailability {
        switch state {
        case .idle:
            return CountdownActionAvailability(canStart: true, canPause: false, canResume: false)
        case .running:
            return CountdownActionAvailability(canStart: false, canPause: true, canResume: false)
        case .paused:
            return CountdownActionAvailability(canStart: false, canPause: false, canResume: true)
        case .breakRunning, .breakPaused:
            return CountdownActionAvailability(canStart: false, canPause: false, canResume: false)
        }
    }

    private var workMinutesValue: Int {
        max(1, appState.durationConfig.workDuration / 60)
    }

    private var shortBreakMinutesValue: Int {
        max(1, appState.durationConfig.shortBreakDuration / 60)
    }

    private var longBreakMinutesValue: Int {
        max(1, appState.durationConfig.longBreakDuration / 60)
    }

    private var countdownMinutesValue: Int {
        max(0, appState.durationConfig.countdownDuration / 60)
    }

    private var countdownSecondsValue: Int {
        max(0, appState.durationConfig.countdownDuration % 60)
    }

    private func updateDurationConfig(
        workMinutes: Int? = nil,
        shortBreakMinutes: Int? = nil,
        longBreakMinutes: Int? = nil,
        longBreakInterval: Int? = nil,
        countdownMinutes: Int? = nil,
        countdownSeconds: Int? = nil
    ) {
        let currentConfig = appState.durationConfig
        let updatedWorkMinutes = clamp(workMinutes ?? currentConfig.workDuration / 60, range: 1...120)
        let updatedShortBreakMinutes = clamp(shortBreakMinutes ?? currentConfig.shortBreakDuration / 60, range: 1...60)
        let updatedLongBreakMinutes = clamp(longBreakMinutes ?? currentConfig.longBreakDuration / 60, range: 1...90)
        let updatedLongBreakInterval = clamp(longBreakInterval ?? currentConfig.longBreakInterval, range: 1...12)
        let currentCountdownDuration = max(60, currentConfig.countdownDuration)
        let updatedCountdownMinutes = clamp(countdownMinutes ?? currentCountdownDuration / 60, range: 0...120)
        let updatedCountdownSeconds = clamp(countdownSeconds ?? currentCountdownDuration % 60, range: 0...59)
        let resolvedCountdownDuration = max(60, updatedCountdownMinutes * 60 + updatedCountdownSeconds)

        appState.applyCustomDurationConfig(DurationConfig(
            workDuration: updatedWorkMinutes * 60,
            shortBreakDuration: updatedShortBreakMinutes * 60,
            longBreakDuration: updatedLongBreakMinutes * 60,
            longBreakInterval: updatedLongBreakInterval,
            countdownDuration: resolvedCountdownDuration
        ))
    }

    private var presetSelectionBinding: Binding<PresetSelection> {
        Binding(
            get: { appState.presetSelection },
            set: { appState.applyPresetSelection($0) }
        )
    }

    private var dashboardPomodoroConfigurationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            Text("Session Setup")
                .font(.headline)
                .foregroundStyle(.secondary)

            Picker(languageManager.text("timer.preset"), selection: dashboardPresetSelectionBinding) {
                ForEach(Preset.builtIn) { preset in
                    Text(preset.name)
                        .tag(PresetSelection.preset(preset))
                }
                Text(languageManager.text("timer.custom"))
                    .tag(PresetSelection.custom)
            }
            .pickerStyle(.segmented)

            dashboardDurationStepperRow(
                title: languageManager.text("timer.work"),
                value: $dashboardWorkMinutes,
                range: 1...120
            )
            dashboardDurationStepperRow(
                title: languageManager.text("timer.short_break"),
                value: $dashboardShortBreakMinutes,
                range: 1...60
            )
            dashboardDurationStepperRow(
                title: languageManager.text("timer.long_break"),
                value: $dashboardLongBreakMinutes,
                range: 1...90
            )

            HStack {
                Text(languageManager.text("timer.long_break_interval"))
                    .font(.system(.body, design: .rounded))
                Spacer()
                Stepper(value: $dashboardLongBreakInterval, in: 1...12) {
                    Text(languageManager.format("timer.long_break_interval.every_sessions", dashboardLongBreakInterval))
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("These controls affect the current dashboard session only. Change Settings to update the default Pomodoro setup.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: dashboardWorkMinutes) { _, _ in handleDashboardSessionEdit() }
        .onChange(of: dashboardShortBreakMinutes) { _, _ in handleDashboardSessionEdit() }
        .onChange(of: dashboardLongBreakMinutes) { _, _ in handleDashboardSessionEdit() }
        .onChange(of: dashboardLongBreakInterval) { _, _ in handleDashboardSessionEdit() }
    }

    private func dashboardDurationStepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(.body, design: .rounded))
            Spacer()
            Stepper(value: value, in: range) {
                Text(languageManager.format("tasks.pomodoro_estimate_value", value.wrappedValue).replacingOccurrences(of: " Pomodoros", with: " min").replacingOccurrences(of: " Pomodoro", with: " min"))
                    .font(.system(.body, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dashboardPresetSelectionBinding: Binding<PresetSelection> {
        Binding(
            get: { dashboardPresetSelection },
            set: { applyDashboardPresetSelection($0) }
        )
    }

    private var dashboardPomodoroDurationConfig: DurationConfig {
        DurationConfig(
            workDuration: dashboardWorkMinutes * 60,
            shortBreakDuration: dashboardShortBreakMinutes * 60,
            longBreakDuration: dashboardLongBreakMinutes * 60,
            longBreakInterval: dashboardLongBreakInterval,
            countdownDuration: appState.durationConfig.countdownDuration
        )
    }

    private func syncDashboardPomodoroSessionDefaults() {
        let config = appState.durationConfig
        dashboardWorkMinutes = max(1, config.workDuration / 60)
        dashboardShortBreakMinutes = max(1, config.shortBreakDuration / 60)
        dashboardLongBreakMinutes = max(1, config.longBreakDuration / 60)
        dashboardLongBreakInterval = clamp(config.longBreakInterval, range: 1...12)
        dashboardPresetSelection = PresetSelection.selection(for: config)
        previewDashboardPomodoroIfIdle()
    }

    private func applyDashboardPresetSelection(_ selection: PresetSelection) {
        dashboardPresetSelection = selection
        guard case .preset(let preset) = selection else {
            previewDashboardPomodoroIfIdle()
            return
        }
        let config = preset.durationConfig
        dashboardWorkMinutes = max(1, config.workDuration / 60)
        dashboardShortBreakMinutes = max(1, config.shortBreakDuration / 60)
        dashboardLongBreakMinutes = max(1, config.longBreakDuration / 60)
        dashboardLongBreakInterval = clamp(config.longBreakInterval, range: 1...12)
        previewDashboardPomodoroIfIdle()
    }

    private func handleDashboardSessionEdit() {
        dashboardPresetSelection = PresetSelection.selection(for: dashboardPomodoroDurationConfig)
        previewDashboardPomodoroIfIdle()
    }

    private func previewDashboardPomodoroIfIdle() {
        guard appState.pomodoro.state == .idle else { return }
        appState.previewPomodoroSession(durationConfig: dashboardPomodoroDurationConfig)
    }

    private func startDashboardPomodoro() {
        appState.startPomodoroSession(durationConfig: dashboardPomodoroDurationConfig)
    }

    private func syncDurationTexts() {
        if focusedField != .work {
            workMinutesText = String(workMinutesValue)
        }
        if focusedField != .shortBreak {
            shortBreakMinutesText = String(shortBreakMinutesValue)
        }
        if focusedField != .longBreak {
            longBreakMinutesText = String(longBreakMinutesValue)
        }
        if focusedField != .countdown {
            countdownMinutesText = String(countdownMinutesValue)
        }
        if focusedField != .countdownSeconds {
            countdownSecondsText = String(format: "%02d", countdownSecondsValue)
        }
    }

    private func syncLongBreakInterval() {
        longBreakIntervalValue = clamp(appState.durationConfig.longBreakInterval, range: 1...12)
    }

    private func commitDuration(_ field: DurationField) {
        switch field {
        case .work:
            let committed = parseMinutes(from: workMinutesText, fallback: workMinutesValue, range: 1...120)
            workMinutesText = String(committed)
            updateDurationConfig(workMinutes: committed)
        case .shortBreak:
            let committed = parseMinutes(from: shortBreakMinutesText, fallback: shortBreakMinutesValue, range: 1...60)
            shortBreakMinutesText = String(committed)
            updateDurationConfig(shortBreakMinutes: committed)
        case .longBreak:
            let committed = parseMinutes(from: longBreakMinutesText, fallback: longBreakMinutesValue, range: 1...90)
            longBreakMinutesText = String(committed)
            updateDurationConfig(longBreakMinutes: committed)
        case .countdown:
            let committed = parseMinutes(from: countdownMinutesText, fallback: countdownMinutesValue, range: 0...120)
            countdownMinutesText = String(committed)
            updateDurationConfig(countdownMinutes: committed)
        case .countdownSeconds:
            let committed = parseMinutes(from: countdownSecondsText, fallback: countdownSecondsValue, range: 0...59)
            countdownSecondsText = String(format: "%02d", committed)
            updateDurationConfig(countdownSeconds: committed)
        }
    }

    private func applyCountdownPreset(minutes: Int) {
        countdownMinutesText = String(minutes)
        countdownSecondsText = "00"
        updateDurationConfig(countdownMinutes: minutes, countdownSeconds: 0)
    }

    private func parseMinutes(from text: String, fallback: Int, range: ClosedRange<Int>) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else {
            return clamp(fallback, range: range)
        }
        return clamp(value, range: range)
    }

    private func clamp(_ value: Int, range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private var timerStateAnimation: Animation? {
        // Calm, lightweight easing for state transitions and numeric pulse.
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }
    
    private var mainTimerUpdateAnimation: Animation? {
        // Subtle dissolve for ticking seconds; keeps the timer feeling fluid.
        reduceMotion ? nil : .easeOut(duration: 0.14)
    }

    private var sectionTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        // Calm fade + slight scale keeps transitions lightweight; avoids sliding motion.
        let fadeScale = AnyTransition.opacity.combined(with: .scale(scale: 0.985))
        return .asymmetric(insertion: fadeScale, removal: fadeScale)
    }

    private var sectionTransitionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    private func shouldAnimateTimerTransition(from oldValue: TimerState, to newValue: TimerState) -> Bool {
        if oldValue == .idle && newValue == .running {
            return true
        }
        if oldValue == .running && newValue == .paused {
            return true
        }
        if oldValue == .paused && newValue == .running {
            return true
        }
        if oldValue == .running && (newValue == .breakRunning || newValue == .breakPaused) {
            return true
        }
        if oldValue == .breakPaused && newValue == .breakRunning {
            return true
        }
        if (oldValue == .breakRunning || oldValue == .breakPaused) && newValue == .idle {
            return true
        }
        if oldValue != .idle && newValue == .idle {
            return true
        }
        return false
    }

    private func triggerPomodoroStateAnimation(from oldValue: TimerState, to newValue: TimerState) {
        guard shouldAnimateTimerTransition(from: oldValue, to: newValue), !reduceMotion else { return }
        pomodoroStatePulse.toggle()
    }

    private func triggerCountdownStateAnimation(from oldValue: TimerState, to newValue: TimerState) {
        guard shouldAnimateTimerTransition(from: oldValue, to: newValue), !reduceMotion else { return }
        countdownStatePulse.toggle()
    }
}

private struct PlanTaskSelectionSheet: View {
    let entries: [AppState.PlanExecutionEntry]
    let onSelect: (AppState.PlanExecutionEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

        VStack(alignment: .leading, spacing: 18) {
            Text("Choose a Planned Task")
                .font(.title3.weight(.semibold))

            Text("Pick the task you want to work on first. Pomodoro will start with that task's saved estimate.")
                .font(.subheadline)
                .foregroundStyle(appearanceMode.secondaryTextColor(for: colorScheme))

            if entries.isEmpty {
                Text("No planned tasks available.")
                    .font(.subheadline)
                    .foregroundStyle(appearanceMode.secondaryTextColor(for: colorScheme))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(entries) { entry in
                            Button {
                                onSelect(entry)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text("\(entry.pomodoros) Pomodoros")
                                            .font(.subheadline)
                                            .foregroundStyle(appearanceMode.secondaryTextColor(for: colorScheme))
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.tint)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .appRoundedSurface(
                                    mode: appearanceMode,
                                    cornerRadius: 16,
                                    glassMaterial: .regularMaterial,
                                    standardLevel: .panel,
                                    showsShadow: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 220, maxHeight: 360)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

private struct GlassCardView<Content: View>: View {
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

        content
            .padding(18)
            .appRoundedSurface(
                mode: appearanceMode,
                cornerRadius: 18,
                glassMaterial: .ultraThinMaterial,
                standardLevel: .panel
            )
    }
}

private struct DashboardPanel<Content: View>: View {
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .appRoundedSurface(
                mode: appearanceMode,
                cornerRadius: 16,
                glassMaterial: .ultraThinMaterial,
                standardLevel: .panel,
                showsShadow: appearanceMode == .standard
            )
            .frame(maxWidth: .infinity, minHeight: 248, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AdaptivePageGrid<Content: View>: View {
    let minimumWidth: CGFloat
    let spacing: CGFloat
    let content: Content

    init(
        minimumWidth: CGFloat = 340,
        spacing: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumWidth = minimumWidth
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: minimumWidth), spacing: spacing, alignment: .top)],
            alignment: .leading,
            spacing: spacing
        ) {
            content
        }
    }
}

private struct AdaptiveMetricGrid<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        AdaptivePageGrid(minimumWidth: 220, spacing: 14) {
            content
        }
    }
}

private struct SectionHeaderView<Trailing: View>: View {
    @EnvironmentObject private var appTypography: AppTypography
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(appTypography.sectionHeaderFont())
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

private extension SectionHeaderView where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let caption: String?
    let tint: Color

    init(title: String, value: String, caption: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.value = value
        self.caption = caption
        self.tint = tint
    }

    var body: some View {
        GlassCardView {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AIActionCard<Trailing: View>: View {
    let icon: String
    let title: String
    let description: String
    let trailing: Trailing

    init(
        icon: String,
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.trailing = trailing()
    }

    var body: some View {
        GlassCardView {
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text(title)
                        .font(.headline)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(Color.accentColor)
                }
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                trailing
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    @EnvironmentObject private var appTypography: AppTypography
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(appTypography.cardTitleFont())
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .appRoundedSurface(
                mode: appearanceMode,
                cornerRadius: 12,
                glassMaterial: .thinMaterial,
                standardLevel: .inset,
                showsShadow: false
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsModuleCard<Content: View>: View {
    @EnvironmentObject private var appTypography: AppTypography
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let description: String?
    @ViewBuilder var content: Content
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(appTypography.cardTitleFont())
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(appearanceMode.secondaryTextColor(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appRoundedSurface(
            mode: appearanceMode,
            cornerRadius: 18,
            glassMaterial: .regularMaterial,
            standardLevel: .panel,
            isEmphasized: isHovering
        )
        .scaleEffect(isHovering ? 1.004 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct SettingsPlansSheet: View {
    @ObservedObject var featureGate: FeatureGate
    @ObservedObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue

    var body: some View {
        let appearanceMode = AppearanceMode.resolved(from: appearanceModeRawValue)

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Subscription")
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text("Compare plans, review upgrades, and restore purchases in a focused pop-up.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PlansComparisonView(
                        featureGate: featureGate,
                        subscriptionStore: subscriptionStore
                    )

                    if let errorMessage = subscriptionStore.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let productLoadErrorMessage = subscriptionStore.productLoadErrorMessage,
                       !productLoadErrorMessage.isEmpty {
                        Text(productLoadErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 640)
        .appRoundedSurface(
            mode: appearanceMode,
            cornerRadius: 24,
            glassMaterial: .regularMaterial,
            standardLevel: .panel
        )
    }
}

// MARK: - Menu bar navigation hooks
extension Notification.Name {
    static let navigateToPomodoro = Notification.Name("navigateToPomodoro")
    static let navigateToFlow = Notification.Name("navigateToFlow")
    static let navigateToCountdown = Notification.Name("navigateToCountdown")
    static let navigateToTasks = Notification.Name("navigateToTasks")
    static let navigateToCalendar = Notification.Name("navigateToCalendar")
    static let openNewTaskComposer = Notification.Name("openNewTaskComposer")
    static let calendarGoToToday = Notification.Name("calendarGoToToday")
    static let taskToggleSelectedCompletion = Notification.Name("taskToggleSelectedCompletion")
    static let taskDeleteSelection = Notification.Name("taskDeleteSelection")
}

#if DEBUG && PREVIEWS_ENABLED
#Preview {
    MainActor.assumeIsolated {
        let appState = AppState()
        let musicController = MusicController(ambientNoiseEngine: appState.ambientNoiseEngine)
        let externalMonitor = ExternalAudioMonitor()
        let externalController = ExternalPlaybackController()
        let audioSourceStore = AudioSourceStore(
            musicController: musicController,
            externalMonitor: externalMonitor,
            externalController: externalController
        )
        let onboardingDefaults = UserDefaults(suiteName: "MainWindowViewPreview")!
        onboardingDefaults.set(true, forKey: "onboarding.completed")
        onboardingDefaults.set(true, forKey: "onboarding.calendarPermissionsPrompted")
        onboardingDefaults.set(true, forKey: "onboarding.menuBarTipSeen")
        onboardingDefaults.set(true, forKey: "onboarding.eventKitRequestCalled")
        let onboardingState = OnboardingState(userDefaults: onboardingDefaults)
        return MainWindowView()
            .environmentObject(appState)
            .environmentObject(musicController)
            .environmentObject(audioSourceStore)
            .environmentObject(LanguageManager.shared)
            .environmentObject(AppTypography.shared)
            .environmentObject(AuthViewModel.shared)
            .environmentObject(onboardingState)
            .environmentObject(FlowWindowManager())
    }
}
#endif

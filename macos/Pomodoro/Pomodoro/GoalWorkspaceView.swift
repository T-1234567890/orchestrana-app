import EventKit
import SwiftUI

enum WorkspaceSection: CaseIterable, Identifiable {
    case search
    case notes
    case goals
    case knowledge
    case map

    var id: Self { self }

    func title(languageManager: LanguageManager) -> String {
        switch self {
        case .search:
            return languageManager.text("workspace.section.search")
        case .notes:
            return languageManager.text("workspace.section.notes")
        case .goals:
            return languageManager.text("workspace.section.goals")
        case .knowledge:
            return languageManager.text("workspace.section.knowledge")
        case .map:
            return languageManager.text("workspace.section.map")
        }
    }

    var systemImage: String {
        switch self {
        case .search:
            return "magnifyingglass"
        case .notes:
            return "note.text"
        case .goals:
            return "target"
        case .knowledge:
            return "books.vertical"
        case .map:
            return "map"
        }
    }
}

private struct GoalDraft {
    var outcome = ""
    var successCriteria = ""
    var nextAction = ""
    var notes = ""
    var targetDate = Date()
    var hasTargetDate = false
}

private struct GoalSmartLinkSuggestion: Identifiable, Hashable {
    let id = UUID()
    let kind: GoalLink.Kind
    let targetID: String
    let title: String
    let subtitle: String
    let reason: String
}

private enum WorkspaceSearchResultKind: String, CaseIterable, Identifiable {
    case goal
    case task
    case event
    case location
    case session

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .goal:
            return "target"
        case .task:
            return "checklist"
        case .event:
            return "calendar"
        case .location:
            return "mappin.and.ellipse"
        case .session:
            return "timer"
        }
    }

    func title(languageManager: LanguageManager) -> String {
        languageManager.text("workspace.search.kind.\(rawValue)")
    }
}

private enum WorkspaceSearchTypeFilter: String, CaseIterable, Identifiable {
    case all
    case goal
    case task
    case event
    case location
    case session

    var id: String { rawValue }

    func title(languageManager: LanguageManager) -> String {
        languageManager.text("workspace.search.filter.type.\(rawValue)")
    }

    func includes(_ kind: WorkspaceSearchResultKind) -> Bool {
        switch self {
        case .all:
            return true
        case .goal:
            return kind == .goal
        case .task:
            return kind == .task
        case .event:
            return kind == .event
        case .location:
            return kind == .location
        case .session:
            return kind == .session
        }
    }
}

private enum WorkspaceSearchStatus: String {
    case active
    case completed
    case paused
}

private enum WorkspaceSearchStatusFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed
    case paused

    var id: String { rawValue }

    func title(languageManager: LanguageManager) -> String {
        languageManager.text("workspace.search.filter.status.\(rawValue)")
    }

    func includes(_ status: WorkspaceSearchStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            return status == .active
        case .completed:
            return status == .completed
        case .paused:
            return status == .paused
        }
    }
}

private enum WorkspaceSearchDifficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    func title(languageManager: LanguageManager) -> String {
        languageManager.text("workspace.search.filter.difficulty.\(rawValue)")
    }
}

private enum WorkspaceSearchDifficultyFilter: String, CaseIterable, Identifiable {
    case all
    case easy
    case medium
    case hard

    var id: String { rawValue }

    func title(languageManager: LanguageManager) -> String {
        languageManager.text("workspace.search.filter.difficulty.\(rawValue)")
    }

    func includes(_ difficulty: WorkspaceSearchDifficulty?) -> Bool {
        switch self {
        case .all:
            return true
        case .easy:
            return difficulty == .easy
        case .medium:
            return difficulty == .medium
        case .hard:
            return difficulty == .hard
        }
    }
}

private struct WorkspaceSearchResult: Identifiable {
    let id: String
    let kind: WorkspaceSearchResultKind
    let title: String
    let subtitle: String
    let searchableText: String
    let status: WorkspaceSearchStatus
    let difficulty: WorkspaceSearchDifficulty?
    let destination: WorkspaceSearchDestination
}

private enum WorkspaceSearchDestination {
    case goal(UUID)
    case task(UUID, locationID: UUID?)
    case planningTask(UUID, locationID: UUID?)
    case planningEvent(UUID, locationID: UUID?, date: Date?)
    case systemEvent(String?, locationID: UUID?, date: Date?)
    case location(UUID)
    case session(UUID)
}

private enum WorkspaceCleanupTarget {
    case goal(UUID)
    case task(UUID)
    case planningTask(UUID)
}

private struct WorkspaceCleanupCandidate: Identifiable {
    let id: String
    let kind: WorkspaceSearchResultKind
    let title: String
    let subtitle: String
    let target: WorkspaceCleanupTarget
}

@MainActor
struct GoalWorkspaceView: View {
    let selectedWorkspaceSection: WorkspaceSection
    @ObservedObject var goalStore: GoalStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject var locationStore: LocationStore
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var sessionRecordStore: SessionRecordStore
    @ObservedObject var featureGate: FeatureGate
    @ObservedObject var appState: AppState
    @EnvironmentObject private var languageManager: LanguageManager

    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue
    @AppStorage(DeveloperDemoMode.googleVideoDemoModeKey) private var googleVideoDemoMode = false
    @AppStorage("com.pomodoro.workspace.dynamicGoalAdaptEnabled") private var isDynamicGoalAdaptEnabled = false
    @AppStorage("com.pomodoro.workspace.dynamicGoalAdaptIntervalHours") private var dynamicGoalAdaptIntervalHours = 12
    @AppStorage("com.pomodoro.workspace.lastGoalAdjustmentTimestamp") private var lastGoalAdjustmentTimestamp = 0.0

    @State private var selectedGoalID: UUID?
    @State private var workspaceSearchText = ""
    @State private var workspaceSearchTypeFilter = WorkspaceSearchTypeFilter.all
    @State private var workspaceSearchStatusFilter = WorkspaceSearchStatusFilter.active
    @State private var workspaceSearchDifficultyFilter = WorkspaceSearchDifficultyFilter.all
    @State private var workspaceSearchListsEverything = false
    @State private var goalDraft = GoalDraft()
    @State private var aiGoalPrompt = ""
    @State private var aiGoalDraftReady = false
    @State private var isGeneratingGoalDraft = false
    @State private var goalAIErrorMessage: String?
    @State private var smartLinkSuggestions: [GoalSmartLinkSuggestion] = []
    @State private var selectedSmartLinkSuggestionIDs: Set<UUID> = []
    @State private var isGeneratingSmartLinks = false
    @State private var smartLinkErrorMessage: String?
    @State private var smartLinkStatusMessage: String?
    @State private var limitMessage: String?
    @State private var showingCreateGoalSheet = false
    @State private var showingAICreateGoalSheet = false
    @State private var showingSmartLinkSheet = false
    @State private var upgradePaywallContext: SubscriptionPaywallContext?
    @State private var showingWorkspaceCleanupSheet = false
    @State private var isWorkspaceCleanupSelecting = false
    @State private var selectedWorkspaceCleanupIDs: Set<String> = []
    @State private var workspaceCleanupMessage: String?
    @State private var isAdjustingGoals = false

    private var selectedGoal: GoalRecord? {
        guard let selectedGoalID else { return goalStore.goals.first }
        return goalStore.goals.first { $0.id == selectedGoalID } ?? goalStore.goals.first
    }

    private var isPaidGoalTier: Bool {
        switch featureGate.tier {
        case .plus, .pro, .developer:
            return true
        case .free, .beta, .expired:
            return false
        }
    }

    private var canUseGoalAI: Bool {
        switch featureGate.tier {
        case .plus, .pro, .developer:
            return true
        case .free, .beta, .expired:
            return false
        }
    }

    private var canUseDynamicGoalAI: Bool {
        switch featureGate.tier {
        case .pro, .developer:
            return true
        case .free, .beta, .plus, .expired:
            return false
        }
    }

    private var isDynamicGoalAdaptActive: Bool {
        canUseDynamicGoalAI && isDynamicGoalAdaptEnabled
    }

    private var dynamicGoalAdaptBinding: Binding<Bool> {
        Binding(
            get: { isDynamicGoalAdaptActive },
            set: { newValue in
                if newValue {
                    guard canUseDynamicGoalAI else {
                        presentDynamicGoalPaywall()
                        return
                    }
                    isDynamicGoalAdaptEnabled = true
                } else {
                    isDynamicGoalAdaptEnabled = false
                }
            }
        )
    }

    private var activeGoalLimit: Int? {
        isPaidGoalTier ? nil : 3
    }

    private var linkLimit: Int? {
        isPaidGoalTier ? nil : 8
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let limitMessage {
                    Text(limitMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 2)
                }

                workspaceContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if selectedGoalID == nil {
                selectedGoalID = goalStore.goals.first?.id
            }
            Task {
                await runDynamicGoalAdaptIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceGoalFocusItem)) { notification in
            guard let goalIDString = notification.userInfo?["goalID"] as? String,
                  let goalID = UUID(uuidString: goalIDString),
                  goalStore.goals.contains(where: { $0.id == goalID }) else {
                return
            }
            selectedGoalID = goalID
        }
        .onChange(of: isDynamicGoalAdaptEnabled) { _, isEnabled in
            if isEnabled {
                Task {
                    await runDynamicGoalAdaptIfNeeded(force: true)
                }
            }
        }
        .onChange(of: dynamicGoalAdaptIntervalHours) { _, _ in
            Task {
                await runDynamicGoalAdaptIfNeeded()
            }
        }
        .onChange(of: goalStore.goals) { _, goals in
            guard let selectedGoalID,
                  goals.contains(where: { $0.id == selectedGoalID }) else {
                self.selectedGoalID = goals.first?.id
                return
            }
        }
        .sheet(isPresented: $showingCreateGoalSheet) {
            goalCreationSheet(
                title: languageManager.text("workspace.goal.create.title"),
                subtitle: languageManager.text("workspace.goal.create.subtitle"),
                primaryActionTitle: languageManager.text("workspace.goal.create.primary")
            ) {
                createGoalFromDraft()
                showingCreateGoalSheet = false
            }
        }
        .sheet(isPresented: $showingAICreateGoalSheet) {
            aiGoalCreationSheet
        }
        .sheet(isPresented: $showingSmartLinkSheet) {
            smartLinkSheet
        }
        .sheet(item: $upgradePaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: SubscriptionStore.shared
            )
        }
        .sheet(isPresented: $showingWorkspaceCleanupSheet) {
            workspaceCleanupSheet
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch selectedWorkspaceSection {
        case .search:
            workspaceSearchPage
        case .goals, .notes, .knowledge:
            goalsOverviewLayout
        case .map:
            MapWorkspaceView(
                locationStore: locationStore,
                todoStore: todoStore,
                planningStore: planningStore,
                calendarManager: calendarManager,
                goalStore: goalStore,
                featureGate: featureGate
            )
        }
    }

    private var workspaceSearchPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(languageManager.text("workspace.search.page.title"))
                    .font(.title2.weight(.semibold))
                Text(languageManager.text("workspace.search.page.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            workspaceSearchField
            workspaceSearchFilterBar

            if shouldShowWorkspaceSearchResults {
                workspaceSearchResultsCard
            } else {
                workspaceSearchIdleState
            }
        }
    }

    private var shouldShowWorkspaceSearchResults: Bool {
        workspaceSearchListsEverything || !normalizedWorkspaceSearchQuery.isEmpty
    }

    private var normalizedWorkspaceSearchQuery: String {
        workspaceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var workspaceSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(languageManager.text("workspace.search.placeholder"), text: $workspaceSearchText)
                .textFieldStyle(.plain)
            if !workspaceSearchText.isEmpty {
                Button {
                    workspaceSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(languageManager.text("common.clear"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appRoundedSurface(
            mode: AppearanceMode.resolved(from: appearanceModeRawValue),
            cornerRadius: 12,
            glassMaterial: .ultraThinMaterial,
            standardLevel: .panel,
            showsShadow: false
        )
    }

    private var workspaceSearchFilterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                ZStack {
                    workspaceSearchFilterControlsGroup
                        .frame(maxWidth: .infinity, alignment: .leading)

                    workspaceSearchActionControlsGroup
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    workspaceSearchFilterControlsGroup

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        workspaceSearchActionControlsGroup
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .controlSize(.small)
            .animation(.easeInOut(duration: 0.18), value: isWorkspaceCleanupSelecting)

            if let workspaceCleanupMessage {
                Text(workspaceCleanupMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: workspaceCleanupMessage)
    }

    private var workspaceSearchFilterControlsGroup: some View {
        HStack(spacing: 10) {
            workspaceTypeFilterControl
            workspaceStatusFilterControl
            workspaceDifficultyFilterControl
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var workspaceSearchActionControlsGroup: some View {
        HStack(spacing: 10) {
            workspaceListEverythingButton
            if isWorkspaceCleanupSelecting {
                workspaceChooseEverythingCleanupButton
            }
            workspaceCleanupButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var workspaceTypeFilterControl: some View {
        workspaceFilterMenu(
            accessibilityLabel: languageManager.text("workspace.search.filter.type.label"),
            selection: $workspaceSearchTypeFilter,
            width: 138,
            title: { $0.title(languageManager: languageManager) }
        )
    }

    private var workspaceStatusFilterControl: some View {
        workspaceFilterMenu(
            accessibilityLabel: languageManager.text("workspace.search.filter.status.label"),
            selection: $workspaceSearchStatusFilter,
            width: 138,
            title: { $0.title(languageManager: languageManager) }
        )
    }

    private var workspaceDifficultyFilterControl: some View {
        workspaceFilterMenu(
            accessibilityLabel: languageManager.text("workspace.search.filter.difficulty.label"),
            selection: $workspaceSearchDifficultyFilter,
            width: 148,
            title: { $0.title(languageManager: languageManager) }
        )
    }

    private func workspaceFilterMenu<Filter>(
        accessibilityLabel: String,
        selection: Binding<Filter>,
        width: CGFloat,
        title: @escaping (Filter) -> String
    ) -> some View where Filter: CaseIterable & Identifiable & Equatable, Filter.AllCases: RandomAccessCollection {
        Menu {
            ForEach(Array(Filter.allCases), id: \.id) { filter in
                Button {
                    selection.wrappedValue = filter
                } label: {
                    if selection.wrappedValue == filter {
                        Label(title(filter), systemImage: "checkmark")
                    } else {
                        Text(title(filter))
                    }
                }
            }
        } label: {
            Text(title(selection.wrappedValue))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(width: width, height: 32, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(accessibilityLabel)
    }

    private var workspaceListEverythingButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                workspaceSearchListsEverything.toggle()
            }
        } label: {
            Label(
                languageManager.text("workspace.search.filter.list_all"),
                systemImage: workspaceSearchListsEverything ? "tray.full.fill" : "tray.full"
            )
        }
        .buttonStyle(.bordered)
        .tint(workspaceSearchListsEverything ? .accentColor : .secondary)
        .frame(height: 32)
        .fixedSize()
    }

    private var workspaceChooseEverythingCleanupButton: some View {
        Button {
            chooseVisibleWorkspaceCleanupItems()
        } label: {
            Label(languageManager.text("workspace.search.cleanup.choose_everything"), systemImage: "plus.circle")
        }
        .disabled(visibleWorkspaceCleanupCandidateIDs.isEmpty)
        .buttonStyle(.bordered)
        .tint(.orange)
        .frame(height: 32)
        .fixedSize()
    }

    private var workspaceCleanupButton: some View {
        Button {
            handleWorkspaceCleanupButtonPress()
        } label: {
            Label(workspaceCleanupButtonTitle, systemImage: isWorkspaceCleanupSelecting ? "list.bullet.rectangle" : "sparkles")
        }
        .disabled(workspaceCleanupCandidates.isEmpty)
        .help(languageManager.format("workspace.search.cleanup.help", workspaceCleanupCandidates.count))
        .buttonStyle(.bordered)
        .tint(isWorkspaceCleanupSelecting ? .orange : .secondary)
        .frame(height: 32)
        .fixedSize()
        .animation(.easeInOut(duration: 0.18), value: selectedWorkspaceCleanupIDs.count)
    }

    private var workspaceCleanupButtonTitle: String {
        if isWorkspaceCleanupSelecting {
            return languageManager.format("workspace.search.cleanup.review_selected", selectedWorkspaceCleanupIDs.count)
        }
        return languageManager.text("workspace.search.cleanup.button")
    }

    private var workspaceCleanupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(languageManager.text("workspace.search.cleanup.title"))
                    .font(.title2.weight(.semibold))
                Text(languageManager.text("workspace.search.cleanup.sheet.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if selectedWorkspaceCleanupCandidates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(languageManager.text("workspace.search.cleanup.empty_selection"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selectedWorkspaceCleanupCandidates) { candidate in
                    HStack {
                        workspaceCleanupCandidateRow(candidate)
                        Spacer()
                        Button {
                            selectedWorkspaceCleanupIDs.remove(candidate.id)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }

            HStack {
                Button(languageManager.text("workspace.search.cleanup.back_to_selection")) {
                    showingWorkspaceCleanupSheet = false
                }

                Spacer()

                Text(languageManager.format("workspace.search.cleanup.selected_count", selectedWorkspaceCleanupIDs.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(languageManager.text("common.cancel")) {
                    cancelWorkspaceCleanup()
                }

                Button(languageManager.text("workspace.search.cleanup.confirm"), role: .destructive) {
                    runWorkspaceCleanup()
                }
                .disabled(selectedWorkspaceCleanupIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 620, maxWidth: 620, minHeight: 460)
    }

    private func workspaceCleanupCandidateRow(_ candidate: WorkspaceCleanupCandidate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: candidate.kind.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(candidate.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private func cleanupSelectionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedWorkspaceCleanupIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedWorkspaceCleanupIDs.insert(id)
                } else {
                    selectedWorkspaceCleanupIDs.remove(id)
                }
            }
        )
    }

    private var workspaceSearchResultsCard: some View {
        GoalWorkspaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(languageManager.text("workspace.search.results.title"))
                            .font(.headline)
                        Text(languageManager.format("workspace.search.results.count", workspaceSearchResults.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if workspaceSearchResults.isEmpty {
                    workspaceSearchEmptyState
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workspaceSearchGroupedResults, id: \.kind.id) { group in
                            workspaceSearchResultGroup(group)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isWorkspaceCleanupSelecting)
        .animation(.easeInOut(duration: 0.16), value: selectedWorkspaceCleanupIDs)
    }

    private var workspaceSearchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(languageManager.text("workspace.search.empty.title"))
                .font(.subheadline.weight(.semibold))
            Text(languageManager.text("workspace.search.empty.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var workspaceSearchIdleState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(languageManager.text("workspace.search.idle.title"))
                .font(.headline)
            Text(languageManager.text("workspace.search.idle.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
    }

    private var workspaceSearchResults: [WorkspaceSearchResult] {
        let query = normalizedWorkspaceSearchQuery
        let filteredResults = filteredWorkspaceSearchResults

        guard !query.isEmpty else {
            return workspaceSearchListsEverything ? Array(filteredResults.prefix(120)) : []
        }

        return filteredResults
            .compactMap { result -> (WorkspaceSearchResult, Int)? in
                let score = fuzzySearchScore(query: query, candidate: result.searchableText)
                return score > 0 ? (result, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
                }
                return lhs.1 > rhs.1
            }
            .prefix(60)
            .map(\.0)
    }

    private var workspaceSearchGroupedResults: [(kind: WorkspaceSearchResultKind, results: [WorkspaceSearchResult])] {
        WorkspaceSearchResultKind.allCases.compactMap { kind in
            let results = workspaceSearchResults.filter { $0.kind == kind }
            return results.isEmpty ? nil : (kind, results)
        }
    }

    private var filteredWorkspaceSearchResults: [WorkspaceSearchResult] {
        let results = allWorkspaceSearchResults.filter { result in
            workspaceSearchTypeFilter.includes(result.kind)
                && workspaceSearchStatusFilter.includes(result.status)
                && workspaceSearchDifficultyFilter.includes(result.difficulty)
        }

        guard isWorkspaceCleanupSelecting else {
            return results
        }

        return results.filter { workspaceCleanupCandidateIDs.contains($0.id) }
    }

    private var allWorkspaceSearchResults: [WorkspaceSearchResult] {
        goalSearchResults
            + taskSearchResults
            + planningEventSearchResults
            + systemEventSearchResults
            + locationSearchResults
            + sessionSearchResults
    }

    private var goalSearchResults: [WorkspaceSearchResult] {
        goalStore.goals.map { goal in
            WorkspaceSearchResult(
                id: "goal-\(goal.id.uuidString)",
                kind: .goal,
                title: goal.outcome,
                subtitle: [
                    localizedStatusTitle(goal.status),
                    goal.targetDate.map { $0.formatted(date: .abbreviated, time: .omitted) }
                ].compactMap { $0 }.joined(separator: " - "),
                searchableText: [
                    goal.outcome,
                    goal.successCriteria,
                    goal.nextAction,
                    goal.notes,
                    goal.status.rawValue,
                    localizedStatusTitle(goal.status)
                ].joined(separator: " "),
                status: workspaceStatus(for: goal.status),
                difficulty: nil,
                destination: .goal(goal.id)
            )
        }
    }

    private var taskSearchResults: [WorkspaceSearchResult] {
        visibleTodoItems.map { task in
            WorkspaceSearchResult(
                id: "task-\(task.id.uuidString)",
                kind: .task,
                title: task.title,
                subtitle: taskSearchSubtitle(task),
                searchableText: [
                    task.title,
                    task.descriptionMarkdown ?? "",
                    task.tags.joined(separator: " "),
                    task.priority.displayName,
                    taskDifficulty(task).title(languageManager: languageManager),
                    task.isCompleted ? languageManager.text("workspace.item.completed_task") : languageManager.text("workspace.item.task")
                ].joined(separator: " "),
                status: task.isCompleted ? .completed : .active,
                difficulty: taskDifficulty(task),
                destination: .task(task.id, locationID: task.locationID)
            )
        }
    }

    private var planningEventSearchResults: [WorkspaceSearchResult] {
        visiblePlanningItems.map { item in
            let destination: WorkspaceSearchDestination = if item.isCalendarEvent {
                .planningEvent(item.id, locationID: item.locationID, date: item.startDate)
            } else if let sourceID = item.sourceID,
                      let taskID = UUID(uuidString: sourceID) {
                .task(taskID, locationID: item.locationID)
            } else {
                .planningTask(item.id, locationID: item.locationID)
            }

            return WorkspaceSearchResult(
                id: "planning-\(item.id.uuidString)",
                kind: item.isCalendarEvent ? .event : .task,
                title: item.title,
                subtitle: planningItemSearchSubtitle(item),
                searchableText: [
                    item.title,
                    item.notes ?? "",
                    item.source.rawValue,
                    planningDifficulty(item)?.title(languageManager: languageManager) ?? "",
                    item.completed ? languageManager.text("workspace.item.completed_task") : ""
                ].joined(separator: " "),
                status: planningStatus(item),
                difficulty: planningDifficulty(item),
                destination: destination
            )
        }
    }

    private var systemEventSearchResults: [WorkspaceSearchResult] {
        calendarManager.events.map { event in
            let identifier = event.eventIdentifier ?? "\(event.title ?? "event")-\(event.startDate?.timeIntervalSince1970 ?? 0)"
            return WorkspaceSearchResult(
                id: "system-event-\(identifier)",
                kind: .event,
                title: event.title ?? languageManager.text("workspace.item.event"),
                subtitle: event.startDate?.formatted(date: .abbreviated, time: .shortened) ?? languageManager.text("workspace.item.event"),
                searchableText: [
                    event.title ?? "",
                    event.notes ?? "",
                    event.location ?? "",
                    event.calendar.title,
                    eventStatus(event).rawValue
                ].joined(separator: " "),
                status: eventStatus(event),
                difficulty: nil,
                destination: .systemEvent(event.eventIdentifier, locationID: systemEventLocationID(event), date: event.startDate)
            )
        }
    }

    private var locationSearchResults: [WorkspaceSearchResult] {
        locationStore.locations.map { location in
            WorkspaceSearchResult(
                id: "location-\(location.id.uuidString)",
                kind: .location,
                title: location.name,
                subtitle: location.address.isEmpty ? location.tags.joined(separator: ", ") : location.address,
                searchableText: [
                    location.name,
                    location.address,
                    location.tags.joined(separator: " ")
                ].joined(separator: " "),
                status: .active,
                difficulty: nil,
                destination: .location(location.id)
            )
        }
    }

    private var sessionSearchResults: [WorkspaceSearchResult] {
        sessionRecordStore.records
            .sorted { $0.endTime > $1.endTime }
            .map { session in
                WorkspaceSearchResult(
                    id: "session-\(session.id.uuidString)",
                    kind: .session,
                    title: sessionTitle(session),
                    subtitle: session.endTime.formatted(date: .abbreviated, time: .shortened),
                    searchableText: [
                        sessionTitle(session),
                        session.sessionType.rawValue,
                        session.completed ? "completed" : "incomplete",
                        session.endTime.formatted(date: .abbreviated, time: .shortened)
                    ].joined(separator: " "),
                    status: session.completed ? .completed : .active,
                    difficulty: nil,
                    destination: .session(session.id)
                )
            }
    }

    private var workspaceCleanupCandidateCount: Int {
        workspaceCleanupCandidates.count
    }

    private var selectedWorkspaceCleanupCandidates: [WorkspaceCleanupCandidate] {
        workspaceCleanupCandidates.filter { selectedWorkspaceCleanupIDs.contains($0.id) }
    }

    private var workspaceCleanupCandidateIDs: Set<String> {
        Set(workspaceCleanupCandidates.map(\.id))
    }

    private var visibleWorkspaceCleanupCandidateIDs: Set<String> {
        Set(workspaceSearchResults.map(\.id).filter { workspaceCleanupCandidateIDs.contains($0) })
    }

    private var workspaceCleanupCandidates: [WorkspaceCleanupCandidate] {
        let goals = completedCleanupGoals.map { goal in
            WorkspaceCleanupCandidate(
                id: "goal-\(goal.id.uuidString)",
                kind: .goal,
                title: goal.outcome,
                subtitle: languageManager.text("workspace.search.cleanup.item.completed_goal"),
                target: .goal(goal.id)
            )
        }

        let tasks = completedCleanupTasks.map { task in
            WorkspaceCleanupCandidate(
                id: "task-\(task.id.uuidString)",
                kind: .task,
                title: task.title,
                subtitle: taskSearchSubtitle(task),
                target: .task(task.id)
            )
        }

        let planningTasks = completedCleanupPlanningTasks.map { item in
            WorkspaceCleanupCandidate(
                id: "planning-\(item.id.uuidString)",
                kind: .task,
                title: item.title,
                subtitle: planningItemSearchSubtitle(item),
                target: .planningTask(item.id)
            )
        }

        return goals + tasks + planningTasks
    }

    private var completedCleanupGoals: [GoalRecord] {
        goalStore.goals.filter { $0.status == .completed }
    }

    private var completedCleanupTasks: [TodoItem] {
        todoStore.items.filter(\.isCompleted)
    }

    private var completedCleanupPlanningTasks: [PlanningItem] {
        planningStore.items.filter { item in
            item.isTask
                && item.completed
                && item.sourceID.flatMap(UUID.init(uuidString:)).map { taskID in
                    !todoStore.items.contains { $0.id == taskID }
                } ?? true
        }
    }

    private func handleWorkspaceCleanupButtonPress() {
        if isWorkspaceCleanupSelecting {
            guard !selectedWorkspaceCleanupIDs.isEmpty else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isWorkspaceCleanupSelecting = false
                    workspaceCleanupMessage = nil
                }
                return
            }
            showingWorkspaceCleanupSheet = true
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            isWorkspaceCleanupSelecting = true
            workspaceSearchListsEverything = true
            workspaceSearchStatusFilter = .completed
            workspaceCleanupMessage = languageManager.text("workspace.search.cleanup.selection_mode")
        }
    }

    private func isWorkspaceCleanupCandidate(_ id: String) -> Bool {
        workspaceCleanupCandidateIDs.contains(id)
    }

    private func toggleWorkspaceCleanupSelection(for result: WorkspaceSearchResult) {
        guard isWorkspaceCleanupCandidate(result.id) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            if selectedWorkspaceCleanupIDs.contains(result.id) {
                selectedWorkspaceCleanupIDs.remove(result.id)
            } else {
                selectedWorkspaceCleanupIDs.insert(result.id)
            }
        }
    }

    private func chooseVisibleWorkspaceCleanupItems() {
        withAnimation(.easeInOut(duration: 0.16)) {
            selectedWorkspaceCleanupIDs.formUnion(visibleWorkspaceCleanupCandidateIDs)
        }
    }

    private func cancelWorkspaceCleanup() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showingWorkspaceCleanupSheet = false
            isWorkspaceCleanupSelecting = false
            selectedWorkspaceCleanupIDs.removeAll()
            workspaceCleanupMessage = nil
            workspaceSearchListsEverything = false
            workspaceSearchStatusFilter = .active
        }
    }

    private func runWorkspaceCleanup() {
        let selectedCandidates = workspaceCleanupCandidates.filter { selectedWorkspaceCleanupIDs.contains($0.id) }

        for candidate in selectedCandidates {
            switch candidate.target {
            case .goal(let goalID):
                deleteGoal(goalID)
            case .task(let taskID):
                deleteTodo(taskID)
            case .planningTask(let itemID):
                deletePlanningTask(itemID)
            }
        }

        workspaceCleanupMessage = languageManager.format("workspace.search.cleanup.done", selectedCandidates.count)
        selectedWorkspaceCleanupIDs.removeAll()
        isWorkspaceCleanupSelecting = false
        showingWorkspaceCleanupSheet = false
        workspaceSearchListsEverything = true
        workspaceSearchStatusFilter = .all
    }

    private func workspaceSearchStatusColor(_ status: WorkspaceSearchStatus) -> Color {
        switch status {
        case .active:
            return .green
        case .completed:
            return .blue
        case .paused:
            return .orange
        }
    }

    private func workspaceSearchStatusSymbol(_ status: WorkspaceSearchStatus) -> String {
        switch status {
        case .active:
            return "bolt.fill"
        case .completed:
            return "flag.checkered"
        case .paused:
            return "pause.circle.fill"
        }
    }

    private func workspaceSearchDifficultySymbol(_ difficulty: WorkspaceSearchDifficulty) -> String {
        switch difficulty {
        case .easy:
            return "leaf"
        case .medium:
            return "gauge.medium"
        case .hard:
            return "flame"
        }
    }

    private func workspaceStatus(for status: GoalRecord.Status) -> WorkspaceSearchStatus {
        switch status {
        case .active:
            return .active
        case .paused:
            return .paused
        case .completed:
            return .completed
        }
    }

    private func planningStatus(_ item: PlanningItem) -> WorkspaceSearchStatus {
        if item.completed {
            return .completed
        }
        if item.isCalendarEvent,
           let endDate = item.endDate ?? item.startDate,
           endDate < Date() {
            return .completed
        }
        return .active
    }

    private func eventStatus(_ event: EKEvent) -> WorkspaceSearchStatus {
        if let endDate = event.endDate,
           endDate < Date() {
            return .completed
        }
        return .active
    }

    private func taskDifficulty(_ task: TodoItem) -> WorkspaceSearchDifficulty {
        let estimate = task.pomodoroEstimate ?? 0
        let duration = task.durationMinutes ?? 0

        if task.priority == .high || estimate >= 4 || duration >= 90 {
            return .hard
        }
        if task.priority == .medium || estimate >= 2 || duration >= 50 {
            return .medium
        }
        return .easy
    }

    private func planningDifficulty(_ item: PlanningItem) -> WorkspaceSearchDifficulty? {
        if let sourceID = item.sourceID,
           let taskID = UUID(uuidString: sourceID),
           let task = todoStore.items.first(where: { $0.id == taskID }) {
            return taskDifficulty(task)
        }

        guard item.isTask else { return nil }
        guard let start = item.startDate,
              let end = item.endDate else {
            return .easy
        }

        let duration = end.timeIntervalSince(start) / 60
        if duration >= 90 {
            return .hard
        }
        if duration >= 50 {
            return .medium
        }
        return .easy
    }

    private func fuzzySearchScore(query: String, candidate: String) -> Int {
        let normalizedQuery = normalizedSearchText(query)
        let normalizedCandidate = normalizedSearchText(candidate)

        guard !normalizedQuery.isEmpty,
              !normalizedCandidate.isEmpty else {
            return 0
        }

        if normalizedCandidate.contains(normalizedQuery) {
            return 10_000 - min(normalizedCandidate.count, 9_000)
        }

        let queryTokens = normalizedQuery.split(separator: " ")
        let candidateTokens = normalizedCandidate.split(separator: " ")
        if !queryTokens.isEmpty,
           queryTokens.allSatisfy({ queryToken in
               candidateTokens.contains { candidateToken in
                   candidateToken.hasPrefix(queryToken) || candidateToken.contains(queryToken)
               }
           }) {
            return 7_500 - normalizedCandidate.count
        }

        var queryIndex = normalizedQuery.startIndex
        var score = 0
        var gapPenalty = 0
        var lastMatchIndex: String.Index?
        var candidateIndex = normalizedCandidate.startIndex

        while queryIndex < normalizedQuery.endIndex,
              candidateIndex < normalizedCandidate.endIndex {
            if normalizedQuery[queryIndex] == normalizedCandidate[candidateIndex] {
                score += 120
                if let lastMatchIndex {
                    gapPenalty += normalizedCandidate.distance(from: lastMatchIndex, to: candidateIndex) - 1
                }
                lastMatchIndex = candidateIndex
                queryIndex = normalizedQuery.index(after: queryIndex)
            }
            candidateIndex = normalizedCandidate.index(after: candidateIndex)
        }

        guard queryIndex == normalizedQuery.endIndex else {
            return 0
        }

        return max(1, score - gapPenalty)
    }

    private func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : " "
            }
            .reduce(into: "") { result, character in
                if character == " ",
                   result.last == " " {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func workspaceSearchResultGroup(_ group: (kind: WorkspaceSearchResultKind, results: [WorkspaceSearchResult])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.kind.title(languageManager: languageManager))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.results) { result in
                    workspaceSearchResultRow(result)
                }
            }
        }
    }

    private func workspaceSearchResultRow(_ result: WorkspaceSearchResult) -> some View {
        HStack(spacing: 8) {
            Button {
                if isWorkspaceCleanupSelecting {
                    toggleWorkspaceCleanupSelection(for: result)
                } else {
                    openSearchResult(result)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: result.kind.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            workspaceSearchStatusBadge(result.status)
                            if let difficulty = result.difficulty {
                                workspaceSearchDifficultyBadge(difficulty)
                            }
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .help(languageManager.text("workspace.search.action.open_original"))

            if isWorkspaceCleanupSelecting {
                workspaceCleanupSelectionControl(for: result)
            } else {
                Menu {
                    workspaceSearchOperations(for: result)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(8)
        .background(
            workspaceCleanupSelectionBackground(for: result),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func workspaceSearchStatusBadge(_ status: WorkspaceSearchStatus) -> some View {
        Label {
            Text(languageManager.text("workspace.search.status.\(status.rawValue)"))
        } icon: {
            Image(systemName: workspaceSearchStatusSymbol(status))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(workspaceSearchStatusColor(status))
        .labelStyle(.titleAndIcon)
    }

    private func workspaceSearchDifficultyBadge(_ difficulty: WorkspaceSearchDifficulty) -> some View {
        Label {
            Text(difficulty.title(languageManager: languageManager))
        } icon: {
            Image(systemName: workspaceSearchDifficultySymbol(difficulty))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private func workspaceCleanupSelectionControl(for result: WorkspaceSearchResult) -> some View {
        let isEligible = isWorkspaceCleanupCandidate(result.id)
        let isSelected = selectedWorkspaceCleanupIDs.contains(result.id)

        return Button {
            toggleWorkspaceCleanupSelection(for: result)
        } label: {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSelected ? Color.orange : (isEligible ? Color.secondary : Color.secondary.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(!isEligible)
        .help(isEligible ? languageManager.text("workspace.search.cleanup.select_item") : languageManager.text("workspace.search.cleanup.not_cleanable"))
    }

    private func workspaceCleanupSelectionBackground(for result: WorkspaceSearchResult) -> Color {
        guard isWorkspaceCleanupSelecting else {
            return Color.primary.opacity(0.035)
        }
        if selectedWorkspaceCleanupIDs.contains(result.id) {
            return Color.orange.opacity(0.12)
        }
        return isWorkspaceCleanupCandidate(result.id) ? Color.primary.opacity(0.035) : Color.primary.opacity(0.018)
    }

    @ViewBuilder
    private func workspaceSearchOperations(for result: WorkspaceSearchResult) -> some View {
        Button(languageManager.text("workspace.search.action.open_original")) {
            openSearchResult(result)
        }

        switch result.destination {
        case .goal(let goalID):
            Button(languageManager.text("workspace.search.action.mark_goal_active")) {
                goalStore.setStatus(goalID: goalID, status: .active)
            }
            Button(languageManager.text("workspace.search.action.mark_goal_completed")) {
                goalStore.setStatus(goalID: goalID, status: .completed)
            }
            Button(languageManager.text("workspace.search.action.mark_goal_paused")) {
                goalStore.setStatus(goalID: goalID, status: .paused)
            }
            Button(languageManager.text("workspace.search.action.delete"), role: .destructive) {
                deleteGoal(goalID)
            }
        case .task(let taskID, let locationID):
            Button(languageManager.text("workspace.search.action.toggle_task_completion")) {
                toggleTodoCompletion(taskID)
            }
            Button(languageManager.text("workspace.search.action.mark_task_active")) {
                setTodoCompletion(taskID, isCompleted: false)
            }
            Button(languageManager.text("workspace.search.action.mark_task_completed")) {
                setTodoCompletion(taskID, isCompleted: true)
            }
            if let locationID {
                Button(languageManager.text("workspace.search.action.show_on_map")) {
                    openMap(locationID: locationID, workItemID: "task-\(taskID.uuidString)")
                }
            }
            Button(languageManager.text("workspace.search.action.delete"), role: .destructive) {
                deleteTodo(taskID)
            }
        case .planningTask(let itemID, let locationID):
            Button(languageManager.text("workspace.search.action.toggle_task_completion")) {
                togglePlanningTaskCompletion(itemID)
            }
            Button(languageManager.text("workspace.search.action.mark_task_active")) {
                setPlanningTaskCompletion(itemID, isCompleted: false)
            }
            Button(languageManager.text("workspace.search.action.mark_task_completed")) {
                setPlanningTaskCompletion(itemID, isCompleted: true)
            }
            if let locationID {
                Button(languageManager.text("workspace.search.action.show_on_map")) {
                    openMap(locationID: locationID, workItemID: "planning-\(itemID.uuidString)")
                }
            }
            Button(languageManager.text("workspace.search.action.delete"), role: .destructive) {
                deletePlanningTask(itemID)
            }
        case .planningEvent(let itemID, let locationID, _):
            if let locationID {
                Button(languageManager.text("workspace.search.action.show_on_map")) {
                    openMap(locationID: locationID, workItemID: "event-\(itemID.uuidString)")
                }
            }
            Button(languageManager.text("workspace.search.action.open_calendar")) {
                openCalendar(localEventID: itemID, systemEventID: nil, taskID: nil, date: nil)
            }
        case .systemEvent(_, let locationID, _):
            if let locationID {
                Button(languageManager.text("workspace.search.action.show_on_map")) {
                    openMap(locationID: locationID, workItemID: nil)
                }
            }
            Button(languageManager.text("workspace.search.action.open_calendar")) {
                openSearchResult(result)
            }
        case .location:
            Button(languageManager.text("workspace.search.action.delete"), role: .destructive) {
                deleteLocation(result)
            }
        case .session:
            Button(languageManager.text("workspace.search.action.open_insights")) {
                NotificationCenter.default.post(name: .navigateToInsights, object: nil)
            }
        }
    }

    private func openSearchResult(_ result: WorkspaceSearchResult) {
        switch result.destination {
        case .goal(let goalID):
            selectedGoalID = goalID
            NotificationCenter.default.post(name: .navigateToWorkspaceGoals, object: nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .workspaceGoalFocusItem,
                    object: nil,
                    userInfo: ["goalID": goalID.uuidString]
                )
            }
        case .task(let taskID, _):
            openTask(taskID)
        case .planningTask(let itemID, _):
            NotificationCenter.default.post(name: .navigateToTasks, object: nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .taskFocusItem,
                    object: nil,
                    userInfo: ["planningItemID": itemID.uuidString]
                )
            }
        case .planningEvent(let itemID, _, let date):
            openCalendar(localEventID: itemID, systemEventID: nil, taskID: nil, date: date)
        case .systemEvent(let eventID, _, let date):
            openCalendar(localEventID: nil, systemEventID: eventID, taskID: nil, date: date)
        case .location(let locationID):
            openMap(locationID: locationID, workItemID: nil)
        case .session:
            NotificationCenter.default.post(name: .navigateToInsights, object: nil)
        }
    }

    private func openTask(_ taskID: UUID) {
        NotificationCenter.default.post(name: .navigateToTasks, object: nil)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .taskFocusItem,
                object: nil,
                userInfo: ["taskID": taskID.uuidString]
            )
        }
    }

    private func openCalendar(localEventID: UUID?, systemEventID: String?, taskID: UUID?, date: Date?) {
        NotificationCenter.default.post(name: .navigateToCalendar, object: nil)
        DispatchQueue.main.async {
            var userInfo: [String: Any] = [:]
            if let localEventID {
                userInfo["localEventID"] = localEventID.uuidString
            }
            if let systemEventID {
                userInfo["systemEventID"] = systemEventID
            }
            if let taskID {
                userInfo["taskID"] = taskID.uuidString
            }
            if let date {
                userInfo["date"] = date
            }
            NotificationCenter.default.post(name: .calendarFocusItem, object: nil, userInfo: userInfo)
        }
    }

    private func openMap(locationID: UUID?, workItemID: String?) {
        NotificationCenter.default.post(name: .navigateToWorkspaceMap, object: nil)
        DispatchQueue.main.async {
            var userInfo: [String: Any] = [:]
            if let locationID {
                userInfo["locationID"] = locationID.uuidString
            }
            if let workItemID {
                userInfo["workItemID"] = workItemID
            }
            NotificationCenter.default.post(name: .workspaceMapFocusItem, object: nil, userInfo: userInfo)
        }
    }

    private func toggleTodoCompletion(_ taskID: UUID) {
        guard let task = todoStore.items.first(where: { $0.id == taskID }) else { return }
        todoStore.toggleCompletion(task)
    }

    private func setTodoCompletion(_ taskID: UUID, isCompleted: Bool) {
        todoStore.setCompletion(itemID: taskID, isCompleted: isCompleted)
    }

    private func deleteTodo(_ taskID: UUID) {
        guard let task = todoStore.items.first(where: { $0.id == taskID }) else { return }
        todoStore.deleteItem(task)
    }

    private func togglePlanningTaskCompletion(_ itemID: UUID) {
        guard let item = planningStore.items.first(where: { $0.id == itemID }) else { return }
        planningStore.toggleComplete(item)
    }

    private func setPlanningTaskCompletion(_ itemID: UUID, isCompleted: Bool) {
        guard let item = planningStore.items.first(where: { $0.id == itemID }),
              item.completed != isCompleted else {
            return
        }
        planningStore.toggleComplete(item)
    }

    private func deletePlanningTask(_ itemID: UUID) {
        guard let item = planningStore.items.first(where: { $0.id == itemID }) else { return }
        planningStore.deleteTask(item)
    }

    private func deleteGoal(_ goalID: UUID) {
        guard let goal = goalStore.goals.first(where: { $0.id == goalID }) else { return }
        goalStore.deleteGoal(goal)
    }

    private func deleteLocation(_ result: WorkspaceSearchResult) {
        guard case .location(let locationID) = result.destination,
              let location = locationStore.location(id: locationID) else {
            return
        }
        locationStore.deleteLocation(location)
    }

    private func systemEventLocationID(_ event: EKEvent) -> UUID? {
        guard let eventLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !eventLocation.isEmpty else {
            return nil
        }
        return locationStore.locations.first { location in
            eventLocation.localizedCaseInsensitiveContains(location.name)
                || (!location.address.isEmpty && eventLocation.localizedCaseInsensitiveContains(location.address))
        }?.id
    }

    private func goalCreationSheet(
        title: String,
        subtitle: String,
        primaryActionTitle: String,
        onCreate: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField(languageManager.text("workspace.goal.placeholder.outcome"), text: $goalDraft.outcome)
                .textFieldStyle(.roundedBorder)

            TextField(languageManager.text("workspace.goal.field.success_criteria"), text: $goalDraft.successCriteria, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            TextField(languageManager.text("workspace.goal.field.next_action"), text: $goalDraft.nextAction)
                .textFieldStyle(.roundedBorder)

            TextField(languageManager.text("workspace.goal.field.notes"), text: $goalDraft.notes, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            Toggle(languageManager.text("workspace.goal.field.target_date"), isOn: $goalDraft.hasTargetDate)
            if goalDraft.hasTargetDate {
                DatePicker(languageManager.text("workspace.goal.field.due"), selection: $goalDraft.targetDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }

            HStack {
                Spacer()
                Button(languageManager.text("common.cancel")) {
                    showingCreateGoalSheet = false
                    showingAICreateGoalSheet = false
                }
                Button(primaryActionTitle) {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(goalDraft.outcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var aiGoalCreationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(languageManager.text("workspace.goal.ai_create.title"))
                    .font(.title2.weight(.semibold))
                Text(languageManager.text("workspace.goal.ai_create.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField(languageManager.text("workspace.goal.ai_create.placeholder"), text: $aiGoalPrompt, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    await generateAIGoalDraft()
                }
            } label: {
                if isGeneratingGoalDraft {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(languageManager.text("workspace.goal.ai_create.generating"))
                    }
                } else {
                    Label(languageManager.text("workspace.goal.ai_create.generate"), systemImage: "sparkles")
                }
            }
            .buttonStyle(.bordered)
            .disabled(aiGoalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingGoalDraft)

            if let goalAIErrorMessage {
                Text(goalAIErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if aiGoalDraftReady {
                Divider()
                goalCreationSheet(
                    title: languageManager.text("workspace.goal.ai_create.review_title"),
                    subtitle: languageManager.text("workspace.goal.ai_create.review_subtitle"),
                    primaryActionTitle: languageManager.text("workspace.goal.create.primary")
                ) {
                    createGoalFromDraft()
                    showingAICreateGoalSheet = false
                }
                .padding(-24)
            } else {
                HStack {
                    Spacer()
                    Button(languageManager.text("common.cancel")) {
                        showingAICreateGoalSheet = false
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var smartLinkSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(languageManager.text("workspace.smart_link.title"))
                    .font(.title2.weight(.semibold))
                Text(languageManager.text("workspace.smart_link.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if smartLinkSuggestions.isEmpty {
                if isGeneratingSmartLinks {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        VStack(spacing: 4) {
                            Text(languageManager.text("workspace.smart_link.finding"))
                                .font(.headline)
                            Text(smartLinkStatusMessage ?? languageManager.text("workspace.smart_link.checking"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.text("workspace.smart_link.empty"))
                            .foregroundStyle(.secondary)
                        if let smartLinkStatusMessage {
                            Text(smartLinkStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(smartLinkSuggestions) { suggestion in
                            Toggle(isOn: smartLinkSelectionBinding(for: suggestion)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(suggestion.title, systemImage: icon(for: suggestion.kind))
                                        .font(.subheadline.weight(.medium))
                                    Text("\(suggestion.subtitle) - \(suggestion.reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(10)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            HStack {
                if let smartLinkErrorMessage {
                    Text(smartLinkErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let smartLinkStatusMessage {
                    Text(smartLinkStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(languageManager.text("common.cancel")) {
                    showingSmartLinkSheet = false
                }
                Button(languageManager.text("workspace.smart_link.add_related_work")) {
                    confirmSmartLinkSuggestions()
                    showingSmartLinkSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSmartLinkSuggestionIDs.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var goalsOverviewLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    goalsActionCard
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

                    goalsListCard
                        .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 16) {
                    goalsActionCard
                    goalsListCard
                }
            }

            selectedGoalCard
                .frame(maxWidth: .infinity)
        }
    }

    private var goalsActionCard: some View {
        GoalWorkspaceCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(languageManager.text("workspace.goals.title"))
                        .font(.title3.weight(.semibold))
                    Text(languageManager.text("workspace.goals.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    goalActionButton(
                        title: languageManager.text("workspace.goal.create.title"),
                        systemImage: "plus.circle.fill",
                        isProminent: true
                    ) {
                        goalDraft = GoalDraft()
                        showingCreateGoalSheet = true
                    }

                    goalActionButton(
                        title: languageManager.text("workspace.goal.ai_create.title"),
                        systemImage: "sparkles"
                    ) {
                        guard canUseGoalAI else {
                            presentGoalAIPaywall(
                                title: languageManager.text("workspace.paywall.ai_goal.title"),
                                message: languageManager.text("workspace.paywall.ai_goal.message")
                            )
                            return
                        }
                        goalDraft = GoalDraft()
                        aiGoalPrompt = ""
                        aiGoalDraftReady = false
                        showingAICreateGoalSheet = true
                    }

                    goalActionButton(
                        title: isGeneratingSmartLinks ? languageManager.text("workspace.smart_link.finding_short") : languageManager.text("workspace.smart_link.button"),
                        systemImage: "wand.and.stars",
                        isEnabled: !isGeneratingSmartLinks,
                        isLoading: isGeneratingSmartLinks
                    ) {
                        guard canUseGoalAI else {
                            presentGoalAIPaywall(
                                title: languageManager.text("workspace.paywall.smart_link.title"),
                                message: languageManager.text("workspace.paywall.smart_link.message")
                            )
                            return
                        }
                        guard selectedGoal != nil else {
                            limitMessage = languageManager.text("workspace.smart_link.select_goal_first")
                            return
                        }
                        Task {
                            await prepareSmartLinkSuggestions()
                        }
                    }
                }

                dynamicGoalAdaptControl
            }
        }
    }

    private var dynamicGoalAdaptControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(languageManager.text("workspace.dynamic_adapt.title"))
                        .font(.subheadline.weight(.semibold))
                    Text(languageManager.text("workspace.dynamic_adapt.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: dynamicGoalAdaptBinding)
                    .labelsHidden()
            }

            if isDynamicGoalAdaptActive {
                Stepper(
                    languageManager.format("workspace.dynamic_adapt.every_hours", dynamicGoalAdaptIntervalHours),
                    value: $dynamicGoalAdaptIntervalHours,
                    in: 6...48,
                    step: 6
                )
                .font(.caption)

                if isAdjustingGoals {
                    Label(languageManager.text("workspace.dynamic_adapt.adapting"), systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func goalActionButton(
        title: String,
        systemImage: String,
        isProminent: Bool = false,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if isProminent {
                Button(action: action) {
                    goalActionButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    goalActionButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
        .disabled(!isEnabled)
    }

    private func goalActionButtonLabel(title: String, systemImage: String, isLoading: Bool = false) -> some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
    }

    private var goalsListCard: some View {
        GoalWorkspaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(languageManager.text("workspace.goal_tracking.title"))
                        .font(.headline)
                    Spacer()
                    Text("\(goalStore.goals.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if goalStore.goals.isEmpty {
                    Text(languageManager.text("workspace.goal_tracking.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(goalStore.goals) { goal in
                                Button {
                                    selectedGoalID = goal.id
                                } label: {
                                    GoalListRow(
                                        goal: goal,
                                        isSelected: selectedGoal?.id == goal.id,
                                        progressText: progressText(for: goal)
                                    )
                                    .frame(width: 280)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedGoalCard: some View {
        if let goal = selectedGoal {
            GoalWorkspaceCard {
                VStack(alignment: .leading, spacing: 16) {
                    selectedGoalHeader(goal)

                    if !goal.successCriteria.isEmpty {
                        detailBlock(title: languageManager.text("workspace.goal.field.success_criteria"), body: goal.successCriteria)
                    }

                    if !goal.nextAction.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            detailBlock(title: languageManager.text("workspace.goal.field.next_action"), body: goal.nextAction)
                            HStack(spacing: 10) {
                                Button {
                                    createRelatedTaskFromNextAction(for: goal)
                                } label: {
                                    Label(languageManager.text("workspace.goal.create_task_from_next_action"), systemImage: "checklist")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRelatedWorkLimitReached(for: goal))

                                Button {
                                    startFocus(for: goal)
                                } label: {
                                    Label(languageManager.text("workspace.goal.start_focus"), systemImage: "timer")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    progressSection(for: goal)

                    relatedWorkList(for: goal)

                    if !goal.notes.isEmpty {
                        detailBlock(title: languageManager.text("workspace.goal.field.notes"), body: goal.notes)
                    }

                    dangerZone(for: goal)
                }
            }
        } else {
            GoalWorkspaceCard {
                Text(languageManager.text("workspace.goal.empty_selection"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            }
        }
    }

    private func selectedGoalHeader(_ goal: GoalRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.outcome)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        Label(localizedStatusTitle(goal.status), systemImage: statusIcon(for: goal.status))
                        if let targetDate = goal.targetDate {
                            Label(targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                StatusPill(title: localizedStatusTitle(goal.status), icon: statusIcon(for: goal.status))
            }

            if let progress = progressText(for: goal) {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progressSection(for goal: GoalRecord) -> some View {
        let summary = relatedWorkSummary(for: goal)
        return VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.text("workspace.progress.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                progressMetric(title: languageManager.text("workspace.progress.tasks"), value: "\(summary.completedTasks)/\(summary.totalTasks)")
                progressMetric(title: languageManager.text("workspace.progress.focus_sessions"), value: "\(summary.focusSessions)")
                progressMetric(title: languageManager.text("workspace.progress.time_spent"), value: durationText(summary.focusSeconds))
            }
        }
    }

    private func progressMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dangerZone(for goal: GoalRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(languageManager.text("workspace.goal_controls.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(languageManager.text("workspace.status.paused")) {
                    goalStore.setStatus(goalID: goal.id, status: .paused)
                }
                .disabled(goal.status == .paused)

                Button(languageManager.text("workspace.status.completed")) {
                    goalStore.setStatus(goalID: goal.id, status: .completed)
                }
                .disabled(goal.status == .completed)

                Button(languageManager.text("common.delete"), role: .destructive) {
                    goalStore.deleteGoal(goal)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private func relatedWorkList(for goal: GoalRecord) -> some View {
        let links = goalStore.links(for: goal.id)
        return VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.text("workspace.related_work.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if links.isEmpty {
                Text(languageManager.text("workspace.related_work.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(links) { link in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: link.kind))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(for: link))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(subtitle(for: link))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func createGoalFromDraft() {
        if let activeGoalLimit,
           goalStore.goals.filter({ $0.status == .active }).count >= activeGoalLimit {
            limitMessage = languageManager.format("workspace.limit.active_goals", activeGoalLimit)
            return
        }

        guard let goal = goalStore.addGoal(
            outcome: goalDraft.outcome,
            successCriteria: goalDraft.successCriteria,
            notes: goalDraft.notes,
            nextAction: goalDraft.nextAction,
            targetDate: goalDraft.hasTargetDate ? goalDraft.targetDate : nil
        ) else {
            return
        }

        selectedGoalID = goal.id
        goalDraft = GoalDraft()
        limitMessage = nil
    }

    private func presentGoalAIPaywall(title: String, message: String) {
        upgradePaywallContext = SubscriptionPaywallContext(
            requiredTier: .plus,
            title: title,
            message: message
        )
    }

    private func presentDynamicGoalPaywall() {
        upgradePaywallContext = SubscriptionPaywallContext(
            requiredTier: .pro,
            title: languageManager.text("workspace.paywall.dynamic_adapt.title"),
            message: languageManager.text("workspace.paywall.dynamic_adapt.message")
        )
    }

    private func createRelatedTaskFromNextAction(for goal: GoalRecord) {
        guard !isRelatedWorkLimitReached(for: goal) else {
            showRelatedWorkLimitMessage()
            return
        }
        let title = goal.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let item = TodoItem(title: title, notes: languageManager.format("workspace.related_goal.note", goal.outcome))
        todoStore.addItem(item)
        _ = goalStore.addLink(goalID: goal.id, kind: .task, targetID: item.id.uuidString)
        limitMessage = nil
    }

    private func showRelatedWorkLimitMessage() {
        if let linkLimit {
            limitMessage = languageManager.format("workspace.limit.related_work", linkLimit)
        }
    }

    private func isRelatedWorkLimitReached(for goal: GoalRecord) -> Bool {
        guard let linkLimit else { return false }
        return goalStore.linkCount(for: goal.id) >= linkLimit
    }

    private func startFocus(for goal: GoalRecord) {
        let title = goal.nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? goal.outcome : goal.nextAction
        appState.applyPlan(title: title, pomodoroCount: 1)
        appState.startPomodoro()
    }

    private func generateAIGoalDraft() async {
        guard canUseGoalAI else {
            goalAIErrorMessage = languageManager.text("workspace.paywall.ai_goal.short")
            return
        }

        isGeneratingGoalDraft = true
        goalAIErrorMessage = nil
        defer { isGeneratingGoalDraft = false }

        do {
            let response = try await AIService.shared.generateGoalDraft(
                prompt: aiGoalPrompt,
                context: goalCreationContextPayload()
            )
            goalDraft = GoalDraft(
                outcome: response.outcome,
                successCriteria: response.successCriteria,
                nextAction: response.nextAction,
                notes: response.notes,
                targetDate: parseGoalTargetDate(response.targetDate) ?? Date(),
                hasTargetDate: parseGoalTargetDate(response.targetDate) != nil
            )
            aiGoalDraftReady = true
        } catch {
            aiGoalDraftReady = false
            goalAIErrorMessage = AIService.userFacingErrorMessage(error)
        }
    }

    private func parseGoalTargetDate(_ value: String?) -> Date? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime, .withFullDate]
        return fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value)
    }

    private var visibleTodoItems: [TodoItem] {
        DeveloperDemoMode.visibleTasks(todoStore.items, tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private var visiblePlanningItems: [PlanningItem] {
        DeveloperDemoMode.visiblePlanningItems(planningStore.items, tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private func taskSearchSubtitle(_ task: TodoItem) -> String {
        var parts = [
            task.isCompleted ? languageManager.text("workspace.item.completed_task") : languageManager.text("workspace.item.task")
        ]
        if let dueDate = task.dueDate {
            parts.append(dueDate.formatted(date: .abbreviated, time: task.hasDueTime ? .shortened : .omitted))
        }
        if let locationID = task.locationID,
           let location = locationStore.location(id: locationID) {
            parts.append(location.name)
        }
        return parts.joined(separator: " - ")
    }

    private func planningItemSearchSubtitle(_ item: PlanningItem) -> String {
        var parts = [
            item.isCalendarEvent ? languageManager.text("workspace.item.event") : languageManager.text("workspace.item.task")
        ]
        if let startDate = item.startDate {
            parts.append(startDate.formatted(date: .abbreviated, time: .shortened))
        }
        if let locationID = item.locationID,
           let location = locationStore.location(id: locationID) {
            parts.append(location.name)
        }
        return parts.joined(separator: " - ")
    }

    private func draftGoal(from prompt: String) -> GoalDraft {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return GoalDraft() }

        let lowercased = trimmed.lowercased()
        let outcome: String
        if lowercased.contains("launch") {
            outcome = "Successfully launch \(extractProductName(from: trimmed))"
        } else if lowercased.contains("finish") || lowercased.contains("complete") {
            outcome = "Finish \(trimmed.replacingOccurrences(of: "I want to ", with: "", options: [.caseInsensitive]))"
        } else {
            outcome = trimmed
        }

        let successCriteria = makeSuccessCriteria(from: trimmed)
        let nextAction = makeNextAction(from: trimmed)
        return GoalDraft(
            outcome: outcome,
            successCriteria: successCriteria,
            nextAction: nextAction,
            notes: "Drafted from: \(trimmed)",
            targetDate: Date(),
            hasTargetDate: false
        )
    }

    private func extractProductName(from prompt: String) -> String {
        if prompt.localizedCaseInsensitiveContains("Orchestrana") {
            return "Orchestrana publicly"
        }
        return "the project publicly"
    }

    private func makeSuccessCriteria(from prompt: String) -> String {
        let lowercased = prompt.lowercased()
        var criteria: [String] = []
        if lowercased.contains("app store") {
            criteria.append("App Store page is live")
        }
        if lowercased.contains("product hunt") {
            criteria.append("Product Hunt page is published")
        }
        if lowercased.contains("website") || lowercased.contains("launch") {
            criteria.append("Website CTA is updated")
        }
        if lowercased.contains("feedback") || lowercased.contains("launch") {
            criteria.append("Initial feedback is collected")
        }
        if criteria.isEmpty {
            criteria = [
                "Outcome is clearly defined",
                "Required work is completed",
                "Result is reviewed"
            ]
        }
        return criteria.map { "- \($0)" }.joined(separator: "\n")
    }

    private func makeNextAction(from prompt: String) -> String {
        let lowercased = prompt.lowercased()
        if lowercased.contains("app store") {
            return "Update the website with the App Store link"
        }
        if lowercased.contains("product hunt") {
            return "Prepare the Product Hunt launch checklist"
        }
        if lowercased.contains("design") {
            return "Draft the first workflow design"
        }
        return "Write the first concrete task for this goal"
    }

    private func goalCreationContextPayload() -> [String: Any] {
        let tasks = visibleTodoItems
            .prefix(40)
            .map { task in
                [
                    "id": task.id.uuidString,
                    "title": task.title,
                    "notes": [task.descriptionMarkdown ?? "", task.tags.joined(separator: " ")].joined(separator: "\n"),
                    "subtitle": task.isCompleted ? languageManager.text("workspace.item.completed_task") : languageManager.text("workspace.item.task")
                ]
            }

        let events = visiblePlanningItems
            .filter(\.isCalendarEvent)
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            .prefix(40)
            .map { event in
                [
                    "id": event.id.uuidString,
                    "title": event.title,
                    "notes": event.notes ?? "",
                    "subtitle": event.startDate?.formatted(date: .abbreviated, time: .shortened) ?? languageManager.text("workspace.item.event")
                ]
            }

        let sessions = sessionRecordStore.records
            .sorted { $0.endTime > $1.endTime }
            .prefix(20)
            .map { session in
                [
                    "id": session.id.uuidString,
                    "title": sessionTitle(session),
                    "notes": "",
                    "subtitle": session.endTime.formatted(date: .abbreviated, time: .shortened)
                ]
            }

        let notes = Array(
            (visibleTodoItems.compactMap(\.descriptionMarkdown) + visiblePlanningItems.compactMap(\.notes))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(30)
        )

        return [
            "tasks": Array(tasks),
            "events": Array(events),
            "sessions": Array(sessions),
            "notes": notes
        ]
    }

    private func prepareSmartLinkSuggestions() async {
        guard let goal = selectedGoal else { return }
        guard canUseGoalAI else {
            smartLinkErrorMessage = languageManager.text("workspace.paywall.smart_link.short")
            return
        }

        let candidates = smartLinkCandidatesPayload(for: goal)
        let candidateCount = smartLinkCandidateCount(in: candidates)

        isGeneratingSmartLinks = true
        smartLinkErrorMessage = nil
        smartLinkStatusMessage = languageManager.format(
            "workspace.smart_link.status.checking_counts",
            candidateCount.tasks,
            candidateCount.events,
            candidateCount.sessions
        )
        smartLinkSuggestions = []
        selectedSmartLinkSuggestionIDs = []
        showingSmartLinkSheet = true
        defer { isGeneratingSmartLinks = false }

        do {
            ClientLog.debug("[Goals] Smart Link AI request started. tasks: \(candidateCount.tasks), events: \(candidateCount.events), sessions: \(candidateCount.sessions)")
            let response = try await AIService.shared.suggestGoalRelatedWork(
                goal: goalSmartLinkPayload(for: goal),
                candidates: candidates
            )
            ClientLog.debug("[Goals] Smart Link AI response suggestions: \(response.suggestions.count)")
            smartLinkSuggestions = response.suggestions.compactMap(goalSmartLinkSuggestion(from:))
            if smartLinkSuggestions.isEmpty {
                smartLinkSuggestions = makeSmartLinkSuggestions(for: goal)
                smartLinkStatusMessage = smartLinkSuggestions.isEmpty
                    ? languageManager.format("workspace.smart_link.status.no_ai_match", candidateCount.tasks, candidateCount.events, candidateCount.sessions)
                    : languageManager.text("workspace.smart_link.status.showing_local")
            } else {
                smartLinkStatusMessage = languageManager.format("workspace.smart_link.status.suggested_count", smartLinkSuggestions.count)
            }
        } catch {
            ClientLog.debugError("[Goals] Smart Link AI request failed", error)
            smartLinkSuggestions = makeSmartLinkSuggestions(for: goal)
            smartLinkErrorMessage = AIService.userFacingErrorMessage(error)
            smartLinkStatusMessage = smartLinkSuggestions.isEmpty
                ? languageManager.text("workspace.smart_link.status.failed_empty")
                : languageManager.text("workspace.smart_link.status.failed_local")
        }

        selectedSmartLinkSuggestionIDs = Set(smartLinkSuggestions.prefix(3).map(\.id))
    }

    private func smartLinkCandidateCount(in payload: [String: Any]) -> (tasks: Int, events: Int, sessions: Int) {
        return (
            tasks: (payload["tasks"] as? [Any])?.count ?? 0,
            events: (payload["events"] as? [Any])?.count ?? 0,
            sessions: (payload["sessions"] as? [Any])?.count ?? 0
        )
    }

    private func goalSmartLinkPayload(for goal: GoalRecord) -> [String: Any] {
        [
            "outcome": goal.outcome,
            "successCriteria": goal.successCriteria,
            "nextAction": goal.nextAction,
            "notes": goal.notes
        ]
    }

    private func smartLinkCandidatesPayload(for goal: GoalRecord) -> [String: Any] {
        let tasks = visibleTodoItems
            .filter { isSmartLinkEligibleTask($0, for: goal) }
            .prefix(40)
            .map { task in
                [
                    "id": task.id.uuidString,
                    "title": task.title,
                    "notes": [task.descriptionMarkdown ?? "", task.tags.joined(separator: " ")].joined(separator: "\n"),
                    "subtitle": languageManager.text("workspace.item.task")
                ]
            }

        let events = visiblePlanningItems
            .filter { isSmartLinkEligibleEvent($0, for: goal) }
            .prefix(40)
            .map { event in
                [
                    "id": event.id.uuidString,
                    "title": event.title,
                    "notes": event.notes ?? "",
                    "subtitle": event.startDate?.formatted(date: .abbreviated, time: .shortened) ?? languageManager.text("workspace.item.event")
                ]
            }

        let sessions = sessionRecordStore.records
            .sorted { $0.endTime > $1.endTime }
            .filter { !goalStore.hasLink(goalID: goal.id, kind: .session, targetID: $0.id.uuidString) }
            .prefix(20)
            .map { session in
                [
                    "id": session.id.uuidString,
                    "title": sessionTitle(session),
                    "notes": "",
                    "subtitle": session.endTime.formatted(date: .abbreviated, time: .shortened)
                ]
            }

        return [
            "tasks": Array(tasks),
            "events": Array(events),
            "sessions": Array(sessions)
        ]
    }

    private func isSmartLinkEligibleTask(_ task: TodoItem, for goal: GoalRecord) -> Bool {
        !task.isCompleted
            && !goalStore.hasLink(goalID: goal.id, kind: .task, targetID: task.id.uuidString)
    }

    private func isSmartLinkEligibleEvent(_ event: PlanningItem, for goal: GoalRecord, now: Date = Date()) -> Bool {
        guard event.isCalendarEvent,
              !event.completed,
              !goalStore.hasLink(goalID: goal.id, kind: .event, targetID: event.id.uuidString) else {
            return false
        }

        if let endDate = event.endDate {
            return endDate >= now
        }

        if let startDate = event.startDate {
            return startDate >= now
        }

        return false
    }

    private func goalSmartLinkSuggestion(from suggestion: AIService.GoalRelatedWorkSuggestionResponse.Suggestion) -> GoalSmartLinkSuggestion? {
        guard let kind = GoalLink.Kind(rawValue: suggestion.kind),
              !suggestion.targetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return GoalSmartLinkSuggestion(
            kind: kind,
            targetID: suggestion.targetID,
            title: suggestion.title,
            subtitle: suggestion.subtitle,
            reason: suggestion.reason
        )
    }

    private func runDynamicGoalAdaptIfNeeded(force: Bool = false) async {
        guard canUseDynamicGoalAI, isDynamicGoalAdaptEnabled, !isAdjustingGoals else { return }
        let now = Date().timeIntervalSince1970
        let interval = TimeInterval(max(1, dynamicGoalAdaptIntervalHours) * 3_600)
        guard force || lastGoalAdjustmentTimestamp == 0 || now - lastGoalAdjustmentTimestamp >= interval else { return }

        let activeGoals = goalStore.goals.filter { $0.status == .active }
        guard !activeGoals.isEmpty else { return }

        isAdjustingGoals = true
        defer {
            isAdjustingGoals = false
            lastGoalAdjustmentTimestamp = Date().timeIntervalSince1970
        }

        let activity = goalAdjustmentActivityPayload()
        for goal in activeGoals {
            do {
                let response = try await AIService.shared.adjustGoalProgress(
                    goal: goalAdjustmentPayload(for: goal),
                    activity: activity,
                    relatedWork: goalRelatedWorkPayload(for: goal),
                    candidates: smartLinkCandidatesPayload(for: goal)
                )
                applyGoalAdjustment(response, to: goal)
            } catch {
                ClientLog.debug("[Goals] Dynamic goal adaptation failed: \(AIService.userFacingErrorMessage(error))")
            }
        }
    }

    private func goalAdjustmentPayload(for goal: GoalRecord) -> [String: Any] {
        [
            "id": goal.id.uuidString,
            "outcome": goal.outcome,
            "successCriteria": goal.successCriteria,
            "nextAction": goal.nextAction,
            "notes": goal.notes,
            "targetDate": goal.targetDate?.ISO8601Format() ?? "",
            "status": goal.status.rawValue
        ]
    }

    private func goalAdjustmentActivityPayload() -> [String: Any] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        let completedTasks = visibleTodoItems
            .filter { $0.isCompleted && $0.modifiedAt >= cutoff }
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(40)
            .map { task in
                [
                    "id": task.id.uuidString,
                    "title": task.title,
                    "notes": [task.descriptionMarkdown ?? "", task.tags.joined(separator: " ")].joined(separator: "\n"),
                    "date": task.modifiedAt.ISO8601Format(),
                    "completed": task.isCompleted
                ] as [String: Any]
            }

        let events = visiblePlanningItems
            .filter { item in
                guard item.isCalendarEvent else { return false }
                return (item.startDate ?? item.endDate ?? Date.distantPast) >= cutoff
            }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
            .prefix(40)
            .map { event in
                [
                    "id": event.id.uuidString,
                    "title": event.title,
                    "notes": event.notes ?? "",
                    "date": event.startDate?.ISO8601Format() ?? "",
                    "completed": event.completed,
                    "subtitle": event.startDate?.formatted(date: .abbreviated, time: .shortened) ?? "Event"
                ] as [String: Any]
            }

        let sessions = sessionRecordStore.records
            .filter { $0.endTime >= cutoff }
            .sorted { $0.endTime > $1.endTime }
            .prefix(40)
            .map { session in
                [
                    "id": session.id.uuidString,
                    "title": sessionTitle(session),
                    "date": session.endTime.ISO8601Format(),
                    "completed": session.completed,
                    "durationSeconds": session.durationSeconds,
                    "interruptionCount": session.interruptionCount ?? 0
                ] as [String: Any]
            }

        return [
            "completedTasks": Array(completedTasks),
            "events": Array(events),
            "sessions": Array(sessions)
        ]
    }

    private func goalRelatedWorkPayload(for goal: GoalRecord) -> [String: Any] {
        let links = goalStore.links(for: goal.id)

        let tasks = links
            .filter { $0.kind == .task }
            .compactMap { link in
                visibleTodoItems.first { $0.id.uuidString == link.targetID }
            }
            .map { task in
                [
                    "id": task.id.uuidString,
                    "title": task.title,
                    "notes": [task.descriptionMarkdown ?? "", task.tags.joined(separator: " ")].joined(separator: "\n"),
                    "subtitle": task.isCompleted ? "Completed task" : "Task"
                ]
            }

        let events = links
            .filter { $0.kind == .event }
            .compactMap { link in
                visiblePlanningItems.first { $0.id.uuidString == link.targetID }
            }
            .map { event in
                [
                    "id": event.id.uuidString,
                    "title": event.title,
                    "notes": event.notes ?? "",
                    "subtitle": event.startDate?.formatted(date: .abbreviated, time: .shortened) ?? "Event"
                ]
            }

        let sessions = links
            .filter { $0.kind == .session }
            .compactMap { link in
                sessionRecordStore.records.first { $0.id.uuidString == link.targetID }
            }
            .map { session in
                [
                    "id": session.id.uuidString,
                    "title": sessionTitle(session),
                    "notes": "",
                    "subtitle": session.endTime.formatted(date: .abbreviated, time: .shortened)
                ]
            }

        return [
            "tasks": Array(tasks),
            "events": Array(events),
            "sessions": Array(sessions)
        ]
    }

    private func applyGoalAdjustment(_ response: AIService.GoalAdjustmentResponse, to goal: GoalRecord) {
        guard response.shouldUpdate else { return }
        var updated = goal

        if let successCriteria = cleaned(response.successCriteria), !successCriteria.isEmpty {
            updated.successCriteria = successCriteria
        }
        if let nextAction = cleaned(response.nextAction), !nextAction.isEmpty {
            updated.nextAction = nextAction
        }
        if let notes = cleaned(response.notes), !notes.isEmpty {
            updated.notes = notes
        }
        if let statusValue = cleaned(response.status),
           let status = GoalRecord.Status(rawValue: statusValue) {
            updated.status = status
        }

        if updated != goal {
            goalStore.updateGoal(updated)
        }

        for suggestedLink in response.suggestedLinks ?? [] {
            guard let kind = GoalLink.Kind(rawValue: suggestedLink.kind),
                  !goalStore.hasLink(goalID: goal.id, kind: kind, targetID: suggestedLink.targetID),
                  !isRelatedWorkLimitReached(for: goal) else {
                continue
            }
            _ = goalStore.addLink(goalID: goal.id, kind: kind, targetID: suggestedLink.targetID)
        }
    }

    private func cleaned(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeSmartLinkSuggestions(for goal: GoalRecord) -> [GoalSmartLinkSuggestion] {
        let goalWords = searchWords([
            goal.outcome,
            goal.successCriteria,
            goal.nextAction,
            goal.notes
        ].joined(separator: " "))

        var scored: [(suggestion: GoalSmartLinkSuggestion, score: Int)] = []

        for task in visibleTodoItems where isSmartLinkEligibleTask(task, for: goal) {
            let score = overlapScore(goalWords, searchWords([task.title, task.descriptionMarkdown ?? "", task.tags.joined(separator: " ")].joined(separator: " ")))
            if score > 0 {
                scored.append((
                    GoalSmartLinkSuggestion(
                        kind: .task,
                        targetID: task.id.uuidString,
                        title: task.title,
                        subtitle: languageManager.text("workspace.item.task"),
                        reason: languageManager.format("workspace.smart_link.reason.matching_terms", score)
                    ),
                    score
                ))
            }
        }

        for event in visiblePlanningItems where isSmartLinkEligibleEvent(event, for: goal) {
            let score = overlapScore(goalWords, searchWords([event.title, event.notes ?? ""].joined(separator: " ")))
            if score > 0 {
                scored.append((
                    GoalSmartLinkSuggestion(
                        kind: .event,
                        targetID: event.id.uuidString,
                        title: event.title,
                        subtitle: event.startDate?.formatted(date: .abbreviated, time: .shortened) ?? languageManager.text("workspace.item.event"),
                        reason: languageManager.format("workspace.smart_link.reason.matching_terms", score)
                    ),
                    score
                ))
            }
        }

        for session in sessionRecordStore.records.sorted(by: { $0.endTime > $1.endTime }).prefix(20)
            where !goalStore.hasLink(goalID: goal.id, kind: .session, targetID: session.id.uuidString) {
            let title = sessionTitle(session)
            let score = overlapScore(goalWords, searchWords(title))
            if score > 0 {
                scored.append((
                    GoalSmartLinkSuggestion(
                        kind: .session,
                        targetID: session.id.uuidString,
                        title: title,
                        subtitle: session.endTime.formatted(date: .abbreviated, time: .shortened),
                        reason: languageManager.format("workspace.smart_link.reason.matching_terms", score)
                    ),
                    score
                ))
            }
        }

        return scored
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.suggestion.title < right.suggestion.title
            }
            .prefix(8)
            .map(\.suggestion)
    }

    private func smartLinkSelectionBinding(for suggestion: GoalSmartLinkSuggestion) -> Binding<Bool> {
        Binding(
            get: { selectedSmartLinkSuggestionIDs.contains(suggestion.id) },
            set: { isSelected in
                if isSelected {
                    selectedSmartLinkSuggestionIDs.insert(suggestion.id)
                } else {
                    selectedSmartLinkSuggestionIDs.remove(suggestion.id)
                }
            }
        )
    }

    private func confirmSmartLinkSuggestions() {
        guard let goal = selectedGoal else { return }
        for suggestion in smartLinkSuggestions where selectedSmartLinkSuggestionIDs.contains(suggestion.id) {
            guard !isRelatedWorkLimitReached(for: goal) else {
                showRelatedWorkLimitMessage()
                return
            }
            _ = goalStore.addLink(goalID: goal.id, kind: suggestion.kind, targetID: suggestion.targetID)
        }
        limitMessage = nil
    }

    private func searchWords(_ text: String) -> Set<String> {
        let parts = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        return Set(parts)
    }

    private func overlapScore(_ left: Set<String>, _ right: Set<String>) -> Int {
        left.intersection(right).count
    }

    private func relatedWorkSummary(for goal: GoalRecord) -> (completedTasks: Int, totalTasks: Int, focusSessions: Int, focusSeconds: Int) {
        let links = goalStore.links(for: goal.id)
        let taskIDs = links
            .filter { $0.kind == .task }
            .compactMap { UUID(uuidString: $0.targetID) }
        let relatedTasks = visibleTodoItems.filter { taskIDs.contains($0.id) }
        let sessionIDs = links
            .filter { $0.kind == .session }
            .compactMap { UUID(uuidString: $0.targetID) }
        let sessions = sessionRecordStore.records.filter { sessionIDs.contains($0.id) }
        return (
            completedTasks: relatedTasks.filter(\.isCompleted).count,
            totalTasks: relatedTasks.count,
            focusSessions: sessions.count,
            focusSeconds: sessions.reduce(0) { $0 + $1.durationSeconds }
        )
    }

    private func progressText(for goal: GoalRecord) -> String? {
        let links = goalStore.links(for: goal.id)
        let taskIDs = links
            .filter { $0.kind == .task }
            .compactMap { UUID(uuidString: $0.targetID) }
        guard !taskIDs.isEmpty else {
            let sessionCount = links.filter { $0.kind == .session }.count
            return sessionCount > 0 ? languageManager.format("workspace.progress.related_focus_sessions", sessionCount) : nil
        }
        let relatedTasks = visibleTodoItems.filter { taskIDs.contains($0.id) }
        let completed = relatedTasks.filter(\.isCompleted).count
        return languageManager.format("workspace.progress.related_tasks_complete", completed, relatedTasks.count)
    }

    private func title(for link: GoalLink) -> String {
        switch link.kind {
        case .task:
            guard let id = UUID(uuidString: link.targetID),
                  let task = visibleTodoItems.first(where: { $0.id == id }) else {
                return languageManager.text("workspace.item.missing_task")
            }
            return task.title
        case .event:
            guard let id = UUID(uuidString: link.targetID),
                  let item = visiblePlanningItems.first(where: { $0.id == id }) else {
                return languageManager.text("workspace.item.missing_event")
            }
            return item.title
        case .session:
            guard let id = UUID(uuidString: link.targetID),
                  let session = sessionRecordStore.records.first(where: { $0.id == id }) else {
                return languageManager.text("workspace.item.missing_session")
            }
            return sessionTitle(session)
        }
    }

    private func subtitle(for link: GoalLink) -> String {
        switch link.kind {
        case .task:
            return languageManager.text("workspace.item.task")
        case .event:
            guard let id = UUID(uuidString: link.targetID),
                  let item = visiblePlanningItems.first(where: { $0.id == id }),
                  let startDate = item.startDate else {
                return languageManager.text("workspace.item.event")
            }
            return startDate.formatted(date: .abbreviated, time: .shortened)
        case .session:
            guard let id = UUID(uuidString: link.targetID),
                  let session = sessionRecordStore.records.first(where: { $0.id == id }) else {
                return languageManager.text("workspace.item.focus_session")
            }
            return "\(durationText(session.durationSeconds)) - \(session.endTime.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private func sessionTitle(_ session: SessionRecord) -> String {
        let taskTitle: String
        if let taskId = session.taskId,
           let task = visibleTodoItems.first(where: { $0.id == taskId }) {
            taskTitle = task.title
        } else {
            taskTitle = session.sessionType == .focus ? languageManager.text("workspace.item.focus_session") : session.sessionType.rawValue.capitalized
        }
        return "\(taskTitle) - \(durationText(session.durationSeconds))"
    }

    private func durationText(_ seconds: Int) -> String {
        guard seconds > 0 else { return languageManager.format("workspace.duration.minutes_short", 0) }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        return languageManager.format("workspace.duration.minutes_short", minutes)
    }

    private func icon(for kind: GoalLink.Kind) -> String {
        switch kind {
        case .task:
            return "checklist"
        case .event:
            return "calendar"
        case .session:
            return "timer"
        }
    }

    private func statusIcon(for status: GoalRecord.Status) -> String {
        switch status {
        case .active:
            return "target"
        case .paused:
            return "pause.circle"
        case .completed:
            return "checkmark.circle"
        }
    }

    private func localizedStatusTitle(_ status: GoalRecord.Status) -> String {
        switch status {
        case .active:
            return languageManager.text("workspace.status.active")
        case .paused:
            return languageManager.text("workspace.status.paused")
        case .completed:
            return languageManager.text("workspace.status.completed")
        }
    }
}

private struct GoalWorkspaceCard<Content: View>: View {
    @AppStorage(AppearanceMode.appStorageKey) private var appearanceModeRawValue = AppearanceMode.standard.rawValue

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var appearanceMode: AppearanceMode {
        AppearanceMode.resolved(from: appearanceModeRawValue)
    }

    var body: some View {
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
            .frame(maxWidth: .infinity, minHeight: 248, alignment: .topLeading)
    }
}

private struct GoalListRow: View {
    @EnvironmentObject private var languageManager: LanguageManager

    let goal: GoalRecord
    let isSelected: Bool
    let progressText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.outcome)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                StatusPill(title: localizedStatusTitle(goal.status), icon: statusIcon)
            }

            if !goal.nextAction.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageManager.text("workspace.goal.field.next_action"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(goal.nextAction)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                if let targetDate = goal.targetDate {
                    Label(targetDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                Text(progressText ?? languageManager.text("workspace.related_work.none_yet"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusIcon: String {
        switch goal.status {
        case .active:
            return "target"
        case .paused:
            return "pause.circle"
        case .completed:
            return "checkmark.circle"
        }
    }

    private func localizedStatusTitle(_ status: GoalRecord.Status) -> String {
        switch status {
        case .active:
            return languageManager.text("workspace.status.active")
        case .paused:
            return languageManager.text("workspace.status.paused")
        case .completed:
            return languageManager.text("workspace.status.completed")
        }
    }
}

private struct StatusPill: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
    }
}

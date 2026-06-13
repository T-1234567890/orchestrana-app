import SwiftUI

private enum WorkspaceFeatureFlags {
    static let notesEnabled = false
    static let knowledgeEnabled = false
    static let mapEnabled = true
    static let locationContextEnabled = false
}

private enum WorkspaceSection: CaseIterable, Identifiable {
    case notes
    case goals
    case knowledge
    case map

    var id: Self { self }

    func title(languageManager: LanguageManager) -> String {
        switch self {
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

@MainActor
struct GoalWorkspaceView: View {
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
    @State private var selectedWorkspaceSection: WorkspaceSection = .goals
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
    @State private var isNavigationVisible = true
    @State private var previousScrollOffset: CGFloat = 0
    @State private var hasScrollPosition = false
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

    private var appearanceMode: AppearanceMode {
        AppearanceMode.resolved(from: appearanceModeRawValue)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: WorkspaceScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("workspaceScroll")).minY
                        )
                }
                .frame(height: 0)

                VStack(alignment: .leading, spacing: 18) {
                    if let limitMessage {
                        Text(limitMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 2)
                    }

                    workspaceContent
                }
                .padding(.top, 82)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: "workspaceScroll")

            workspaceNavigation
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .opacity(isNavigationVisible ? 1 : 0)
                .offset(y: isNavigationVisible ? 0 : -28)
                .allowsHitTesting(isNavigationVisible)
                .animation(.spring(response: 0.24, dampingFraction: 0.9), value: isNavigationVisible)
        }
        .onPreferenceChange(WorkspaceScrollOffsetPreferenceKey.self) { offset in
            updateNavigationVisibility(for: offset)
        }
        .onReceive(NotificationCenter.default.publisher(for: .workspaceShowMap)) { _ in
            if WorkspaceFeatureFlags.mapEnabled {
                selectedWorkspaceSection = .map
            }
        }
        .onAppear {
            if selectedGoalID == nil {
                selectedGoalID = goalStore.goals.first?.id
            }
            Task {
                await runDynamicGoalAdaptIfNeeded()
            }
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
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch selectedWorkspaceSection {
        case .goals, .notes, .knowledge:
            goalsOverviewLayout
        case .map:
            MapWorkspaceView(
                locationStore: locationStore,
                todoStore: todoStore,
                planningStore: planningStore,
                calendarManager: calendarManager,
                goalStore: goalStore,
                featureGate: featureGate,
                onScrollOffsetChange: updateNavigationVisibility(for:)
            )
        }
    }

    private func updateNavigationVisibility(for offset: CGFloat) {
        guard hasScrollPosition else {
            hasScrollPosition = true
            previousScrollOffset = offset
            return
        }

        let delta = offset - previousScrollOffset
        previousScrollOffset = offset

        if abs(delta) < 1.5 {
            return
        }

        if offset > -6 {
            isNavigationVisible = true
        } else if delta < 0 {
            isNavigationVisible = false
        } else if delta > 0 {
            isNavigationVisible = true
        }
    }

    @ViewBuilder
    private var workspaceNavigation: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                workspaceNavigationContent
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
        } else {
            workspaceNavigationContent
                .appRoundedSurface(
                    mode: appearanceMode,
                    cornerRadius: 16,
                    glassMaterial: .ultraThinMaterial,
                    standardLevel: .panel,
                    showsShadow: appearanceMode == .standard
                )
        }
    }

    private var workspaceNavigationContent: some View {
        HStack(spacing: 8) {
            ForEach(visibleWorkspaceSections) { section in
                workspaceNavigationItem(for: section)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func workspaceNavigationItem(for section: WorkspaceSection) -> some View {
        let isEnabled = section == .goals || section == .map
        let isSelected = section == selectedWorkspaceSection
        let foreground = isSelected ? Color.accentColor : Color.primary
        let label = HStack(spacing: 7) {
            Image(systemName: section.systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foreground)
                .frame(width: 16)
            Text(section.title(languageManager: languageManager))
                .foregroundStyle(foreground)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .frame(height: 36)
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : 0.5)

        if #available(macOS 26.0, *) {
            Button {
                selectedWorkspaceSection = section
            } label: {
                label
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .glassEffect(
                .regular.interactive(isEnabled),
                in: Capsule()
            )
        } else {
            Button {
                selectedWorkspaceSection = section
            } label: {
                label
                    .background(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }

    private var visibleWorkspaceSections: [WorkspaceSection] {
        WorkspaceSection.allCases.filter { section in
            switch section {
            case .notes:
                return WorkspaceFeatureFlags.notesEnabled
            case .goals:
                return true
            case .knowledge:
                return WorkspaceFeatureFlags.knowledgeEnabled
            case .map:
                return WorkspaceFeatureFlags.mapEnabled
            }
        }
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

private struct WorkspaceScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

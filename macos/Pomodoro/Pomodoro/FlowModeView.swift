import SwiftUI
import Combine
import AppKit
import FirebaseAuth
import StoreKit
import UniformTypeIdentifiers

/// Flow Mode: a low-density state with a single focus surface (clock) and a clear exit.
/// UI-only: no settings or persistence changes.
@MainActor
struct FlowModeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var fullscreenFocusBackdropStore: FullscreenFocusBackdropStore
    @EnvironmentObject private var flowWindowManager: FlowWindowManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var featureGate = FeatureGate.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @StateObject private var layoutStore = FlowLayoutStore.shared

    // Countdown overlay is opt-in; default off to keep the clock calm (time awareness, not urgency).
    var showsCountdown: Bool = false
    var showsBackgroundLayer: Bool = true
    var isFullscreenPresentation: Bool = false
    var exitAction: () -> Void = {}

    @State private var countdownVisible: Bool
    @State private var isPresented = false
    @State private var sessionDissolve = false
    @State private var timerHovering = false
    @GestureState private var timerPressing = false
    @State private var fullscreenHovering = false
    @GestureState private var fullscreenPressing = false
    @State private var exitHovering = false
    @GestureState private var exitPressing = false
    @State private var previewBillingCycle: PlanBillingCycle = .yearly
    @State private var timerSize: CGSize = .zero
    @State private var controlsSize: CGSize = .zero
    @State private var dragStartCenters: [FlowLayoutItem: CGPoint] = [:]

    init(
        showsCountdown: Bool = false,
        showsBackgroundLayer: Bool = true,
        isFullscreenPresentation: Bool = false,
        exitAction: @escaping () -> Void = {}
    ) {
        self.showsCountdown = showsCountdown
        self.showsBackgroundLayer = showsBackgroundLayer
        self.isFullscreenPresentation = isFullscreenPresentation
        self.exitAction = exitAction
        _countdownVisible = State(initialValue: showsCountdown)
    }

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .background(alignment: .center) {
                if showsBackgroundLayer {
                    flowBackgroundComposite
                }
            }
            .overlay(alignment: .center) {
                flowContent
            }
        // Enter/exit feel like settling in: fade + slight scale with Apple-like easing.
        .opacity(flowOpacity)
        .scaleEffect(flowScale)
        // Flow Mode is a presentation-only context: entering/leaving must not alter timers or tasks.
        .onAppear {
            appState.isInFlowMode = true
            guard !reduceMotion else { isPresented = true; return }
            withAnimation(.easeOut(duration: 0.25)) { isPresented = true }
            triggerSessionDissolve()
        }
        .onDisappear {
            appState.isInFlowMode = false
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.20)) { isPresented = false }
        }
        .onChange(of: sessionVisualToken) { _, _ in
            triggerSessionDissolve()
        }
        .onChange(of: featureGate.tier) { _, _ in
            flowWindowManager.completePremiumPreviewIfUnlocked()
        }
        .overlay {
            if activePremiumPreview != nil {
                premiumPreviewOverlay
            }
        }
        .sheet(isPresented: purchaseLoginPromptBinding) {
            PurchaseAuthenticationSheet()
                .environmentObject(authViewModel)
                .environmentObject(localizationManager)
        }
        .task(id: authViewModel.currentUser?.uid) {
            await authViewModel.preparePurchaseReadiness()
            layoutStore.load(for: authViewModel.currentUser?.uid)
        }
    }

    // MARK: - UI Sections

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizationManager.text("flow.focus_state"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(localizationManager.text("flow.calm_time_awareness"))
                    .font(.caption)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            Spacer()
            controlGroups
        }
    }

    private var controlGroups: some View {
            HStack(alignment: .center, spacing: 10) {
                timerControl
                exitControl
                fullscreenSettingsControl
            }
        }

    private var timerControl: some View {
        Button {
            handleTimerTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.title3.weight(.semibold))
                Text(localizationManager.text("timer.timer"))
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(timerScale)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: timerPressing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: timerHovering)
        .onHover { timerHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($timerPressing) { _, state, _ in state = true }
        )
        .accessibilityLabel(localizationManager.text("flow.accessibility.show_pomodoro_timer"))
    }

    private var exitControl: some View {
        Button(action: exitAction) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                Text(localizationManager.text("flow.exit"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(exitScale)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: exitPressing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: exitHovering)
        .onHover { exitHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($exitPressing) { _, state, _ in state = true }
        )
        .help(localizationManager.text("flow.help.return_main_workspace"))
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel(localizationManager.text("flow.accessibility.exit_mode"))
    }

    private var fullscreenSettingsControl: some View {
        Group {
            if isActiveFullscreenPresentation || featureGate.canUseCustomFlowLayout {
                HStack(alignment: .center, spacing: 0) {
                    fullscreenButton

                    Divider()
                        .frame(height: 20)

                    flowSettingsMenu(label: {
                        settingsIcon
                    })
                }
            } else {
                fullscreenButton
            }
        }
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var fullscreenButton: some View {
        Button {
            handleFullscreenButton()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(fullscreenScale)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: fullscreenPressing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fullscreenHovering)
        .onHover { fullscreenHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($fullscreenPressing) { _, state, _ in state = true }
        )
        .help(localizationManager.text(isActiveFullscreenPresentation ? "focus.fullscreen.exit" : "focus.fullscreen.enter"))
    }

    private var settingsIcon: some View {
        Image(systemName: "gearshape.fill")
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }

    private func flowSettingsMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            if isActiveFullscreenPresentation {
                Button {
                    handleChooseImage()
                } label: {
                    SwiftUI.Label(localizationManager.text("focus.fullscreen.choose_image"), systemImage: "photo")
                }

                Button {
                    handleChooseFolder()
                } label: {
                    SwiftUI.Label(localizationManager.text("focus.fullscreen.choose_folder"), systemImage: "photo.on.rectangle")
                }

                Toggle(isOn: autoRotateBinding) {
                    SwiftUI.Label(localizationManager.text("focus.fullscreen.auto_rotate"), systemImage: "arrow.triangle.2.circlepath")
                }
            }

            if featureGate.canUseCustomFlowLayout {
                if isActiveFullscreenPresentation {
                    Divider()
                }

                Toggle(isOn: customLayoutBinding) {
                    SwiftUI.Label("Customize Layout", systemImage: "hand.draw")
                }

                if layoutStore.configuration.customLayoutEnabled {
                    Button("Reset Layout") {
                        layoutStore.resetLayout(for: currentLayoutUserID)
                    }
                }
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .help(localizationManager.text("focus.fullscreen.settings"))
    }

    private func clockStack(in size: CGSize) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let currentDate = context.date
            VStack(spacing: 8) {
                Text(wallClockString(for: currentDate))
                    .font(clockFont(for: size))
                    // Fixed neutral tone: Flow clock should not signal urgency or timer state.
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .kerning(-0.8)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 10)
                    .layoutPriority(1) // keep the clock dominant; prevents compression by surrounding content
                    // Calm numeric morph to reduce tick anxiety.
                    .contentTransition(.numericText())
                    // Minutes-only animation: barely-there dissolve when minutes roll.
                    .animation(minuteMorphAnimation, value: minuteMorphToken(for: currentDate))
                    .accessibilityLabel(localizationManager.text("flow.accessibility.current_time"))

                if let currentTaskTitle {
                    Text(currentTaskTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 18)
                        .transition(.opacity)
                }

                if shouldShowTimerChip {
                    timerChip
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var timerChip: some View {
        HStack(spacing: 8) {
            Image(systemName: timerIconName)
                .font(.callout)
            Text(timerTimeString)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                // Seconds update every second: keep animation extremely subtle.
                .animation(secondTickAnimation, value: timerTimeString)
            Text(timerStatusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        // Soft dissolve on session changes; keeps interaction live.
        .opacity(sessionOpacity)
        .blur(radius: sessionBlur)
        // Overlay is intentionally lightweight; tap pauses/resumes, long-press or secondary click hides.
        .onTapGesture { toggleActiveTimer() }
        .onLongPressGesture { countdownVisible.toggle() }
        .gesture(
            TapGesture()
                .modifiers(.command) // secondary-like quick hide
                .onEnded { countdownVisible.toggle() }
        )
    }

    // MARK: - Helpers

    private func wallClockString(for date: Date) -> String {
        // System wall-clock time; locale-aware 12/24h, no seconds for calmer display.
        date.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .locale(localizationManager.effectiveLocale)
        )
    }
    
    /// Token used to trigger a soft morph only when minutes change.
    private func minuteMorphToken(for date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .locale(localizationManager.effectiveLocale)
        )
    }
    
    /// Token representing session state changes for dissolve animation.
    private var sessionVisualToken: String {
        "\(appState.isInFlowMode)-\(appState.pomodoro.state.rawValue)"
    }

    private var countdownTimeString: String {
        let totalSeconds = max(0, Int(appState.countdown.remainingSeconds))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var timerTimeString: String {
        let totalSeconds = max(0, appState.pomodoro.remainingSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var shouldShowTimerChip: Bool {
        appState.pomodoro.state != .idle
    }

    private var currentTaskTitle: String? {
        guard let title = appState.currentPlanTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    // MARK: - Clock styling

    private func clockFont(for size: CGSize) -> Font {
        _ = size
        return .system(size: 104, weight: .heavy, design: .rounded).monospacedDigit()
    }

    // MARK: - Timer wiring (observes existing engines, never duplicates logic)

    private enum ActiveTimer {
        case pomodoro(state: TimerState, remaining: Int)
        case countdown(state: TimerState, remaining: Int)
    }

    private var currentActiveTimer: ActiveTimer? {
        if appState.pomodoro.state != .idle {
            return .pomodoro(state: appState.pomodoro.state, remaining: appState.pomodoro.remainingSeconds)
        }
        if appState.countdown.state != .idle {
            return .countdown(state: appState.countdown.state, remaining: appState.countdown.remainingSeconds)
        }
        return nil
    }

    private var activeTimerRemainingSeconds: Int {
        switch currentActiveTimer {
        case .pomodoro(_, let remaining): return remaining
        case .countdown(_, let remaining): return remaining
        case .none: return appState.pomodoro.remainingSeconds
        }
    }

    private var timerIconName: String {
        switch appState.pomodoro.state {
        case .running, .breakRunning:
            return "timer"
        case .paused, .breakPaused:
            return "pause.circle"
        case .idle:
            return "timer"
        }
    }

    private var timerStatusLabel: String {
        switch appState.pomodoro.state {
        case .running:
            return localizationManager.text("timer.state.running")
        case .breakRunning:
            return localizationManager.text("timer.mode.break")
        case .paused, .breakPaused:
            return localizationManager.text("timer.state.paused")
        case .idle:
            return localizationManager.text("timer.state.idle")
        }
    }

    private func handleTimerTap() {
        // Reveal timer state and control the shared Pomodoro engine.
        countdownVisible = true
        startOrTogglePomodoro()
    }

    private func toggleActiveTimer() {
        switch appState.pomodoro.state {
        case .idle:
            appState.startPomodoro()
        case .running, .breakRunning:
            appState.pomodoro.pause()
        case .paused, .breakPaused:
            appState.pomodoro.resume()
        }
    }

    private func startOrTogglePomodoro() {
        switch appState.pomodoro.state {
        case .idle:
            appState.startPomodoro()
        case .running, .breakRunning:
            appState.pomodoro.pause()
        case .paused, .breakPaused:
            appState.pomodoro.resume()
        }
    }

    private func handleFullscreenButton() {
        flowWindowManager.toggleFlowFullscreen()
    }

    private var flowContent: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if isCustomLayoutActive {
                    customLayoutCanvas(in: proxy.size, safeAreaInsets: proxy.safeAreaInsets)
                } else {
                    defaultLayoutCanvas(in: proxy.size)
                }

                topBar
                    .padding(.horizontal, horizontalChromePadding)
                    .padding(.top, verticalChromePadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(contentForegroundStyle)
        }
    }

    private func defaultLayoutCanvas(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topBarReservedHeight)

            Spacer(minLength: 0)

            clockStack(in: size)
                .padding(.horizontal, horizontalChromePadding)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            AmbientAudioStrip()
                .padding(.horizontal, horizontalChromePadding)
                .padding(.bottom, bottomControlsPadding)
        }
    }

    private func customLayoutCanvas(in size: CGSize, safeAreaInsets: EdgeInsets) -> some View {
        ZStack(alignment: .topLeading) {
            clockStack(in: size)
                .padding(.horizontal, 12)
                .measureSize { timerSize = $0 }
                .position(resolvedPosition(for: .timer, in: size, safeAreaInsets: safeAreaInsets))
                .gesture(layoutDragGesture(for: .timer, in: size, safeAreaInsets: safeAreaInsets))
                .zIndex(2)

            AmbientAudioStrip()
                .measureSize { controlsSize = $0 }
                .position(resolvedPosition(for: .controls, in: size, safeAreaInsets: safeAreaInsets))
                .gesture(layoutDragGesture(for: .controls, in: size, safeAreaInsets: safeAreaInsets))
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var flowBackgroundComposite: some View {
        ZStack {
            backgroundMediaLayer
            backgroundEffectLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var backgroundMediaLayer: some View {
        if let currentImageURL = flowBackgroundImageURL {
            FullscreenFocusBackdropImage(url: currentImageURL)
        } else {
            Color.clear
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var backgroundEffectLayer: some View {
        if let currentImageURL = flowBackgroundImageURL {
            ZStack {
                FullscreenFocusBackdropImage(
                    url: currentImageURL,
                    opacity: 0.32,
                    blurRadius: 24,
                    scale: 1.06
                )
                LinearGradient(
                    colors: [Color.black.opacity(0.30), Color.black.opacity(0.52)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        } else {
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                Color.white.opacity(0.04)
                    .ignoresSafeArea()
            }
        }
    }

    private var contentForegroundStyle: AnyShapeStyle {
        if flowBackgroundImageURL != nil {
            return AnyShapeStyle(.white.opacity(0.96))
        }
        return AnyShapeStyle(.primary)
    }

    private var premiumPreviewOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.black.opacity(0.38))
                    .ignoresSafeArea()

                let modalWidth = min(920, max(760, proxy.size.width - 64))
                let modalHeight = min(720, max(560, proxy.size.height - 64))

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(premiumPreviewTitle)
                            .font(.title2.weight(.semibold))

                        Text(premiumPreviewMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        PlansComparisonView(
                            featureGate: featureGate,
                            subscriptionStore: subscriptionStore,
                            emphasizedTier: .plus,
                            billingCycleSelection: $previewBillingCycle
                        )

                        HStack {
                            Button(localizationManager.text("common.cancel")) {
                                flowWindowManager.dismissPremiumPreview()
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button(previewPurchaseButtonTitle) {
                                Task {
                                    guard let product = selectedPreviewUpgradeProduct else { return }
                                    guard await handlePreviewPurchaseIntent() else { return }
                                    await subscriptionStore.purchase(product)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isPreviewPurchaseButtonDisabled)
                        }
                    }
                    .padding(24)
                }
                .frame(width: modalWidth, height: modalHeight)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(32)
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: activePremiumPreview)
    }

    private var selectedPreviewUpgradeProduct: Product? {
        let productID: String
        switch previewBillingCycle {
        case .monthly:
            productID = "pomodoro.plus.monthly"
        case .yearly:
            productID = "pomodoro.plus.yearly"
        }
        return subscriptionStore.product(for: productID)
    }

    private var isPreviewUpgradeCurrentPlan: Bool {
        guard let selectedPreviewUpgradeProduct else { return false }
        return subscriptionStore.currentProductID == selectedPreviewUpgradeProduct.id
    }

    private var autoRotateBinding: Binding<Bool> {
        Binding(
            get: { fullscreenFocusBackdropStore.autoRotateEnabled },
            set: { newValue in
                flowWindowManager.setBackgroundAutoRotateEnabled(newValue)
            }
        )
    }

    private func handleChooseImage() {
        flowWindowManager.requestCustomBackgroundImage()
    }

    private func handleChooseFolder() {
        flowWindowManager.requestCustomBackgroundFolder()
    }

    private func handlePreviewPurchaseIntent() async -> Bool {
        guard authViewModel.isAuthenticated else {
            await MainActor.run {
                authViewModel.isPurchaseLoginPromptPresented = true
            }
            return false
        }
        return authViewModel.canStartPurchase
    }
}

private extension FlowModeView {
    var purchaseLoginPromptBinding: Binding<Bool> {
        Binding(
            get: { authViewModel.isPurchaseLoginPromptPresented },
            set: { isPresented in
                if !isPresented {
                    authViewModel.dismissPurchaseLoginPrompt()
                }
            }
        )
    }

    var previewPurchaseButtonTitle: String {
        if !authViewModel.isAuthenticated {
            return "Sign in to continue"
        }
        if authViewModel.isLoading || authViewModel.isPreparingPurchase {
            return "Loading…"
        }
        return localizationManager.text("tasks.ai_assistant.upgrade")
    }

    var isPreviewPurchaseButtonDisabled: Bool {
        guard !isPreviewUpgradeCurrentPlan, selectedPreviewUpgradeProduct != nil else { return true }
        if !authViewModel.isAuthenticated {
            return false
        }
        return !authViewModel.canStartPurchase
    }

    var isActiveFullscreenPresentation: Bool {
        flowWindowManager.isFullscreenPresentation || isFullscreenPresentation
    }

    var flowBackgroundImageURL: URL? {
        guard isActiveFullscreenPresentation else { return nil }
        guard featureGate.canUseCustomFlowBackgrounds else { return nil }
        return fullscreenFocusBackdropStore.currentImageURL
    }

    var activePremiumPreview: FlowWindowManager.PremiumFeature? {
        flowWindowManager.activePremiumPreview
    }

    var layoutConfiguration: FlowLayoutConfiguration {
        featureGate.canUseCustomFlowLayout ? layoutStore.configuration : .defaultValue
    }

    var currentLayoutUserID: String? {
        authViewModel.currentUser?.uid
    }

    var isCustomLayoutActive: Bool {
        featureGate.canUseCustomFlowLayout && layoutStore.configuration.customLayoutEnabled
    }

    var customLayoutBinding: Binding<Bool> {
        Binding(
            get: { layoutStore.configuration.customLayoutEnabled },
            set: { isEnabled in
                layoutStore.setCustomLayoutEnabled(isEnabled, for: currentLayoutUserID)
            }
        )
    }

    var topBarReservedHeight: CGFloat {
        88
    }

    var horizontalChromePadding: CGFloat {
        28
    }

    var verticalChromePadding: CGFloat {
        20
    }

    var bottomControlsPadding: CGFloat {
        20
    }

    func resolvedPosition(for item: FlowLayoutItem, in size: CGSize, safeAreaInsets: EdgeInsets) -> CGPoint {
        let normalizedPoint = layoutConfiguration.position(for: item)
        let itemSize = measuredSize(for: item)
        let point = CGPoint(
            x: size.width * normalizedPoint.x,
            y: size.height * normalizedPoint.y
        )
        return clampedPoint(point, for: item, itemSize: itemSize, in: size, safeAreaInsets: safeAreaInsets)
    }

    func measuredSize(for item: FlowLayoutItem) -> CGSize {
        switch item {
        case .timer:
            return timerSize == .zero ? CGSize(width: 420, height: 220) : timerSize
        case .controls:
            return controlsSize == .zero ? CGSize(width: 620, height: 86) : controlsSize
        }
    }

    func clampedPoint(
        _ point: CGPoint,
        for item: FlowLayoutItem,
        itemSize: CGSize,
        in size: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> CGPoint {
        let minX = horizontalChromePadding + itemSize.width / 2
        let maxX = max(minX, size.width - horizontalChromePadding - itemSize.width / 2)
        let minY = safeAreaInsets.top + topBarReservedHeight + itemSize.height / 2
        let maxY = max(minY, size.height - safeAreaInsets.bottom - bottomControlsPadding - itemSize.height / 2)

        var clamped = CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )

        let centerX = size.width / 2
        if abs(clamped.x - centerX) <= 24 {
            clamped.x = centerX
        }
        if item == .controls, abs(clamped.y - maxY) <= 28 {
            clamped.y = maxY
        }

        return clamped
    }

    func collisionAdjustedPoint(
        _ point: CGPoint,
        for item: FlowLayoutItem,
        in size: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> CGPoint {
        let itemSize = measuredSize(for: item)
        let otherItem: FlowLayoutItem = item == .timer ? .controls : .timer
        let otherSize = measuredSize(for: otherItem)
        let otherCenter = resolvedPosition(for: otherItem, in: size, safeAreaInsets: safeAreaInsets)
        let gap: CGFloat = 24
        let currentFrame = CGRect(
            x: point.x - itemSize.width / 2,
            y: point.y - itemSize.height / 2,
            width: itemSize.width,
            height: itemSize.height
        )
        let otherFrame = CGRect(
            x: otherCenter.x - otherSize.width / 2,
            y: otherCenter.y - otherSize.height / 2,
            width: otherSize.width,
            height: otherSize.height
        )

        guard currentFrame.intersects(otherFrame) else { return point }

        let direction: CGFloat = item == .timer ? -1 : 1
        let shiftedPoint = CGPoint(
            x: point.x,
            y: point.y + direction * ((itemSize.height + otherSize.height) / 2 + gap)
        )
        return clampedPoint(shiftedPoint, for: item, itemSize: itemSize, in: size, safeAreaInsets: safeAreaInsets)
    }

    func normalizedPoint(_ point: CGPoint, in size: CGSize, fallback: FlowLayoutPoint) -> FlowLayoutPoint {
        guard size.width > 0, size.height > 0 else { return fallback }
        return FlowLayoutPoint(
            x: point.x / size.width,
            y: point.y / size.height
        )
    }

    func layoutDragGesture(for item: FlowLayoutItem, in size: CGSize, safeAreaInsets: EdgeInsets) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let startCenter = dragStartCenters[item] ?? resolvedPosition(for: item, in: size, safeAreaInsets: safeAreaInsets)
                if dragStartCenters[item] == nil {
                    dragStartCenters[item] = startCenter
                }

                let translatedPoint = CGPoint(
                    x: startCenter.x + value.translation.width,
                    y: startCenter.y + value.translation.height
                )
                let clamped = clampedPoint(
                    translatedPoint,
                    for: item,
                    itemSize: measuredSize(for: item),
                    in: size,
                    safeAreaInsets: safeAreaInsets
                )
                let adjusted = collisionAdjustedPoint(clamped, for: item, in: size, safeAreaInsets: safeAreaInsets)
                let fallback = layoutConfiguration.position(for: item)
                layoutStore.setPosition(normalizedPoint(adjusted, in: size, fallback: fallback), for: item, userID: currentLayoutUserID)
            }
            .onEnded { _ in
                dragStartCenters[item] = nil
            }
    }

    var premiumPreviewTitle: String {
        switch activePremiumPreview {
        case .fullscreen:
            return localizationManager.text("focus.fullscreen.preview_title")
        case .customBackground:
            return localizationManager.text("focus.background.preview_title")
        case .none:
            return localizationManager.text("focus.fullscreen.preview_title")
        }
    }

    var premiumPreviewMessage: String {
        switch activePremiumPreview {
        case .fullscreen:
            return localizationManager.text("focus.fullscreen.preview_message")
        case .customBackground:
            return localizationManager.text("focus.background.preview_message")
        case .none:
            return localizationManager.text("focus.fullscreen.preview_message")
        }
    }

    var timerScale: CGFloat {
        guard !reduceMotion else { return 1.0 }
        return timerPressing ? 0.98 : 1.0
    }
    
    var exitScale: CGFloat {
        guard !reduceMotion else { return 1.0 }
        return exitPressing ? 0.98 : 1.0
    }

    var fullscreenScale: CGFloat {
        guard !reduceMotion, !isActiveFullscreenPresentation else { return 1.0 }
        return fullscreenPressing ? 0.98 : 1.0
    }
    
    var flowScale: CGFloat {
        guard !reduceMotion, !isActiveFullscreenPresentation else { return 1.0 }
        return isPresented ? 1.0 : 0.98
    }
    
    var flowOpacity: Double {
        guard !reduceMotion else { return 1.0 }
        return isPresented ? 1.0 : 0.0
    }
    
    var timeUpdateAnimation: Animation? {
        // Very light easing to make digits "flow" instead of tick.
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }
    
    var minuteMorphAnimation: Animation? {
        // Slightly fuller dissolve for minute transitions; still calm and short.
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }
    
    var secondTickAnimation: Animation? {
        // Near-invisible change each second to avoid flicker stress.
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }
    
    var sessionTransitionAnimation: Animation {
        .easeOut(duration: 0.2)
    }
    
    var sessionOpacity: Double {
        guard !reduceMotion else { return 1.0 }
        return sessionDissolve ? 0.6 : 1.0
    }
    
    var sessionBlur: CGFloat {
        guard !reduceMotion else { return 0 }
        return sessionDissolve ? 1.2 : 0
    }
    
    func triggerSessionDissolve() {
        guard !reduceMotion else { return }
        sessionDissolve = true
        withAnimation(sessionTransitionAnimation) {
            sessionDissolve = false
        }
    }
}

enum FlowLayoutItem: String, CaseIterable, Hashable {
    case timer
    case controls
}

struct FlowLayoutPoint: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
}

struct FlowLayoutConfiguration: Codable, Equatable {
    static let defaultTimerPosition = FlowLayoutPoint(x: 0.5, y: 0.43)
    static let defaultControlsPosition = FlowLayoutPoint(x: 0.5, y: 0.9)
    static let defaultValue = FlowLayoutConfiguration()

    var customLayoutEnabled = false
    var timerPosition = defaultTimerPosition
    var controlsPosition = defaultControlsPosition

    func position(for item: FlowLayoutItem) -> FlowLayoutPoint {
        switch item {
        case .timer:
            return timerPosition
        case .controls:
            return controlsPosition
        }
    }
}

@MainActor
final class FlowLayoutStore: ObservableObject {
    static let shared = FlowLayoutStore()

    @Published private(set) var configuration = FlowLayoutConfiguration.defaultValue

    private let defaults = UserDefaults.standard
    private let storageKeyPrefix = "flow.layout.configuration"
    private var activeUserStorageID = "guest"

    private init() {
        configuration = .defaultValue
    }

    func load(for userID: String?) {
        let storageID = storageID(for: userID)
        activeUserStorageID = storageID
        configuration = readConfiguration(for: storageID)
    }

    func setCustomLayoutEnabled(_ isEnabled: Bool, for userID: String?) {
        ensureLoaded(for: userID)
        var next = configuration
        next.customLayoutEnabled = isEnabled
        persist(next, for: activeUserStorageID)
    }

    func setPosition(_ position: FlowLayoutPoint, for item: FlowLayoutItem, userID: String?) {
        ensureLoaded(for: userID)
        var next = configuration
        switch item {
        case .timer:
            next.timerPosition = position
        case .controls:
            next.controlsPosition = position
        }
        persist(next, for: activeUserStorageID)
    }

    func resetLayout(for userID: String?) {
        ensureLoaded(for: userID)
        persist(.defaultValue, for: activeUserStorageID)
    }

    private func ensureLoaded(for userID: String?) {
        let storageID = storageID(for: userID)
        guard storageID != activeUserStorageID else { return }
        load(for: userID)
    }

    private func storageID(for userID: String?) -> String {
        guard let userID, !userID.isEmpty else { return "guest" }
        return userID
    }

    private func storageKey(for storageID: String) -> String {
        "\(storageKeyPrefix).\(storageID)"
    }

    private func readConfiguration(for storageID: String) -> FlowLayoutConfiguration {
        let key = storageKey(for: storageID)
        guard let data = defaults.data(forKey: key),
              let configuration = try? JSONDecoder().decode(FlowLayoutConfiguration.self, from: data) else {
            return .defaultValue
        }
        return configuration
    }

    private func persist(_ configuration: FlowLayoutConfiguration, for storageID: String) {
        self.configuration = configuration
        let key = storageKey(for: storageID)
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension View {
    func measureSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

// MARK: - Ambient Audio

private struct AmbientAudioStrip: View {
    @EnvironmentObject private var musicController: MusicController
    @EnvironmentObject private var audioSourceStore: AudioSourceStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ambientVolume: Double = 0.4
    @State private var sliderEditing = false
    @State private var sliderHover = false

    var body: some View {
        Group {
            if audioSourceStore.externalMediaDetected, let media = audioSourceStore.externalMediaMetadata {
                externalStrip(media)
            } else {
                ambientStrip
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 620)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            ambientVolume = Double(musicController.focusVolume)
        }
    }

    private var ambientStrip: some View {
        HStack(spacing: 14) {
            Button(action: toggleAmbient) {
                Image(systemName: musicController.playbackState == .playing ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                soundIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .cornerRadius(6)
                    .foregroundStyle(.primary.opacity(0.85))

                VStack(alignment: .leading, spacing: 2) {
                    Text(ambientTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(localizationManager.text("audio.ambient_local"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Slider(
                value: $ambientVolume,
                in: 0...1,
                onEditingChanged: { editing in
                    if reduceMotion {
                        sliderEditing = editing
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { sliderEditing = editing }
                    }
                },
                minimumValueLabel: Image(systemName: "speaker.wave.1.fill").foregroundStyle(.secondary),
                maximumValueLabel: Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary),
                label: { EmptyView() }
            )
            .frame(width: 180)
            .tint(.primary.opacity(0.65))
            // Smooth track fill animation; matches macOS slider feel.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: ambientVolume)
            // Knob scales very slightly while dragging; no layout change.
            .scaleEffect(sliderEditing ? 1.03 : 1.0, anchor: .center)
            // Hover brightens softly to indicate focus without glow.
            .opacity((sliderHover || sliderEditing) ? 1.0 : 0.95)
            .onHover { hovering in
                if reduceMotion {
                    sliderHover = hovering
                } else {
                    withAnimation(.easeOut(duration: 0.18)) { sliderHover = hovering }
                }
            }
            .accessibilityLabel(localizationManager.text("audio.accessibility.ambient_volume"))
            .onChange(of: ambientVolume) { _, newValue in
                audioSourceStore.setVolume(Float(newValue))
            }
        }
    }

    private func externalStrip(_ media: ExternalMedia) -> some View {
        HStack(spacing: 14) {
            artwork(for: media)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizationManager.format("audio.now_playing_source", media.source.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(media.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(media.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private func toggleAmbient() {
        audioSourceStore.togglePlayPause()
    }

    private var ambientTitle: String {
        if case .ambient(let type) = audioSourceStore.audioSource {
            return type.displayName
        }
        return musicController.currentFocusSound == .off
            ? localizationManager.text("audio.sound.white_noise")
            : musicController.currentFocusSound.displayName
    }

    private var soundIcon: Image {
        switch musicController.currentFocusSound {
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

    @ViewBuilder
    private func artwork(for media: ExternalMedia) -> some View {
        if let artwork = media.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

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
        let fullscreenFocusBackdropStore = FullscreenFocusBackdropStore()
        return FlowModeView()
            .environmentObject(appState)
            .environmentObject(musicController)
            .environmentObject(audioSourceStore)
            .environmentObject(fullscreenFocusBackdropStore)
    }
}

@MainActor
final class FullscreenFocusBackdropStore: ObservableObject {
    private enum PendingSelection {
        case image(URL)
        case folder(URL, [URL])
    }

    @Published private(set) var imageURLs: [URL] = []
    @Published private(set) var currentImageURL: URL?
    @Published private(set) var previewImageURL: URL?
    @Published var autoRotateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoRotateEnabled, forKey: Self.autoRotateKey)
            restartRotationIfNeeded()
        }
    }

    private static let imageBookmarkKey = "fullscreen.focus.background.image.bookmark"
    private static let bookmarkKey = "fullscreen.focus.background.bookmark"
    private static let autoRotateKey = "fullscreen.focus.background.autoRotate"
    private static let supportedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff"])
    private var currentIndex = 0
    private var rotationTask: Task<Void, Never>?
    private var pendingSelection: PendingSelection?

    init() {
        self.autoRotateEnabled = UserDefaults.standard.object(forKey: Self.autoRotateKey) as? Bool ?? true
        Task { await restorePersistedFolderIfNeeded() }
    }

    deinit {
        rotationTask?.cancel()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = LocalizationManager.shared.text("focus.fullscreen.choose_folder")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        Task { await setFolder(url) }
    }

    func chooseFolderPreview() async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = LocalizationManager.shared.text("focus.fullscreen.choose_folder")

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        _ = url.startAccessingSecurityScopedResource()
        let urls = await loadImageURLs(from: url)
        guard let firstURL = urls.first else { return false }
        pendingSelection = .folder(url, urls)
        previewImageURL = firstURL
        return true
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = LocalizationManager.shared.text("focus.fullscreen.choose_image")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        Task { await setImage(url) }
    }

    func chooseImagePreview() async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = LocalizationManager.shared.text("focus.fullscreen.choose_image")

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        _ = url.startAccessingSecurityScopedResource()
        pendingSelection = .image(url)
        previewImageURL = url
        return true
    }

    func clearPreviewSelection() {
        previewImageURL = nil
        pendingSelection = nil
    }

    func commitPreviewSelectionIfNeeded() async {
        guard let pendingSelection else { return }
        switch pendingSelection {
        case .image(let url):
            await setImage(url)
        case .folder(let folderURL, let urls):
            applyFolder(folderURL, urls: urls)
        }
        clearPreviewSelection()
    }

    func advanceBackground() {
        guard imageURLs.count > 1 else { return }
        currentIndex = (currentIndex + 1) % imageURLs.count
        currentImageURL = imageURLs[currentIndex]
    }

    private func setFolder(_ url: URL) async {
        UserDefaults.standard.removeObject(forKey: Self.imageBookmarkKey)
        if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkKey)
        }
        let urls = await loadImageURLs(from: url)
        applyFolder(url, urls: urls)
    }

    private func setImage(_ url: URL) async {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.imageBookmarkKey)
        }

        imageURLs = [url]
        currentIndex = 0
        currentImageURL = url
        restartRotationIfNeeded()
    }

    private func restorePersistedFolderIfNeeded() async {
        if let imageBookmarkData = UserDefaults.standard.data(forKey: Self.imageBookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: imageBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                imageURLs = [url]
                currentIndex = 0
                currentImageURL = url
                previewImageURL = nil
                restartRotationIfNeeded()
                return
            }
        }

        guard let bookmarkData = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        _ = url.startAccessingSecurityScopedResource()
        let urls = await loadImageURLs(from: url)
        applyFolder(url, urls: urls)
    }

    private func applyFolder(_ folderURL: URL, urls: [URL]) {
        UserDefaults.standard.removeObject(forKey: Self.imageBookmarkKey)
        if let bookmarkData = try? folderURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.bookmarkKey)
        }
        imageURLs = urls
        currentIndex = 0
        currentImageURL = urls.first
        previewImageURL = nil
        restartRotationIfNeeded()
    }

    private func loadImageURLs(from folderURL: URL) async -> [URL] {
        let supportedExtensions = Self.supportedExtensions
        return await Task.detached(priority: .utility) { () -> [URL] in
            let keys: [URLResourceKey] = [.isRegularFileKey]
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            var collected: [URL] = []
            while let nextObject = enumerator.nextObject() as? URL {
                let fileURL = nextObject
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                let ext = fileURL.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }
                collected.append(fileURL)
            }

            return collected.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }.value
    }

    private func restartRotationIfNeeded() {
        rotationTask?.cancel()
        guard autoRotateEnabled, imageURLs.count > 1 else { return }
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.advanceBackground()
                }
            }
        }
    }
}

private struct FullscreenFocusBackdropImage: View {
    let url: URL
    var opacity: Double = 1.0
    var blurRadius: CGFloat = 0
    var scale: CGFloat = 1.0
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .blur(radius: blurRadius)
                    .opacity(opacity)
            } else {
                Color.black.opacity(opacity == 1.0 ? 0.92 : 0.28)
            }
        }
        .ignoresSafeArea()
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let loadedImage = await Task.detached(priority: .utility) {
            NSImage(contentsOf: url)
        }.value
        await MainActor.run {
            image = loadedImage
        }
    }
}

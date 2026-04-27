//
//  OnboardingFlowView.swift
//  Pomodoro
//
//  Created by OpenAI on 2025-02-01.
//

import AppKit
import FirebaseAuth
import SwiftUI
import UserNotifications

@MainActor
struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var featureGate = FeatureGate.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared

    @State private var flow: [OnboardingStep] = []
    @State private var index = 0
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingAuthorization = false
    @State private var showEmailLogin = false
    @State private var activeProvider: AuthProvider?
    @State private var upgradePaywallContext: SubscriptionPaywallContext?

    private enum NavigationDirection {
        case forward
        case backward
    }

    private var step: OnboardingStep {
        guard flow.indices.contains(index) else { return .welcome }
        return flow[index]
    }

    private var isLastStep: Bool {
        index == flow.count - 1
    }

    private var shouldShowUpgradeAwareness: Bool {
        let tier = PlanTier.from(featureTier: subscriptionStore.currentTier)
        return tier == .free && subscriptionStore.currentProductID == nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    topBar

                    Spacer(minLength: shellSpacerLength)

                    contentColumn(in: proxy.size)

                    Spacer(minLength: shellSpacerLength)
                }
                .padding(.horizontal, 42)
                .padding(.vertical, shellVerticalPadding)
                .frame(maxWidth: 980, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $upgradePaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: subscriptionStore
            )
            .environmentObject(authViewModel)
            .environmentObject(localizationManager)
        }
        .onAppear {
            rebuildFlow(resetIndex: true)
            refreshAuthorizationStatusIfNeeded()
        }
        .onChange(of: step) { _, _ in
            refreshAuthorizationStatusIfNeeded()
        }
        .onChange(of: shouldShowUpgradeAwareness) { _, isVisible in
            if !isVisible && step == .upgrade {
                onboardingState.markCompleted()
            } else {
                rebuildFlow(resetIndex: false)
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated, step == .login else { return }
            advance()
        }
        .task(id: authViewModel.currentUser?.uid) {
            await subscriptionStore.ensureProductsLoaded()
            await authViewModel.preparePurchaseReadiness()
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Orchestrana")
                        .font(.system(size: 14, weight: .semibold))
                    Text(localizationManager.text("onboarding.progress_label"))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let topActionTitle {
                Button(topActionTitle) {
                    handleTopAction()
                }
                .orchestranaButton(.subtle)
                .font(.system(size: 13, weight: .medium))
            }
        }
    }

    private func contentColumn(in availableSize: CGSize) -> some View {
        let width = contentColumnWidth(in: availableSize)

        return VStack(alignment: .leading, spacing: 14) {
            stepPanel(width: width)
            footerBar(width: width)
        }
        .frame(maxWidth: width, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func stepPanel(width: CGFloat) -> some View {
        ZStack {
            OnboardingGlassPanel(isCompact: step == .features) {
                VStack(alignment: .leading, spacing: panelContentSpacing) {
                    if step != .welcome {
                        stepHeader
                    }
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step.id)
                .transition(stepTransition)
            }
        }
        .frame(maxWidth: width)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(panelAnimation, value: step.id)
    }

    private func contentColumnWidth(in availableSize: CGSize) -> CGFloat {
        min(panelWidth, max(availableSize.width - 120, 640))
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localizationManager.text(step.titleKey))
                .font(onboardingHeadingFont(size: 31, weight: .semibold))
                .tracking(-0.35)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitleKey = step.subtitleKey {
                Text(localizationManager.text(subtitleKey))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let descriptionKey = step.descriptionKey {
                Text(localizationManager.text(descriptionKey))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: step == .welcome ? 560 : 640, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeContent
        case .features:
            featuresContent
        case .notifications:
            notificationsContent
        case .permissions:
            permissionsContent
        case .menuBar:
            menuBarContent
        case .login:
            loginContent
        case .upgrade:
            upgradeContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .center, spacing: 26) {
            VStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text("Orchestrana")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.92))

                VStack(alignment: .center, spacing: 10) {
                    Text(localizationManager.text("onboarding.welcome.title"))
                        .font(onboardingHeadingFont(size: 42, weight: .semibold))
                        .tracking(-0.8)
                        .multilineTextAlignment(.center)

                    Text(localizationManager.text("onboarding.welcome.subtitle"))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 470)
                }
            }

            welcomeFeaturePreview
                .frame(maxWidth: 620)
        }
        .frame(maxWidth: .infinity)
    }

    private var welcomeFeaturePreview: some View {
        HStack(spacing: 10) {
            ForEach(WelcomePreviewItem.allCases) { item in
                VStack(spacing: 8) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.72))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(localizationManager.text(item.titleKey))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .opacity(reduceMotion ? 1 : 0.96)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var onboardingPrimaryLabelFont: Font {
        .system(size: 14, weight: .semibold)
    }

    private func onboardingHeadingFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    private var onboardingBodyFont: Font {
        .system(size: 14, weight: .regular)
    }

    private var onboardingFeatureTitleFont: Font {
        .system(size: 15, weight: .semibold)
    }

    private var onboardingFeatureBodyFont: Font {
        .system(size: 13, weight: .regular)
    }

    private var onboardingMetaFont: Font {
        .system(size: 12, weight: .medium)
    }

    private var shellVerticalPadding: CGFloat {
        step == .features ? 22 : 30
    }

    private var shellSpacerLength: CGFloat {
        step == .features ? 18 : 28
    }

    private var panelContentSpacing: CGFloat {
        switch step {
        case .welcome:
            return 20
        case .features:
            return 18
        default:
            return 24
        }
    }

    private var featuresContent: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10, alignment: .top),
            count: 3
        )

        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(OnboardingFeature.allCases) { feature in
                    featureCard(feature)
                }
            }
        }
    }

    private func featureCard(_ feature: OnboardingFeature) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(localizationManager.text(feature.titleKey))
                        .font(onboardingFeatureTitleFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(localizationManager.text(feature.subtitleKey))
                        .font(onboardingFeatureBodyFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if feature.isComingSoon {
                Text(localizationManager.text("onboarding.features.coming_soon"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.045), in: Capsule())
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 108)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var notificationsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                notificationOptionCard(.minimal)
                notificationOptionCard(.rich)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(onboardingBodyFont)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: Capsule())

            if authorizationStatus == .denied {
                Button(localizationManager.text("common.open_system_settings")) {
                    openNotificationSettings()
                }
                .orchestranaButton(.secondary)
                .controlSize(.large)
            }
        }
    }

    private func notificationOptionCard(_ option: OnboardingNotificationOption) -> some View {
        let isSelected = selectedNotificationOption == option

        return Button {
            appState.notificationDeliveryStyle = option == .minimal ? .system : .inApp
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: option.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.85) : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.28) : Color.primary.opacity(0.05))
                        )

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(localizationManager.text(option.titleKey))
                        .font(onboardingFeatureTitleFont)
                    Text(localizationManager.text(option.subtitleKey))
                        .font(onboardingFeatureBodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.28) : Color.white.opacity(0.10), lineWidth: isSelected ? 1.2 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0.03), radius: isSelected ? 14 : 8, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 14) {
                permissionRow(
                    symbol: "calendar",
                    title: localizationManager.text("onboarding.permissions.calendar_title"),
                    detail: localizationManager.text("onboarding.permissions.read_write")
                )

                permissionRow(
                    symbol: "checklist",
                    title: localizationManager.text("onboarding.permissions.reminders_title"),
                    detail: localizationManager.text("onboarding.permissions.read_write")
                )
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )

            Text(appState.calendarReminderPermissionStatusText)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func permissionRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(onboardingFeatureTitleFont)
                Text(detail)
                    .font(onboardingFeatureBodyFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(localizationManager.text("permissions.authorized"))
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .opacity(0.7)
        }
    }

    private var menuBarContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 10) {
                        Image(systemName: "timer")
                        Text("25:00")
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                    }
                    .foregroundStyle(.primary.opacity(0.88))
                }

                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(localizationManager.text("onboarding.menu_bar_tip.hint"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var loginContent: some View {
        if authViewModel.isLoggedIn {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "person.crop.circle.fill.badge.checkmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(authViewModel.user?.displayName ?? localizationManager.text("settings.account.signed_in"))
                            .font(onboardingFeatureTitleFont)
                        Text(authViewModel.currentUserEmail.isEmpty ? localizationManager.text("settings.account.no_email") : authViewModel.currentUserEmail)
                            .font(onboardingFeatureBodyFont)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.thinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                AuthProviderButton(
                    provider: .apple,
                    title: AuthProvider.apple.title(using: localizationManager),
                    isLoading: activeProvider == .apple && authViewModel.isAuthenticating,
                    isDisabled: authViewModel.isAuthenticating
                ) {
                    Task { @MainActor in
                        authViewModel.clearError()
                        await performProviderSignIn(provider: .apple) {
                            try await authViewModel.signInWithApple()
                        }
                    }
                }

                AuthProviderButton(
                    provider: .google,
                    title: AuthProvider.google.title(using: localizationManager),
                    isLoading: activeProvider == .google && authViewModel.isAuthenticating,
                    isDisabled: authViewModel.isAuthenticating
                ) {
                    Task { @MainActor in
                        authViewModel.clearError()
                        await performProviderSignIn(provider: .google) {
                            try await authViewModel.signInWithGoogle()
                        }
                    }
                }

                AuthProviderButton(
                    provider: .email,
                    title: AuthProvider.email.title(using: localizationManager),
                    isLoading: false,
                    isDisabled: authViewModel.isAuthenticating
                ) {
                    withAnimation(panelAnimation) {
                        authViewModel.clearError()
                        showEmailLogin.toggle()
                    }
                }

                if showEmailLogin {
                    EmailLoginView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !showEmailLogin, let message = authViewModel.authError, !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var upgradeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                upgradeFeatureRow(
                    symbol: "cpu",
                    title: localizationManager.text("onboarding.upgrade.feature.models_title"),
                    detail: localizationManager.text("onboarding.upgrade.feature.models_body")
                )
                upgradeFeatureRow(
                    symbol: "chart.bar.xaxis",
                    title: localizationManager.text("onboarding.upgrade.feature.analysis_title"),
                    detail: localizationManager.text("onboarding.upgrade.feature.analysis_body")
                )
                upgradeFeatureRow(
                    symbol: "waveform.path.ecg",
                    title: localizationManager.text("onboarding.upgrade.feature.analytics_title"),
                    detail: localizationManager.text("onboarding.upgrade.feature.analytics_body")
                )
                upgradeFeatureRow(
                    symbol: "calendar.badge.clock",
                    title: localizationManager.text("onboarding.upgrade.feature.planning_title"),
                    detail: localizationManager.text("onboarding.upgrade.feature.planning_body")
                )
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )

            Button(localizationManager.text("onboarding.upgrade.view_plans")) {
                upgradePaywallContext = SubscriptionPaywallContext(
                    requiredTier: .plus,
                    title: localizationManager.text("onboarding.upgrade.view_plans_title"),
                    message: localizationManager.text("onboarding.upgrade.view_plans_body")
                )
            }
            .orchestranaButton(.secondary)
        }
    }

    private func upgradeFeatureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(onboardingFeatureTitleFont)
                Text(detail)
                    .font(onboardingFeatureBodyFont)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func footerBar(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 16) {
            progressIndicator

            Spacer(minLength: 24)

            HStack(spacing: 14) {
                if index > 0 {
                    Button(localizationManager.text("onboarding.back")) {
                        back()
                    }
                    .orchestranaButton(.secondary)
                    .controlSize(.large)
                    .font(onboardingPrimaryLabelFont)
                    .frame(minWidth: 112, minHeight: 46)
                }

                if let footerActionTitle {
                    Button(footerActionTitle) {
                        performFooterAction()
                    }
                    .orchestranaButton(.primary)
                    .controlSize(.large)
                    .font(onboardingPrimaryLabelFont)
                    .frame(minWidth: 168, minHeight: 46)
                    .disabled(isFooterActionDisabled)
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var progressIndicator: some View {
        HStack(spacing: 10) {
            ForEach(Array(flow.enumerated()), id: \.offset) { offset, item in
                Capsule()
                    .fill(offset == index ? Color.accentColor : Color.white.opacity(0.22))
                    .frame(width: offset == index ? 28 : 8, height: 8)
                    .animation(panelAnimation, value: index)
                    .accessibilityLabel(localizationManager.text(item.titleKey))
            }
        }
    }

    private var topActionTitle: String? {
        switch step {
        case .welcome:
            return localizationManager.text("onboarding.skip")
        case .notifications, .permissions:
            return localizationManager.text("onboarding.not_now")
        case .features, .menuBar, .login, .upgrade:
            return nil
        }
    }

    private var footerActionTitle: String? {
        switch step {
        case .welcome:
            return localizationManager.text("onboarding.get_started")
        case .features:
            return localizationManager.text("onboarding.continue")
        case .notifications:
            return localizationManager.text("onboarding.enable_notifications")
        case .permissions:
            return localizationManager.text("onboarding.permissions.allow_access")
        case .menuBar:
            return localizationManager.text("onboarding.got_it")
        case .login:
            return localizationManager.text("onboarding.continue")
        case .upgrade:
            return isLastStep ? localizationManager.text("onboarding.finish") : localizationManager.text("onboarding.continue")
        }
    }

    private var isFooterActionDisabled: Bool {
        switch step {
        case .notifications:
            return isRequestingAuthorization
        case .permissions:
            return isRequestingAuthorization
        default:
            return false
        }
    }

    private var selectedNotificationOption: OnboardingNotificationOption {
        get {
            appState.notificationDeliveryStyle == .system ? .minimal : .rich
        }
        set {
            appState.notificationDeliveryStyle = newValue == .minimal ? .system : .inApp
        }
    }

    private var statusText: String {
        switch authorizationStatus {
        case .authorized, .provisional:
            return localizationManager.text("onboarding.notifications.enabled")
        case .denied:
            return localizationManager.text("onboarding.notifications.denied")
        case .notDetermined:
            return localizationManager.text("onboarding.notifications.not_requested")
        case .ephemeral:
            return localizationManager.text("onboarding.notifications.ephemeral")
        @unknown default:
            return localizationManager.text("onboarding.notifications.unavailable")
        }
    }

    private var statusColor: Color {
        switch authorizationStatus {
        case .authorized, .provisional:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        case .ephemeral:
            return .blue
        @unknown default:
            return .gray
        }
    }

    private var panelWidth: CGFloat {
        switch step {
        case .welcome:
            return 700
        case .features:
            return 820
        case .notifications, .permissions, .login, .upgrade:
            return 760
        case .menuBar:
            return 660
        }
    }

    private var panelAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.24)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private func performFooterAction() {
        switch step {
        case .welcome, .features:
            advance()
        case .notifications:
            requestAuthorizationAndAdvance()
        case .permissions:
            requestPermissionsAndAdvance()
        case .menuBar:
            onboardingState.markMenuBarTipSeen()
            advance()
        case .login, .upgrade:
            advance()
        }
    }

    private func handleTopAction() {
        switch step {
        case .welcome:
            onboardingState.markCompleted()
        case .notifications:
            advance()
        case .permissions:
            onboardingState.markPermissionsPrompted()
            onboardingState.markEventKitRequestCalled()
            advance()
        case .features, .menuBar, .login, .upgrade:
            break
        }
    }

    private func refreshAuthorizationStatusIfNeeded() {
        guard step == .notifications else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                authorizationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestAuthorizationAndAdvance() {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        appState.requestSystemNotificationAuthorization { status in
            authorizationStatus = status
            isRequestingAuthorization = false
            advance()
        }
    }

    private func requestPermissionsAndAdvance() {
        guard !isRequestingAuthorization else { return }
        isRequestingAuthorization = true
        Task { @MainActor in
            await appState.requestCalendarAndReminderAccessIfNeeded()
            isRequestingAuthorization = false
            onboardingState.markPermissionsPrompted()
            onboardingState.markEventKitRequestCalled()
            advance()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    private func advance() {
        guard !flow.isEmpty else {
            onboardingState.markCompleted()
            return
        }

        navigationDirection = .forward
        if index + 1 < flow.count {
            index += 1
        } else {
            onboardingState.markCompleted()
        }
    }

    private func back() {
        guard index > 0 else { return }
        navigationDirection = .backward
        index -= 1
    }

    private func rebuildFlow(resetIndex: Bool) {
        let currentStep = step
        var newFlow: [OnboardingStep] = [
            .welcome,
            .features,
            .notifications,
            .permissions,
            .menuBar,
            .login
        ]

        if shouldShowUpgradeAwareness {
            newFlow.append(.upgrade)
        }

        flow = newFlow

        if resetIndex {
            index = 0
        } else if let preservedIndex = newFlow.firstIndex(of: currentStep) {
            index = preservedIndex
        } else {
            index = min(index, max(newFlow.count - 1, 0))
        }
    }

    @MainActor
    private func performProviderSignIn(
        provider: AuthProvider,
        _ operation: @escaping @MainActor () async throws -> Void
    ) async {
        activeProvider = provider
        defer { activeProvider = nil }
        do {
            try await operation()
        } catch {}
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.accentColor.opacity(0.08),
                    Color.black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.07))
                    .frame(width: 280, height: 280)
                    .blur(radius: 96)
                    .offset(x: -240, y: -170)

                Circle()
                    .fill(Color.white.opacity(0.09))
                    .frame(width: 240, height: 240)
                    .blur(radius: 100)
                    .offset(x: 260, y: 120)

                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 460, height: 180)
                    .blur(radius: 110)
                    .offset(x: 80, y: -120)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private enum OnboardingStep: String, Identifiable, CaseIterable {
    case welcome
    case features
    case notifications
    case permissions
    case menuBar
    case login
    case upgrade

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .welcome:
            return "onboarding.welcome.title"
        case .features:
            return "onboarding.features.title"
        case .notifications:
            return "onboarding.notifications.title"
        case .permissions:
            return "onboarding.permissions.title"
        case .menuBar:
            return "onboarding.menu_bar.title"
        case .login:
            return "onboarding.login.title"
        case .upgrade:
            return "onboarding.upgrade.title"
        }
    }

    var subtitleKey: String? {
        switch self {
        case .welcome:
            return "onboarding.welcome.subtitle"
        default:
            return nil
        }
    }

    var descriptionKey: String? {
        switch self {
        case .welcome:
            return "onboarding.welcome.description"
        case .features:
            return "onboarding.features.description"
        case .notifications:
            return "onboarding.notifications.description"
        case .permissions:
            return "onboarding.permissions.description"
        case .menuBar:
            return "onboarding.menu_bar.description"
        case .login:
            return "onboarding.login.description"
        case .upgrade:
            return "onboarding.upgrade.description"
        }
    }
}

private enum OnboardingFeature: String, CaseIterable, Identifiable {
    case aiPlanning
    case smartScheduling
    case focusTimer
    case insights
    case subtasks
    case markdownNotes
    case calendarSync
    case notes
    case knowledgeBase

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .aiPlanning:
            return "wand.and.stars"
        case .smartScheduling:
            return "calendar.badge.clock"
        case .focusTimer:
            return "timer"
        case .insights:
            return "chart.xyaxis.line"
        case .subtasks:
            return "list.bullet.indent"
        case .markdownNotes:
            return "text.document"
        case .calendarSync:
            return "calendar"
        case .notes:
            return "note.text"
        case .knowledgeBase:
            return "books.vertical"
        }
    }

    var titleKey: String {
        "onboarding.features.\(rawValue).title"
    }

    var subtitleKey: String {
        "onboarding.features.\(rawValue).subtitle"
    }

    var isComingSoon: Bool {
        self == .notes || self == .knowledgeBase
    }
}

private enum OnboardingNotificationOption: String, CaseIterable, Identifiable {
    case minimal
    case rich

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .minimal:
            return "bell.badge"
        case .rich:
            return "app.badge"
        }
    }

    var titleKey: String {
        "onboarding.notifications.\(rawValue).title"
    }

    var subtitleKey: String {
        "onboarding.notifications.\(rawValue).subtitle"
    }
}

private enum WelcomePreviewItem: String, CaseIterable, Identifiable {
    case ai
    case focus
    case calendar
    case insights
    case notes

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .ai:
            return "cpu"
        case .focus:
            return "timer"
        case .calendar:
            return "calendar"
        case .insights:
            return "chart.xyaxis.line"
        case .notes:
            return "note.text"
        }
    }

    var titleKey: String {
        "onboarding.welcome.preview.\(rawValue)"
    }
}

private struct OnboardingGlassPanel<Content: View>: View {
    let isCompact: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, isCompact ? 26 : 34)
        .padding(.vertical, isCompact ? 24 : 32)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 22, x: 0, y: 14)
    }
}

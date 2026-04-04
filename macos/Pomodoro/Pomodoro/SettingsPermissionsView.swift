import EventKit
import AppKit
import FirebaseAuth
import StoreKit
import SwiftUI

/// Settings view with centralized permission overview.
/// Shows status and enable buttons for Notifications, Calendar, and Reminders.
@MainActor
struct SettingsPermissionsView: View {
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject private var featureGate = FeatureGate.shared
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var showAdvancedAccountTools = false
    @State private var upgradePaywallContext: SubscriptionPaywallContext?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(localizationManager.text("permissions.title"))
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(localizationManager.text("permissions.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 16) {
                permissionRow(
                    icon: "bell.fill",
                    title: localizationManager.text("permissions.notifications"),
                    status: permissionsManager.notificationStatusText,
                    isAuthorized: permissionsManager.isNotificationsAuthorized,
                    action: {
                        Task {
                            await permissionsManager.requestNotificationPermission()
                        }
                    }
                )
                
                Divider()
                
                permissionRow(
                    icon: "calendar",
                    title: localizationManager.text("permissions.calendar"),
                    status: permissionsManager.calendarStatusText,
                    isAuthorized: permissionsManager.isCalendarAuthorized,
                    isDenied: permissionsManager.calendarStatus == .denied || permissionsManager.calendarStatus == .restricted,
                    action: {
                        Task {
                            await permissionsManager.requestCalendarPermission()
                        }
                    }
                )
                
                Divider()
                
                permissionRow(
                    icon: "checklist",
                    title: localizationManager.text("permissions.reminders"),
                    status: permissionsManager.remindersStatusText,
                    isAuthorized: permissionsManager.isRemindersAuthorized,
                    isDenied: permissionsManager.remindersStatus == .denied || permissionsManager.remindersStatus == .restricted,
                    action: {
                        Task {
                            await permissionsManager.requestRemindersPermission()
                        }
                    }
                )
            }
            .padding(16)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
            
            Text(localizationManager.text("permissions.note.reminders_optional"))
                .font(.caption)
                .foregroundStyle(.secondary)

            aiSubscriptionSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .onAppear {
            permissionsManager.refreshAllStatuses()
            subscriptionStore.start()
            Task { @MainActor in
                await featureGate.refreshSubscriptionStatusIfNeeded()
            }
        }
        .alert(localizationManager.text("permissions.calendar.denied_title"), isPresented: $permissionsManager.showCalendarDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("permissions.calendar.denied_message"))
        }
        .alert(localizationManager.text("permissions.reminders.denied_title"), isPresented: $permissionsManager.showRemindersDeniedAlert) {
            Button(localizationManager.text("common.open_settings")) {
                permissionsManager.openSystemSettings()
            }
            Button(localizationManager.text("common.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.text("permissions.reminders.denied_message"))
        }
        .sheet(item: $upgradePaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: subscriptionStore
            )
        }

        Divider()

        DisclosureGroup(
            "Account & Cloud (Cloud/AI Features Coming Soon)",
            isExpanded: $showAdvancedAccountTools
        ) {
            CloudSettingsSection()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
        .accessibilityLabel("Account & Cloud (Cloud/AI Features Coming Soon)")
        .accessibilityIdentifier("settings.account_cloud_disclosure")
        .font(.subheadline.weight(.medium))
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)

        Button {
            guard let url = URL(string: "https://pomodoro-app.tech/policies.html") else {
                return
            }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)

                Text("Privacy & Policies")
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var aiSubscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localizationManager.text("settings.ai_subscription.title"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                statusRow(
                    label: localizationManager.text("settings.ai_subscription.current_plan"),
                    value: currentPlanLabel
                )

                subscriptionManagementContent

                aiPlanningContent

                if let subscriptionEndAt = featureGate.subscriptionEndAt,
                          featureGate.tier == .plus || featureGate.tier == .pro {
                    statusRow(
                        label: localizationManager.text("settings.ai_subscription.subscription_ends"),
                        value: formattedDate(subscriptionEndAt)
                    )
                }

                if let resetAt = featureGate.allowanceResetAt {
                    statusRow(
                        label: localizationManager.text("settings.ai_subscription.usage_resets"),
                        value: formattedDate(resetAt)
                    )
                }

                if !displayedAIUsageProgressItems.isEmpty {
                    VStack(spacing: 14) {
                        ForEach(displayedAIUsageProgressItems, id: \.title) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))

                                ProgressView(value: item.usedRatio)
                                    .tint(usageColor(for: item.usedRatio))

                                Text(localizationManager.format("settings.ai_usage.used_percentage", item.usedPercentage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var subscriptionManagementContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Compare Plans")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    Task {
                        await subscriptionStore.restorePurchases()
                    }
                } label: {
                    if subscriptionStore.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(subscriptionStore.isRestoring)
            }

            PlansComparisonView(
                featureGate: featureGate,
                subscriptionStore: subscriptionStore
            )

            if let errorMessage = subscriptionStore.errorMessage,
               !errorMessage.isEmpty {
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

    @ViewBuilder
    private var aiPlanningContent: some View {
        switch aiPlanningDisplayMode {
        case .upgrade:
            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.text("settings.ai_planning.title"))
                    .font(.subheadline.weight(.semibold))

                Text(localizationManager.text("settings.ai_planning.free_description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(localizationManager.text("tasks.ai_assistant.upgrade")) {
                    presentUpgradePaywall(
                        requiredTier: .plus,
                        title: localizationManager.text("settings.ai_planning.title"),
                        message: localizationManager.text("settings.ai_planning.free_description")
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        case .deepSeek:
            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.text("settings.ai_planning.title"))
                    .font(.subheadline.weight(.semibold))

                statusRow(
                    label: localizationManager.text("settings.ai_planning.available_model"),
                    value: "DeepSeek"
                )
            }
        case .deepSeekAndGemini:
            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.text("settings.ai_planning.title"))
                    .font(.subheadline.weight(.semibold))

                VStack(alignment: .leading, spacing: 8) {
                    modelRow("Gemini")
                    modelRow("DeepSeek")
                }
            }
        }
    }

    private var displayedAIUsageProgressItems: [FeatureGate.AIUsageProgress] {
        switch aiPlanningDisplayMode {
        case .upgrade:
            return []
        case .deepSeek:
            return featureGate.aiUsageProgressItems.filter { $0.title == "DeepSeek" }
        case .deepSeekAndGemini:
            return featureGate.aiUsageProgressItems.filter { $0.title == "DeepSeek" || $0.title == "Gemini Flash" }
        }
    }

    private var aiPlanningDisplayMode: AIPlanningDisplayMode {
        switch featureGate.tier {
        case .plus, .beta:
            return .deepSeek
        case .pro, .developer:
            return .deepSeekAndGemini
        case .free, .expired:
            return .upgrade
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

    private var currentPlanLabel: String {
        switch featureGate.tier {
        case .free:
            return localizationManager.text("settings.ai_subscription.plan.free")
        case .plus:
            return localizationManager.text("settings.ai_subscription.plan.plus")
        case .pro:
            return localizationManager.text("settings.ai_subscription.plan.pro")
        case .developer:
            return localizationManager.text("settings.ai_subscription.plan.developer")
        case .beta:
            return localizationManager.text("settings.ai_subscription.plan.beta")
        case .expired:
            return localizationManager.text("settings.ai_subscription.plan.expired")
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    private func presentUpgradePaywall(requiredTier: PlanTier, title: String, message: String) {
        upgradePaywallContext = SubscriptionPaywallContext(
            requiredTier: requiredTier,
            title: title,
            message: message
        )
    }

    @ViewBuilder
    private func statusRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func modelRow(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
    
    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        status: String,
        isAuthorized: Bool,
        isDenied: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isAuthorized ? .green : (isDenied ? .red : .secondary))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isAuthorized ? .green : (isDenied ? .red : .secondary))
            }
            
            Spacer()
            
            if isAuthorized {
                Text(localizationManager.text("permissions.authorized"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            } else if isDenied {
                Button(action: action) {
                    Text(localizationManager.text("permissions.request_again"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: action) {
                    Text(localizationManager.text("permissions.enable"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private enum AIPlanningDisplayMode {
    case upgrade
    case deepSeek
    case deepSeekAndGemini
}

enum PlanBillingCycle: String, CaseIterable, Identifiable {
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Annually"
        }
    }
}

enum PlanTier: String, Identifiable {
    case free
    case plus
    case pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro: return "Pro"
        }
    }
}

extension PlanTier {
    var upgradeTitle: String {
        switch self {
        case .free:
            return "Free"
        case .plus:
            return "Upgrade to Plus"
        case .pro:
            return "Upgrade to Pro"
        }
    }

    static func from(featureTier: FeatureGate.Tier) -> PlanTier {
        switch featureTier {
        case .pro, .developer:
            return .pro
        case .plus, .beta:
            return .plus
        case .free, .expired:
            return .free
        }
    }
}

struct SubscriptionPaywallContext: Identifiable {
    let requiredTier: PlanTier
    let title: String
    let message: String

    var id: String {
        "\(requiredTier.rawValue)-\(title)-\(message)"
    }
}

enum PlanFeatureAvailability {
    case available
    case unavailable
    case limited(String)

    var symbol: String {
        switch self {
        case .available:
            return "checkmark"
        case .unavailable:
            return "minus"
        case .limited:
            return "exclamationmark"
        }
    }

    var label: String {
        switch self {
        case .available:
            return "Available"
        case .unavailable:
            return "Unavailable"
        case .limited(let detail):
            return detail
        }
    }

    var color: Color {
        switch self {
        case .available:
            return .green
        case .unavailable:
            return .secondary
        case .limited:
            return .orange
        }
    }
}

struct PlanFeatureRow: Identifiable {
    let title: String
    let freeAvailability: PlanFeatureAvailability
    let plusAvailability: PlanFeatureAvailability
    let proAvailability: PlanFeatureAvailability

    var id: String { title }

    func availability(for tier: PlanTier) -> PlanFeatureAvailability {
        switch tier {
        case .free:
            return freeAvailability
        case .plus:
            return plusAvailability
        case .pro:
            return proAvailability
        }
    }
}

enum PlanFeatureSection: String, CaseIterable, Identifiable {
    case core
    case ai
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .core:
            return "Core Features"
        case .ai:
            return "AI Features"
        case .advanced:
            return "Advanced Features"
        }
    }
}

@MainActor
struct PlansComparisonView: View {
    @ObservedObject var featureGate: FeatureGate
    @ObservedObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var authViewModel: AuthViewModel
    var emphasizedTier: PlanTier? = nil
    var billingCycleSelection: Binding<PlanBillingCycle>? = nil
    @State private var billingCycle: PlanBillingCycle = .yearly
    @State private var expandedSections: Set<PlanFeatureSection> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Picker("Billing", selection: selectedBillingCycle) {
                    ForEach(PlanBillingCycle.allCases) { cycle in
                        Text(cycle.title).tag(cycle)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            HStack(alignment: .top, spacing: 14) {
                ForEach([PlanTier.free, .plus, .pro]) { tier in
                    PlanCardView(
                        tier: tier,
                        billingCycle: selectedBillingCycle.wrappedValue,
                        keyFeatures: keyFeatures(for: tier),
                        currentTier: featureGate.tier,
                        currentProductID: subscriptionStore.currentProductID,
                        product: product(for: tier),
                        isPurchasing: activePurchaseMatches(tier: tier),
                        isRestoring: subscriptionStore.isRestoring,
                        isLoadingProducts: subscriptionStore.isLoadingProducts,
                        productLoadErrorMessage: subscriptionStore.productLoadErrorMessage,
                        emphasizedTier: emphasizedTier,
                        onSelectPlan: { product in
                            Task {
                                guard await handlePurchaseIntent() else { return }
                                await subscriptionStore.purchase(product)
                            }
                        }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(PlanFeatureSection.allCases) { section in
                    comparisonSection(section)
                }
            }
        }
        .task(id: authViewModel.currentUser?.uid) {
            await subscriptionStore.ensureProductsLoaded()
            await authViewModel.preparePurchaseReadiness()
        }
        .sheet(isPresented: purchaseLoginPromptBinding) {
            PurchaseAuthenticationSheet()
                .environmentObject(authViewModel)
                .environmentObject(LocalizationManager.shared)
        }
    }

    private func handlePurchaseIntent() async -> Bool {
        guard authViewModel.isAuthenticated else {
            await MainActor.run {
                authViewModel.isPurchaseLoginPromptPresented = true
            }
            return false
        }
        return authViewModel.canStartPurchase
    }

    private var purchaseLoginPromptBinding: Binding<Bool> {
        Binding(
            get: { authViewModel.isPurchaseLoginPromptPresented },
            set: { isPresented in
                if !isPresented {
                    authViewModel.dismissPurchaseLoginPrompt()
                }
            }
        )
    }

    private func product(for tier: PlanTier) -> Product? {
        guard let productID = productID(for: tier) else {
            return nil
        }
        return subscriptionStore.product(for: productID)
    }

    private func productID(for tier: PlanTier) -> String? {
        switch (tier, selectedBillingCycle.wrappedValue) {
        case (.free, _):
            return nil
        case (.plus, .monthly):
            return "pomodoro.plus.monthly"
        case (.plus, .yearly):
            return "pomodoro.plus.yearly"
        case (.pro, .monthly):
            return "pomodoro.pro.monthly"
        case (.pro, .yearly):
            return "pomodoro.pro.yearly"
        }
    }

    private func activePurchaseMatches(tier: PlanTier) -> Bool {
        guard let productID = productID(for: tier) else { return false }
        return subscriptionStore.activePurchaseProductID == productID
    }

    private func keyFeatures(for tier: PlanTier) -> [String] {
        switch tier {
        case .free:
            return [
                "Core Pomodoro Timer",
                "Basic Tasks",
                "Calendar Read Access",
                "Reminders Sync"
            ]
        case .plus:
            return [
                "Everything in Free",
                "AI task drafting",
                "AI summaries",
                "Extended task tools"
            ]
        case .pro:
            return [
                "Everything in Plus",
                "Advanced AI models",
                "Advanced analytics",
                "Auto fullscreen Flow Mode"
            ]
        }
    }

    private func rows(for section: PlanFeatureSection) -> [PlanFeatureRow] {
        switch section {
        case .core:
            return [
                PlanFeatureRow(title: "Pomodoro timer", freeAvailability: .available, plusAvailability: .available, proAvailability: .available),
                PlanFeatureRow(title: "Tasks", freeAvailability: .available, plusAvailability: .available, proAvailability: .available),
                PlanFeatureRow(title: "Calendar read", freeAvailability: .available, plusAvailability: .available, proAvailability: .available),
                PlanFeatureRow(title: "Reminders", freeAvailability: .available, plusAvailability: .available, proAvailability: .available)
            ]
        case .ai:
            return [
                PlanFeatureRow(title: "AI task drafting", freeAvailability: .unavailable, plusAvailability: .available, proAvailability: .available),
                PlanFeatureRow(title: "AI summaries", freeAvailability: .unavailable, plusAvailability: .available, proAvailability: .available),
                PlanFeatureRow(title: "AI scheduling suggestions", freeAvailability: .unavailable, plusAvailability: .unavailable, proAvailability: .available)
            ]
        case .advanced:
            return [
                PlanFeatureRow(title: "Flow mode customization", freeAvailability: .available, plusAvailability: .available, proAvailability: .available),
                PlanFeatureRow(title: "Advanced analytics", freeAvailability: .unavailable, plusAvailability: .unavailable, proAvailability: .available),
                PlanFeatureRow(title: "Auto fullscreen Flow Mode", freeAvailability: .unavailable, plusAvailability: .unavailable, proAvailability: .available),
                PlanFeatureRow(title: "Markdown tasks & subtasks", freeAvailability: .unavailable, plusAvailability: .available, proAvailability: .available),
                PlanFeatureRow(title: "Advanced AI models", freeAvailability: .unavailable, plusAvailability: .limited("DeepSeek"), proAvailability: .available),
                PlanFeatureRow(title: "Eisenhower Matrix", freeAvailability: .unavailable, plusAvailability: .unavailable, proAvailability: .available)
            ]
        }
    }

    @ViewBuilder
    private func comparisonSection(_ section: PlanFeatureSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                } else {
                    expandedSections.insert(section)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expandedSections.contains(section) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedSections.contains(section) {
                VStack(alignment: .leading, spacing: 8) {
                    comparisonHeaderRow

                    ForEach(rows(for: section)) { row in
                        HStack(alignment: .center, spacing: 12) {
                            Text(row.title)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            comparisonCell(row.availability(for: .free))
                            comparisonCell(row.availability(for: .plus))
                            comparisonCell(row.availability(for: .pro))
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var comparisonHeaderRow: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(maxWidth: .infinity)
            Text("Free")
                .frame(width: 72)
            Text("Plus")
                .frame(width: 72)
            Text("Pro")
                .frame(width: 72)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func comparisonCell(_ availability: PlanFeatureAvailability) -> some View {
        VStack(spacing: 2) {
            Image(systemName: availability.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(availability.color)
            if case .limited(let detail) = availability {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 72)
    }

    private var selectedBillingCycle: Binding<PlanBillingCycle> {
        billingCycleSelection ?? $billingCycle
    }
}

struct PlanCardView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let tier: PlanTier
    let billingCycle: PlanBillingCycle
    let keyFeatures: [String]
    let currentTier: FeatureGate.Tier
    let currentProductID: String?
    let product: Product?
    let isPurchasing: Bool
    let isRestoring: Bool
    let isLoadingProducts: Bool
    let productLoadErrorMessage: String?
    let emphasizedTier: PlanTier?
    let onSelectPlan: (Product) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            VStack(alignment: .leading, spacing: 10) {
                ForEach(keyFeatures, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                            .frame(width: 12, alignment: .center)

                        Text(feature)
                            .font(.subheadline)
                    }
                }
            }

            if shouldCallOutUnlock {
                Label("Unlocks this feature", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            ctaSection
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(currentCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(currentBorderColor, lineWidth: isHighlighted ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.title)
                    .font(.title3.weight(.semibold))

                Spacer()

                if showBestValueBadge {
                    Text("Best Value")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            Text(priceText)
                .font(.headline)
                .foregroundStyle(isCycleHighlighted ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private var ctaSection: some View {
        if tier == .free {
            Button(isCurrentFreePlan ? "Current Plan" : "Free") { }
                .buttonStyle(.bordered)
                .disabled(true)
        } else if let product {
            Button {
                onSelectPlan(product)
            } label: {
                if isPurchasing || isPurchaseBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(buttonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isDisabled)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                } label: {
                    if isPurchaseBusy || isLoadingProducts {
                        ProgressView()
                            .controlSize(.small)
                    } else if productLoadErrorMessage != nil {
                        Text("Price unavailable")
                    } else {
                        Text(!authViewModel.isAuthenticated ? "Sign in to continue" : "Loading…")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(true)

                if let productLoadErrorMessage, !productLoadErrorMessage.isEmpty {
                    Text(productLoadErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var priceText: String {
        if let product {
            return product.displayPrice
        }
        switch tier {
        case .free:
            return "Included"
        case .plus, .pro:
            if productLoadErrorMessage != nil {
                return "Price unavailable"
            }
            return "Loading…"
        }
    }

    private var isCurrentFreePlan: Bool {
        let resolvedTier = PlanTier.from(featureTier: currentTier)
        return resolvedTier == .free && !hasStoreKitPaidPlan
    }

    private var isCurrentPaidPlan: Bool {
        let resolvedTier = PlanTier.from(featureTier: currentTier)
        if resolvedTier == tier, resolvedTier != .free {
            return true
        }
        guard let product else { return false }
        return currentProductID == product.id
    }

    private var hasStoreKitPaidPlan: Bool {
        currentProductID != nil
    }

    private var isHighlighted: Bool {
        if emphasizedTier == tier {
            return true
        }
        switch tier {
        case .free:
            return isCurrentFreePlan
        case .plus, .pro:
            return isCurrentPaidPlan
        }
    }

    private var isDisabled: Bool {
        if !authViewModel.isAuthenticated {
            return isRestoring || isPurchasing || isCurrentPaidPlan || currentTier == .developer
        }
        return isRestoring || isPurchasing || isCurrentPaidPlan || currentTier == .developer || !authViewModel.canStartPurchase
    }

    private var buttonTitle: String {
        if isCurrentPaidPlan {
            return "Current Plan"
        }
        if !authViewModel.isAuthenticated {
            return "Sign in to continue"
        }
        if isPurchaseBusy {
            return "Loading…"
        }
        switch tier {
        case .free:
            return "Free"
        case .plus, .pro:
            return "Upgrade"
        }
    }

    private var isPurchaseBusy: Bool {
        authViewModel.isLoading || authViewModel.isPreparingPurchase
    }

    private var showBestValueBadge: Bool {
        billingCycle == .yearly && tier == .pro
    }

    private var shouldCallOutUnlock: Bool {
        emphasizedTier == tier && PlanTier.from(featureTier: currentTier) != tier
    }

    private var isCycleHighlighted: Bool {
        billingCycle == .yearly && tier == .pro
    }

    private var currentCardBackground: some ShapeStyle {
        if isHighlighted {
            return AnyShapeStyle(Color.accentColor.opacity(0.10))
        }
        return AnyShapeStyle(Color.primary.opacity(0.04))
    }

    private var currentBorderColor: Color {
        isHighlighted ? .accentColor.opacity(0.7) : Color.primary.opacity(0.08)
    }
}

@MainActor
struct SubscriptionUpgradeSheetView: View {
    let context: SubscriptionPaywallContext
    @ObservedObject var featureGate: FeatureGate
    @ObservedObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var billingCycle: PlanBillingCycle = .yearly

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(context.title)
                    .font(.title3.weight(.semibold))

                Text(context.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PlansComparisonView(
                    featureGate: featureGate,
                    subscriptionStore: subscriptionStore,
                    emphasizedTier: context.requiredTier,
                    billingCycleSelection: $billingCycle
                )

                if let errorMessage = subscriptionStore.errorMessage,
                   !errorMessage.isEmpty {
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

                HStack {
                    Button(localizationManager.text("common.cancel")) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(primaryPurchaseButtonTitle) {
                        Task {
                            guard let product = selectedUpgradeProduct else { return }
                            guard await handlePurchaseIntent() else { return }
                            await subscriptionStore.purchase(product)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPurchaseButtonDisabled)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 860, idealWidth: 920, minHeight: 640, idealHeight: 720)
        .task(id: authViewModel.currentUser?.uid) {
            await authViewModel.preparePurchaseReadiness()
        }
        .sheet(isPresented: purchaseLoginPromptBinding) {
            PurchaseAuthenticationSheet()
                .environmentObject(authViewModel)
                .environmentObject(localizationManager)
        }
    }

    private var selectedUpgradeProduct: Product? {
        let productID: String?
        switch (context.requiredTier, billingCycle) {
        case (.free, _):
            productID = nil
        case (.plus, .monthly):
            productID = "pomodoro.plus.monthly"
        case (.plus, .yearly):
            productID = "pomodoro.plus.yearly"
        case (.pro, .monthly):
            productID = "pomodoro.pro.monthly"
        case (.pro, .yearly):
            productID = "pomodoro.pro.yearly"
        }

        guard let productID else { return nil }
        return subscriptionStore.product(for: productID)
    }

    private var isUpgradingCurrentPlan: Bool {
        if PlanTier.from(featureTier: featureGate.tier) == context.requiredTier,
           context.requiredTier != .free {
            return true
        }
        guard let selectedUpgradeProduct else { return false }
        return subscriptionStore.currentProductID == selectedUpgradeProduct.id
    }

    private var isPurchaseButtonDisabled: Bool {
        guard !isUpgradingCurrentPlan, selectedUpgradeProduct != nil else { return true }
        if !authViewModel.isAuthenticated {
            return false
        }
        return !authViewModel.canStartPurchase
    }

    private var primaryPurchaseButtonTitle: String {
        if !authViewModel.isAuthenticated {
            return "Sign in to continue"
        }
        if authViewModel.isLoading || authViewModel.isPreparingPurchase {
            return "Loading…"
        }
        return localizationManager.text("tasks.ai_assistant.upgrade")
    }

    private func handlePurchaseIntent() async -> Bool {
        guard authViewModel.isAuthenticated else {
            await MainActor.run {
                authViewModel.isPurchaseLoginPromptPresented = true
            }
            return false
        }
        return authViewModel.canStartPurchase
    }

    private var purchaseLoginPromptBinding: Binding<Bool> {
        Binding(
            get: { authViewModel.isPurchaseLoginPromptPresented },
            set: { isPresented in
                if !isPresented {
                    authViewModel.dismissPurchaseLoginPrompt()
                }
            }
        )
    }
}

struct PurchaseAuthenticationSheet: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Sign in to continue")
                .font(.title3.weight(.semibold))

            Text("Please sign in before purchasing so your subscription can be validated and synced.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LoginView()

            HStack {
                Spacer()

                Button(localizationManager.text("common.close")) {
                    authViewModel.dismissPurchaseLoginPrompt()
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
        .onChange(of: authViewModel.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            authViewModel.dismissPurchaseLoginPrompt()
            dismiss()
        }
    }
}

#Preview {
    MainActor.assumeIsolated {
        SettingsPermissionsView(permissionsManager: .shared)
            .frame(width: 600, height: 400)
            .environmentObject(AuthViewModel.shared)
    }
}

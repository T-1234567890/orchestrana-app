import Foundation
import Combine
import FirebaseAuth
import FirebaseFunctions

/// Entitlement-aware feature gating for cloud-powered capabilities.
final class FeatureGate: ObservableObject {
    private struct CachedEntitlement: Codable {
        let uid: String
        let tier: Tier
        let subscriptionEndAt: Date?
        let analyticsLevel: AnalyticsLevel
        let aiLevel: AILevel
        let features: [String: Bool]

        init(
            uid: String,
            tier: Tier,
            subscriptionEndAt: Date?,
            analyticsLevel: AnalyticsLevel,
            aiLevel: AILevel,
            features: [String: Bool]
        ) {
            self.uid = uid
            self.tier = tier
            self.subscriptionEndAt = subscriptionEndAt
            self.analyticsLevel = analyticsLevel
            self.aiLevel = aiLevel
            self.features = features
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uid = try container.decode(String.self, forKey: .uid)
            tier = try container.decode(Tier.self, forKey: .tier)
            subscriptionEndAt = try container.decodeIfPresent(Date.self, forKey: .subscriptionEndAt)
            analyticsLevel = try container.decodeIfPresent(AnalyticsLevel.self, forKey: .analyticsLevel)
                ?? FeatureGate.defaultAnalyticsLevel(for: tier)
            aiLevel = try container.decodeIfPresent(AILevel.self, forKey: .aiLevel)
                ?? FeatureGate.defaultAILevel(for: tier)
            features = try container.decodeIfPresent([String: Bool].self, forKey: .features)
                ?? Dictionary(uniqueKeysWithValues: FeatureGate.defaultFeatures(for: tier).map { ($0.key.rawValue, $0.value) })
        }

        enum CodingKeys: String, CodingKey {
            case uid
            case tier
            case subscriptionEndAt
            case analyticsLevel
            case aiLevel
            case features
        }
    }

    struct AIUsageProgress {
        let title: String
        let usedRatio: Double

        var usedPercentage: Int {
            Int((usedRatio * 100).rounded())
        }
    }

    struct DailyAIUsageWindow {
        let used: Int?
        let limit: Int?
        let remaining: Int?
        let resetAt: Date?
    }

    enum Feature: String, Codable, CaseIterable {
        case aiEnabled = "AI_ENABLED"
        case advancedCharts = "ADVANCED_CHARTS"
        case proLayout = "PRO_LAYOUT"
        case fullscreenMode = "FULLSCREEN_MODE"
    }

    enum AnalyticsLevel: String, Codable {
        case basic
        case plus
        case pro
    }

    enum AILevel: String, Codable {
        case none
        case weekly
        case deep
    }

    enum Tier: String, Codable {
        case free
        case beta
        case plus
        case pro
        case expired
        case developer
    }

    @Published private(set) var tier: Tier = .free
    @Published private(set) var deepSeekRemainingTokens: Int?
    @Published private(set) var deepSeekMonthlyLimit: Int?
    @Published private(set) var geminiFlash3RemainingTokens: Int?
    @Published private(set) var geminiFlash3MonthlyLimit: Int?
    @Published private(set) var allowanceResetAt: Date?
    @Published private(set) var dailyAllowanceResetAt: Date?
    @Published private(set) var subscriptionEndAt: Date?
    @Published private(set) var isRefreshingAllowance = false
    @Published private(set) var allowanceErrorMessage: String?
    @Published private(set) var analyticsLevel: AnalyticsLevel = .basic
    @Published private(set) var aiLevel: AILevel = .none
    @Published private(set) var dailyAIUsage = DailyAIUsageWindow(used: nil, limit: nil, remaining: nil, resetAt: nil)
    @Published private(set) var featureFlags: [Feature: Bool] = [:]

    static let shared = FeatureGate()

    private var authListener: AuthStateDidChangeListenerHandle?
    private let functions: Functions
    private let defaults: UserDefaults
    private static let cachedEntitlementKey = "feature_gate.cached_entitlement"

    private init(functions: Functions? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let functions {
            self.functions = functions
        } else {
            self.functions = Functions.functions(region: "us-central1")
        }
        restoreCachedEntitlementIfAvailable()
        listenForAuthChanges()
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    // MARK: - Permissions

    func canAccess(_ feature: Feature) -> Bool {
        if let value = featureFlags[feature] {
            return value
        }
        return Self.defaultFeatures(for: tier)[feature] ?? false
    }

    var canUseCloudProxyAI: Bool {
        canAccess(.aiEnabled)
    }

    var canUseNotesProFeatures: Bool {
        switch tier {
        case .pro, .developer:
            return true
        default:
            return false
        }
    }

    var canUseSharePrivateSocial: Bool {
        switch tier {
        case .plus, .pro, .beta, .developer:
            return true
        default:
            return false
        }
    }

    var isExpired: Bool {
        tier == .expired
    }

    var hasAnyQuotaData: Bool {
        deepSeekRemainingTokens != nil || geminiFlash3RemainingTokens != nil
    }

    var isAIQuotaExhausted: Bool {
        if tier == .developer {
            return false
        }
        let trackedValues = [deepSeekRemainingTokens, geminiFlash3RemainingTokens].compactMap { $0 }
        guard !trackedValues.isEmpty else { return false }
        return trackedValues.allSatisfy { $0 <= 0 }
    }

    var isAIDailyQuotaExhausted: Bool {
        if tier == .developer {
            return false
        }
        guard let remaining = dailyAIUsage.remaining else { return false }
        return remaining <= 0
    }

    var canTriggerAIAction: Bool {
        canUseCloudProxyAI && !isAIQuotaExhausted && !isAIDailyQuotaExhausted
    }

    var canUseAIPlanning: Bool {
        canUseCloudProxyAI
    }

    func canUseAIScheduling() -> Bool {
        analyticsLevel == .pro || tier == .pro || tier == .developer
    }

    var canUseFullscreenFlow: Bool {
        canAccess(.fullscreenMode)
    }

    var canUseCustomFlowBackgrounds: Bool {
        canUseFullscreenFlow
    }

    var canUseCustomFlowLayout: Bool {
        canAccess(.proLayout)
    }

    var canUseAdvancedCharts: Bool {
        canAccess(.advancedCharts)
    }

    var canUseAIWeeklyOverview: Bool {
        aiLevel == .weekly || aiLevel == .deep
    }

    var canUseAIDeepAnalysis: Bool {
        aiLevel == .deep
    }

    var canUseAIAssistantBreakdown: Bool {
        canUseCloudProxyAI
    }

    var canUseAdvancedTasks: Bool {
        canUseCloudProxyAI
    }

    var canUseTaskMarkdown: Bool {
        canUseAdvancedTasks
    }

    var canUseSubtasks: Bool {
        canUseAdvancedTasks
    }

    var canUseTaskKeyboardShortcuts: Bool {
        canUseAdvancedTasks
    }

    var canUseEisenhowerMatrix: Bool {
        switch tier {
        case .pro, .developer:
            return true
        default:
            return false
        }
    }

    var aiAssistantUpgradeTitle: String {
        LocalizationManager.shared.text("tasks.ai_assistant.plus_feature_title")
    }

    func canUseAIAssistantAction(_ action: AIAssistantAction) -> Bool {
        switch action {
        case .breakdown:
            return canUseAIAssistantBreakdown
        case .planning:
            return canUseAIPlanning
        case .reschedule:
            return canUseAIScheduling()
        }
    }

    func shouldShowUpgradeModal(for action: AIAssistantAction) -> Bool {
        !canUseAIAssistantAction(action)
    }

    func aiAssistantDisabledReason(for action: AIAssistantAction) -> String? {
        if !canUseAIAssistantAction(action) {
            switch action {
            case .breakdown:
                return LocalizationManager.shared.text("tasks.ai_assistant.breakdown_requires_plus")
            case .planning:
                return LocalizationManager.shared.text("tasks.ai_assistant.planning_requires_plus")
            case .reschedule:
                return LocalizationManager.shared.text("calendar.ai_auto_schedule.requires_pro_title")
            }
        }
        if isAIQuotaExhausted {
            return aiActionDisabledReason
        }
        return nil
    }

    var aiPlanningDisabledReason: String? {
        if !canUseAIPlanning {
            return LocalizationManager.shared.text("tasks.ai_assistant.planning_requires_plus")
        }
        if isAIQuotaExhausted {
            return aiActionDisabledReason
        }
        return nil
    }

    var shouldShowAIPlanningUpgradeModal: Bool {
        !canUseAIPlanning
    }

    var aiPlanningQuotaMessage: String? {
        guard (canUseAIPlanning || canUseAIAssistantBreakdown), isAIQuotaExhausted || isAIDailyQuotaExhausted else { return nil }
        return aiActionDisabledReason
    }

    var canRunAIPlanningRequest: Bool {
        (canUseAIPlanning || canUseAIAssistantBreakdown) && !isAIQuotaExhausted && !isAIDailyQuotaExhausted
    }

    var aiUsageProgressItems: [AIUsageProgress] {
        [
            usageProgress(
                title: "DeepSeek",
                remaining: deepSeekRemainingTokens,
                limit: deepSeekMonthlyLimit
            ),
            usageProgress(
                title: "Gemini Flash",
                remaining: geminiFlash3RemainingTokens,
                limit: geminiFlash3MonthlyLimit
            )
        ]
        .compactMap { $0 }
    }

    var aiActionDisabledReason: String? {
        let l10n = LocalizationManager.shared
        if !canUseCloudProxyAI {
            return l10n.text("feature_gate.ai_access_unavailable")
        }
        if isAIQuotaExhausted || isAIDailyQuotaExhausted {
            Self.resetFormatter.locale = l10n.effectiveLocale
            let resetDate = dailyAIUsage.resetAt ?? dailyAllowanceResetAt ?? allowanceResetAt
            if let resetText = resetDate.map(Self.resetFormatter.string(from:)) {
                return l10n.format("feature_gate.ai_quota_exhausted_refresh_on", resetText)
            }
            return l10n.text("feature_gate.ai_quota_exhausted")
        }
        return nil
    }

    private func usageProgress(title: String, remaining: Int?, limit: Int?) -> AIUsageProgress? {
        guard let remaining, let limit, limit > 0 else {
            return nil
        }

        let used = max(0, min(limit, limit - remaining))
        let ratio = min(1, max(0, Double(used) / Double(limit)))
        return AIUsageProgress(title: title, usedRatio: ratio)
    }

    // MARK: - Networking

    @MainActor
    func refreshTier() async {
        await refreshAllowance()
    }

    @MainActor
    func refreshSubscriptionStatusIfNeeded() async {
        guard AuthViewModel.shared.isAuthenticated else {
            resetToSignedOutState()
            return
        }
        guard !isRefreshingAllowance else { return }
        await refreshAllowance()
    }

    func refreshAllowanceInBackground() {
        guard AuthViewModel.shared.isAuthenticated else { return }
        guard !isRefreshingAllowance else { return }
        Task { @MainActor in
            await refreshAllowance()
        }
    }

    @MainActor
    func refreshAllowance() async {
        guard AuthViewModel.shared.isAuthenticated else {
            resetToSignedOutState()
            return
        }

        isRefreshingAllowance = true
        allowanceErrorMessage = nil
        defer { isRefreshingAllowance = false }

        do {
            let result = try await functions
                .httpsCallable("getAllowance")
                .call()
            let payload = try decodeAllowancePayload(from: result.data)
            apply(payload: payload)
        } catch {
            allowanceErrorMessage = error.localizedDescription
        }
    }

    private func listenForAuthChanges() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                if user == nil {
                    self.resetToSignedOutState()
                } else {
                    self.restoreCachedEntitlementIfAvailable()
                    await self.refreshAllowance()
                }
            }
        }
    }

    @MainActor
    private func resetToSignedOutState() {
        tier = .free
        deepSeekRemainingTokens = nil
        deepSeekMonthlyLimit = nil
        geminiFlash3RemainingTokens = nil
        geminiFlash3MonthlyLimit = nil
        allowanceResetAt = nil
        dailyAllowanceResetAt = nil
        subscriptionEndAt = nil
        analyticsLevel = .basic
        aiLevel = .none
        dailyAIUsage = DailyAIUsageWindow(used: nil, limit: nil, remaining: nil, resetAt: nil)
        featureFlags = Self.defaultFeatures(for: .free)
    }

    @MainActor
    private func restoreCachedEntitlementIfAvailable() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let data = defaults.data(forKey: Self.cachedEntitlementKey) else { return }
        guard let cached = try? JSONDecoder().decode(CachedEntitlement.self, from: data) else { return }
        guard cached.uid == uid else { return }

        tier = cached.tier
        subscriptionEndAt = cached.subscriptionEndAt
        analyticsLevel = cached.analyticsLevel
        aiLevel = cached.aiLevel
        featureFlags = Self.decodeFeatureFlags(from: cached.features)
    }

    @MainActor
    private func apply(payload: AllowancePayload) {
        tier = payload.tier ?? .free
        deepSeekRemainingTokens = payload.deepSeekRemainingTokens
        deepSeekMonthlyLimit = payload.deepSeekMonthlyLimit
        geminiFlash3RemainingTokens = payload.geminiFlash3RemainingTokens
        geminiFlash3MonthlyLimit = payload.geminiFlash3MonthlyLimit
        allowanceResetAt = payload.resetAt
        dailyAllowanceResetAt = payload.dailyResetAt ?? payload.dailyAIUsage?.resetAt
        subscriptionEndAt = payload.subscriptionEndAt
        analyticsLevel = payload.analyticsLevel ?? Self.defaultAnalyticsLevel(for: tier)
        aiLevel = payload.aiLevel ?? Self.defaultAILevel(for: tier)
        featureFlags = payload.featureFlags ?? Self.defaultFeatures(for: tier)
        dailyAIUsage = payload.dailyAIUsage ?? DailyAIUsageWindow(
            used: nil,
            limit: nil,
            remaining: nil,
            resetAt: dailyAllowanceResetAt
        )
        if let uid = Auth.auth().currentUser?.uid {
            persistCachedEntitlement(uid: uid, tier: tier, subscriptionEndAt: payload.subscriptionEndAt)
        }
    }

    private func persistCachedEntitlement(uid: String, tier: Tier, subscriptionEndAt: Date?) {
        let cached = CachedEntitlement(
            uid: uid,
            tier: tier,
            subscriptionEndAt: subscriptionEndAt,
            analyticsLevel: analyticsLevel,
            aiLevel: aiLevel,
            features: Dictionary(uniqueKeysWithValues: featureFlags.map { ($0.key.rawValue, $0.value) })
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: Self.cachedEntitlementKey)
    }

    private func decodeAllowancePayload(from data: Any) throws -> AllowancePayload {
        let rootObject: Any
        if let dictionary = data as? [String: Any],
           let nested = dictionary["data"] {
            rootObject = nested
        } else if let dictionary = data as? [String: Any],
                  let nested = dictionary["payload"] {
            rootObject = nested
        } else {
            rootObject = data
        }

        guard JSONSerialization.isValidJSONObject(rootObject) else {
            throw GateError.invalidResponse
        }

        let responseData = try JSONSerialization.data(withJSONObject: rootObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AllowanceResponse.self, from: responseData) {
            return decoded.payload
        }

        let object = try JSONSerialization.jsonObject(with: responseData)
        guard let json = object as? [String: Any] else {
            throw GateError.decodingFailed
        }
        return AllowancePayload(json: json)
    }

    private enum GateError: LocalizedError {
        case invalidResponse
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return LocalizationManager.shared.text("feature_gate.error.invalid_allowance_response")
            case .decodingFailed:
                return LocalizationManager.shared.text("feature_gate.error.decoding_failed")
            }
        }
    }

    private struct AllowanceResponse: Decodable {
        let tier: Tier?
        let entitlements: EntitlementsPayload?
        let deepseek: ProviderQuota?
        let deepSeek: ProviderQuota?
        let geminiFlash3: ProviderQuota?
        let gemini_flash_3: ProviderQuota?
        let allowances: [String: ProviderQuota]?
        let quotas: [String: ProviderQuota]?
        let deepseekRemaining: Int?
        let deepseekLimit: Int?
        let geminiFlash3Remaining: Int?
        let geminiFlash3Limit: Int?
        let resetAt: Date?
        let reset_at: Date?
        let dailyResetAt: Date?
        let daily_reset_at: Date?
        let aiUsage: AIUsagePayload?
        let ai_usage: AIUsagePayload?
        let subscriptionEndAt: Date?
        let subscription_end_at: Date?

        var payload: AllowancePayload {
            let deepSeekQuota = deepseek ?? deepSeek ?? allowances?["deepseek"] ?? quotas?["deepseek"]
            let geminiQuota = geminiFlash3
                ?? gemini_flash_3
                ?? allowances?["geminiFlash3"]
                ?? allowances?["gemini_flash_3"]
                ?? quotas?["geminiFlash3"]
                ?? quotas?["gemini_flash_3"]

            return AllowancePayload(
                tier: entitlements?.tier ?? tier,
                deepSeekRemainingTokens: deepSeekQuota?.remaining ?? deepseekRemaining,
                deepSeekMonthlyLimit: deepSeekQuota?.limit ?? deepseekLimit,
                geminiFlash3RemainingTokens: geminiQuota?.remaining ?? geminiFlash3Remaining,
                geminiFlash3MonthlyLimit: geminiQuota?.limit ?? geminiFlash3Limit,
                resetAt: resetAt ?? reset_at,
                dailyResetAt: dailyResetAt ?? daily_reset_at ?? aiUsage?.daily?.resetAt ?? ai_usage?.daily?.resetAt,
                analyticsLevel: entitlements?.analyticsLevelResolved,
                aiLevel: entitlements?.aiLevelResolved,
                featureFlags: entitlements?.features.flatMap(FeatureGate.decodeFeatureFlags(from:)),
                dailyAIUsage: aiUsage?.daily?.window ?? ai_usage?.daily?.window,
                subscriptionEndAt: subscriptionEndAt ?? subscription_end_at
            )
        }
    }

    private struct ProviderQuota: Decodable {
        let remaining: Int?
        let limit: Int?
    }

    private struct AIUsagePayload: Decodable {
        let daily: AIUsageWindowPayload?
    }

    private struct AIUsageWindowPayload: Decodable {
        let used: Int?
        let limit: Int?
        let remaining: Int?
        let resetAt: Date?
        let reset_at: Date?

        var window: DailyAIUsageWindow {
            DailyAIUsageWindow(
                used: used,
                limit: limit,
                remaining: remaining,
                resetAt: resetAt ?? reset_at
            )
        }
    }

    private struct EntitlementsPayload: Decodable {
        let tier: Tier?
        let analyticsLevel: AnalyticsLevel?
        let analytics_level: AnalyticsLevel?
        let aiLevel: AILevel?
        let ai_level: AILevel?
        let features: [String: Bool]?

        var analyticsLevelResolved: AnalyticsLevel? {
            analyticsLevel ?? analytics_level
        }

        var aiLevelResolved: AILevel? {
            aiLevel ?? ai_level
        }
    }

    private struct AllowancePayload {
        let tier: Tier?
        let deepSeekRemainingTokens: Int?
        let deepSeekMonthlyLimit: Int?
        let geminiFlash3RemainingTokens: Int?
        let geminiFlash3MonthlyLimit: Int?
        let resetAt: Date?
        let dailyResetAt: Date?
        let analyticsLevel: AnalyticsLevel?
        let aiLevel: AILevel?
        let featureFlags: [Feature: Bool]?
        let dailyAIUsage: DailyAIUsageWindow?
        let subscriptionEndAt: Date?

        init(
            tier: Tier?,
            deepSeekRemainingTokens: Int?,
            deepSeekMonthlyLimit: Int?,
            geminiFlash3RemainingTokens: Int?,
            geminiFlash3MonthlyLimit: Int?,
            resetAt: Date?,
            dailyResetAt: Date?,
            analyticsLevel: AnalyticsLevel?,
            aiLevel: AILevel?,
            featureFlags: [Feature: Bool]?,
            dailyAIUsage: DailyAIUsageWindow?,
            subscriptionEndAt: Date?
        ) {
            self.tier = tier
            self.deepSeekRemainingTokens = deepSeekRemainingTokens
            self.deepSeekMonthlyLimit = deepSeekMonthlyLimit
            self.geminiFlash3RemainingTokens = geminiFlash3RemainingTokens
            self.geminiFlash3MonthlyLimit = geminiFlash3MonthlyLimit
            self.resetAt = resetAt
            self.dailyResetAt = dailyResetAt
            self.analyticsLevel = analyticsLevel
            self.aiLevel = aiLevel
            self.featureFlags = featureFlags
            self.dailyAIUsage = dailyAIUsage
            self.subscriptionEndAt = subscriptionEndAt
        }

        init(json: [String: Any]) {
            let rawTier = (json["tier"] as? String)?.lowercased()
            self.tier = rawTier.flatMap(Tier.init(rawValue:))
            let entitlements = json["entitlements"] as? [String: Any]

            let deepseek = (json["deepseek"] as? [String: Any]) ?? (json["deepSeek"] as? [String: Any])
            let gemini = (json["geminiFlash3"] as? [String: Any]) ?? (json["gemini_flash_3"] as? [String: Any])

            self.deepSeekRemainingTokens = deepseek?["remaining"] as? Int ?? json["deepseekRemaining"] as? Int
            self.deepSeekMonthlyLimit = deepseek?["limit"] as? Int ?? json["deepseekLimit"] as? Int
            self.geminiFlash3RemainingTokens = gemini?["remaining"] as? Int ?? json["geminiFlash3Remaining"] as? Int
            self.geminiFlash3MonthlyLimit = gemini?["limit"] as? Int ?? json["geminiFlash3Limit"] as? Int

            if let reset = json["resetAt"] as? String {
                self.resetAt = Self.parseDate(reset)
            } else if let reset = json["reset_at"] as? String {
                self.resetAt = Self.parseDate(reset)
            } else {
                self.resetAt = nil
            }

            if let dailyReset = json["dailyResetAt"] as? String {
                self.dailyResetAt = Self.parseDate(dailyReset)
            } else if let dailyReset = json["daily_reset_at"] as? String {
                self.dailyResetAt = Self.parseDate(dailyReset)
            } else if let aiUsage = json["aiUsage"] as? [String: Any],
                      let daily = aiUsage["daily"] as? [String: Any],
                      let reset = daily["resetAt"] as? String {
                self.dailyResetAt = Self.parseDate(reset)
            } else {
                self.dailyResetAt = nil
            }

            let analyticsRaw = (entitlements?["analyticsLevel"] as? String)
                ?? (entitlements?["analytics_level"] as? String)
            self.analyticsLevel = analyticsRaw.flatMap(AnalyticsLevel.init(rawValue:))
            let aiRaw = (entitlements?["aiLevel"] as? String)
                ?? (entitlements?["ai_level"] as? String)
            self.aiLevel = aiRaw.flatMap(AILevel.init(rawValue:))
            self.featureFlags = (entitlements?["features"] as? [String: Bool]).flatMap(FeatureGate.decodeFeatureFlags(from:))

            if let aiUsage = json["aiUsage"] as? [String: Any],
               let daily = aiUsage["daily"] as? [String: Any] {
                self.dailyAIUsage = DailyAIUsageWindow(
                    used: daily["used"] as? Int,
                    limit: daily["limit"] as? Int,
                    remaining: daily["remaining"] as? Int,
                    resetAt: (daily["resetAt"] as? String).flatMap(Self.parseDate)
                )
            } else {
                self.dailyAIUsage = nil
            }

            if let end = json["subscriptionEndAt"] as? String {
                self.subscriptionEndAt = Self.parseDate(end)
            } else if let end = json["subscription_end_at"] as? String {
                self.subscriptionEndAt = Self.parseDate(end)
            } else {
                self.subscriptionEndAt = nil
            }
        }

        nonisolated private static func parseDate(_ value: String) -> Date? {
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            return nil
        }
    }

    nonisolated private static func defaultAnalyticsLevel(for tier: Tier) -> AnalyticsLevel {
        switch tier {
        case .pro, .developer:
            return .pro
        case .plus, .beta:
            return .plus
        case .free, .expired:
            return .basic
        }
    }

    nonisolated private static func defaultAILevel(for tier: Tier) -> AILevel {
        switch tier {
        case .pro, .developer:
            return .deep
        case .plus, .beta:
            return .weekly
        case .free, .expired:
            return .none
        }
    }

    nonisolated private static func defaultFeatures(for tier: Tier) -> [Feature: Bool] {
        switch tier {
        case .pro, .developer:
            return [
                .aiEnabled: true,
                .advancedCharts: true,
                .proLayout: true,
                .fullscreenMode: true,
            ]
        case .plus, .beta:
            return [
                .aiEnabled: true,
                .advancedCharts: true,
                .proLayout: false,
                .fullscreenMode: true,
            ]
        case .free, .expired:
            return [
                .aiEnabled: false,
                .advancedCharts: false,
                .proLayout: false,
                .fullscreenMode: false,
            ]
        }
    }

    nonisolated private static func decodeFeatureFlags(from raw: [String: Bool]) -> [Feature: Bool] {
        var decoded = [Feature: Bool]()
        for (key, value) in raw {
            guard let feature = Feature(rawValue: key) else { continue }
            decoded[feature] = value
        }
        return decoded
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    static func formatTokenCount(_ value: Int?) -> String {
        guard let value else { return "—" }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    static func tierDisplayName(_ tier: Tier) -> String {
        switch tier {
        case .free: return LocalizationManager.shared.text("feature_gate.tier.free")
        case .beta: return LocalizationManager.shared.text("feature_gate.tier.beta")
        case .plus: return LocalizationManager.shared.text("feature_gate.tier.plus")
        case .pro: return LocalizationManager.shared.text("feature_gate.tier.pro")
        case .expired: return LocalizationManager.shared.text("feature_gate.tier.expired")
        case .developer: return LocalizationManager.shared.text("feature_gate.tier.developer")
        }
    }
}

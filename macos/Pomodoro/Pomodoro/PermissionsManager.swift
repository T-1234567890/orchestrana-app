import Foundation
import AppKit
import Combine
import CoreLocation
import EventKit
import UserNotifications

final class SharedEventStore {
    static let shared = SharedEventStore()
    let eventStore = EKEventStore()

    private init() {}
}

/// Centralized permissions manager for Notifications, Calendar, and Reminders.
/// Provides authorization status checks and system settings opening.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()
    
    // System Settings URL
    private static let systemSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy"
    
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var calendarStatus: EKAuthorizationStatus = .notDetermined
    @Published var remindersStatus: EKAuthorizationStatus = .notDetermined
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    
    // Alert state for denied permissions
    @Published var showCalendarDeniedAlert = false
    @Published var showRemindersDeniedAlert = false
    @Published var showLocationDeniedAlert = false
    
    private let eventStore = SharedEventStore.shared.eventStore
    private let notificationCenter = UNUserNotificationCenter.current()
    private let locationManager = CLLocationManager()
    
    private init() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.refreshAllStatuses()
        }
    }
    
    // MARK: - Status Refresh
    
    /// Refresh all permission statuses
    func refreshAllStatuses() {
        Task {
            await refreshNotificationStatus()
            refreshCalendarStatus()
            refreshRemindersStatus()
            refreshLocationStatus()
        }
    }
    
    func refreshNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        updateNotificationStatus(settings.authorizationStatus)
    }
    
    func refreshCalendarStatus() {
        updateCalendarStatus(EKEventStore.authorizationStatus(for: .event))
    }
    
    func refreshRemindersStatus() {
        updateRemindersStatus(EKEventStore.authorizationStatus(for: .reminder))
    }

    func refreshLocationStatus() {
        updateLocationStatus(locationManager.authorizationStatus)
    }
    
    // MARK: - Permission Requests
    
    /// Request notification permission - shows system dialog if notDetermined, alert if denied/restricted
    func requestNotificationPermission() async {
        // Check current status
        let status = await notificationCenter.notificationSettings().authorizationStatus
        updateNotificationStatus(status)
        
        switch status {
        case .notDetermined:
            // Request permission - this will show the system dialog
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
                let updatedStatus = await notificationCenter.notificationSettings().authorizationStatus
                updateNotificationStatus(updatedStatus)
                
                if !granted {
                    // User denied in the dialog - no additional action needed
                    ClientLog.debug("[PermissionsManager] Notification permission denied by user")
                }
            } catch {
                ClientLog.debugError("[PermissionsManager] Notification request failed", error)
            }
            
        case .denied:
            // Already denied - inform user via alert (handled in UI)
            ClientLog.debug("[PermissionsManager] Notification permission already denied")
            // Note: Notifications don't have a dedicated alert flag since they're handled differently in the UI
            // but the pattern is consistent with Calendar/Reminders
            
        case .authorized, .provisional, .ephemeral:
            // Already authorized
            ClientLog.debug("[PermissionsManager] Notification permission already authorized")
            
        @unknown default:
            ClientLog.debug("[PermissionsManager] Unknown notification status")
        }
    }
    
    /// Request calendar permission - shows system dialog if notDetermined, sets alert flag if denied/restricted
    func requestCalendarPermission() async {
        // Check current status
        let status = EKEventStore.authorizationStatus(for: .event)
        updateCalendarStatus(status)

        if #available(macOS 14.0, *) {
            switch status {
            case .notDetermined:
                let granted = await requestCalendarAccess()
                updateCalendarStatus(EKEventStore.authorizationStatus(for: .event))
                if !granted { showCalendarDeniedAlert = true }
            case .denied, .restricted:
                showCalendarDeniedAlert = true
            case .fullAccess, .writeOnly:
                break
            default:
                break
            }
        } else {
            switch status {
            case .notDetermined:
                let granted = await requestCalendarAccess()
                updateCalendarStatus(EKEventStore.authorizationStatus(for: .event))
                if !granted { showCalendarDeniedAlert = true }
            case .denied, .restricted:
                showCalendarDeniedAlert = true
            case .authorized:
                break
            default:
                break
            }
        }
    }
    
    /// Request reminders permission - shows system dialog if notDetermined, sets alert flag if denied/restricted
    func requestRemindersPermission() async {
        // Check current status
        let status = EKEventStore.authorizationStatus(for: .reminder)
        updateRemindersStatus(status)

        if #available(macOS 14.0, *) {
            switch status {
            case .notDetermined:
                let granted = await requestRemindersAccess()
                updateRemindersStatus(EKEventStore.authorizationStatus(for: .reminder))
                if !granted { showRemindersDeniedAlert = true }
            case .denied, .restricted:
                showRemindersDeniedAlert = true
            case .fullAccess, .writeOnly:
                break
            default:
                break
            }
        } else {
            switch status {
            case .notDetermined:
                let granted = await requestRemindersAccess()
                updateRemindersStatus(EKEventStore.authorizationStatus(for: .reminder))
                if !granted { showRemindersDeniedAlert = true }
            case .denied, .restricted:
                showRemindersDeniedAlert = true
            case .authorized:
                break
            default:
                break
            }
        }
    }

    /// Request Always location permission for Map location reminders and nearby-work context.
    func requestLocationPermission() async {
        refreshLocationStatus()

        switch locationStatus {
        case .notDetermined:
            do {
                try await LocationAuthorizationRequester.shared.requestWhenInUse()
                refreshLocationStatus()
            } catch {
                refreshLocationStatus()
                showLocationDeniedAlert = true
                ClientLog.debugError("[PermissionsManager] Location request failed", error)
            }
        case .denied, .restricted:
            showLocationDeniedAlert = true
        case .authorizedAlways:
            break
        @unknown default:
            break
        }
    }
    
    // MARK: - Legacy Methods (Deprecated)
    
    /// Register notification intent when status is notDetermined
    /// This may show the system prompt once
    @available(*, deprecated, message: "Use requestNotificationPermission() instead")
    func registerNotificationIntent() async {
        await requestNotificationPermission()
    }
    
    /// Register calendar intent when status is notDetermined
    /// This may show the system prompt once
    @available(*, deprecated, message: "Use requestCalendarPermission() instead")
    func registerCalendarIntent() async {
        await requestCalendarPermission()
    }
    
    /// Register reminders intent when status is notDetermined
    /// This may show the system prompt once
    @available(*, deprecated, message: "Use requestRemindersPermission() instead")
    func registerRemindersIntent() async {
        await requestRemindersPermission()
    }
    
    // MARK: - System Settings
    
    /// Opens macOS System Settings app
    /// This is the primary UX for permission management
    func openSystemSettings() {
        if let url = URL(string: Self.systemSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private helpers

    private func requestCalendarAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestRemindersAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func updateNotificationStatus(_ status: UNAuthorizationStatus) {
        guard notificationStatus != status else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.notificationStatus != status else { return }
            self.notificationStatus = status
        }
    }

    private func updateCalendarStatus(_ status: EKAuthorizationStatus) {
        guard calendarStatus != status else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.calendarStatus != status else { return }
            self.calendarStatus = status
        }
    }

    private func updateRemindersStatus(_ status: EKAuthorizationStatus) {
        guard remindersStatus != status else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.remindersStatus != status else { return }
            self.remindersStatus = status
        }
    }

    private func updateLocationStatus(_ status: CLAuthorizationStatus) {
        guard locationStatus != status else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.locationStatus != status else { return }
            self.locationStatus = status
        }
    }
    
    // MARK: - Status Helpers
    
    var isNotificationsAuthorized: Bool {
        notificationStatus == .authorized || notificationStatus == .provisional
    }
    
    var isCalendarAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return calendarStatus == .fullAccess || calendarStatus == .writeOnly
        } else {
            return calendarStatus == .authorized
        }
    }
    
    var isRemindersAuthorized: Bool {
        if #available(macOS 14.0, *) {
            return remindersStatus == .fullAccess || remindersStatus == .writeOnly
        } else {
            return remindersStatus == .authorized
        }
    }

    var isLocationAuthorized: Bool {
        locationStatus == .authorizedAlways
    }
    
    var notificationStatusText: String {
        switch notificationStatus {
        case .notDetermined:
            return LocalizationManager.shared.text("permission.not_determined")
        case .denied:
            return LocalizationManager.shared.text("permission.denied")
        case .authorized, .provisional:
            return LocalizationManager.shared.text("permission.authorized")
        case .ephemeral:
            return LocalizationManager.shared.text("permission.ephemeral")
        @unknown default:
            return LocalizationManager.shared.text("permission.unknown")
        }
    }
    
    var calendarStatusText: String {
        if #available(macOS 14.0, *) {
            switch calendarStatus {
            case .notDetermined: return LocalizationManager.shared.text("permission.not_determined")
            case .restricted: return LocalizationManager.shared.text("permission.restricted")
            case .denied: return LocalizationManager.shared.text("permission.denied")
            case .fullAccess: return LocalizationManager.shared.text("permission.full_access")
            case .writeOnly: return LocalizationManager.shared.text("permission.write_only")
            default: return LocalizationManager.shared.text("permission.unknown")
            }
        } else {
            switch calendarStatus {
            case .notDetermined: return LocalizationManager.shared.text("permission.not_determined")
            case .restricted: return LocalizationManager.shared.text("permission.restricted")
            case .denied: return LocalizationManager.shared.text("permission.denied")
            case .authorized: return LocalizationManager.shared.text("permission.authorized")
            default: return LocalizationManager.shared.text("permission.unknown")
            }
        }
    }
    
    var remindersStatusText: String {
        if #available(macOS 14.0, *) {
            switch remindersStatus {
            case .notDetermined: return LocalizationManager.shared.text("permission.not_determined")
            case .restricted: return LocalizationManager.shared.text("permission.restricted")
            case .denied: return LocalizationManager.shared.text("permission.denied")
            case .fullAccess: return LocalizationManager.shared.text("permission.full_access")
            case .writeOnly: return LocalizationManager.shared.text("permission.write_only")
            default: return LocalizationManager.shared.text("permission.unknown")
            }
        } else {
            switch remindersStatus {
            case .notDetermined: return LocalizationManager.shared.text("permission.not_determined")
            case .restricted: return LocalizationManager.shared.text("permission.restricted")
            case .denied: return LocalizationManager.shared.text("permission.denied")
            case .authorized: return LocalizationManager.shared.text("permission.authorized")
            default: return LocalizationManager.shared.text("permission.unknown")
            }
        }
    }

    var locationStatusText: String {
        switch locationStatus {
        case .notDetermined:
            return LocalizationManager.shared.text("permission.not_determined")
        case .restricted:
            return LocalizationManager.shared.text("permission.restricted")
        case .denied:
            return LocalizationManager.shared.text("permission.denied")
        case .authorizedAlways:
            return LocalizationManager.shared.text("permission.authorized")
        @unknown default:
            return LocalizationManager.shared.text("permission.unknown")
        }
    }

    var calendarReminderLocationPermissionStatusText: String {
        let l10n = LocalizationManager.shared
        if isCalendarAuthorized && isRemindersAuthorized && isLocationAuthorized {
            return l10n.text("permissions.status.calendar_reminders_location_enabled")
        }
        if isCalendarAuthorized && isRemindersAuthorized {
            return l10n.text("permissions.status.calendar_and_reminders_enabled_location_optional")
        }
        if isLocationAuthorized {
            return l10n.text("permissions.status.location_enabled_schedule_optional")
        }
        return l10n.text("permissions.status.access_not_granted")
    }
}

import Foundation
import Combine
import CoreLocation
import UserNotifications

struct WorkLocation: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var tags: [String]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        address: String = "",
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct LocationNotificationRule: Identifiable, Codable, Equatable {
    let id: UUID
    let locationID: UUID
    var isEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        locationID: UUID,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.locationID = locationID
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
final class LocationStore: ObservableObject {
    static let freeTaskLocationLimit = 10

    @Published private(set) var locations: [WorkLocation] = []
    @Published private(set) var notificationRules: [LocationNotificationRule] = []

    private let locationsKey = "com.pomodoro.workspace.locations"
    private let notificationRulesKey = "com.pomodoro.workspace.locationNotificationRules"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    @discardableResult
    func addLocation(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150,
        tags: [String] = []
    ) -> WorkLocation? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              latitude.isFinite,
              longitude.isFinite else {
            return nil
        }

        let location = WorkLocation(
            name: trimmedName,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            radiusMeters: max(50, min(radiusMeters, 1_000)),
            tags: normalizedTags(tags)
        )
        locations.insert(location, at: 0)
        saveLocations()
        return location
    }

    func updateLocation(_ location: WorkLocation) {
        guard let index = locations.firstIndex(where: { $0.id == location.id }) else { return }
        var updated = location
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { return }
        updated.address = updated.address.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.radiusMeters = max(50, min(updated.radiusMeters, 1_000))
        updated.tags = normalizedTags(updated.tags)
        updated.updatedAt = Date()
        locations[index] = updated
        saveLocations()
    }

    func deleteLocation(_ location: WorkLocation) {
        locations.removeAll { $0.id == location.id }
        notificationRules.removeAll { $0.locationID == location.id }
        saveLocations()
        saveNotificationRules()
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: location.id)]
        )
    }

    func location(id: UUID?) -> WorkLocation? {
        guard let id else { return nil }
        return locations.first { $0.id == id }
    }

    func notificationRule(for locationID: UUID) -> LocationNotificationRule? {
        notificationRules.first { $0.locationID == locationID }
    }

    func currentLocation() async throws -> CLLocation {
        try await LocationCurrentPositionProvider.shared.currentLocation()
    }

    func enableNotification(for location: WorkLocation, taskCount: Int) async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { throw LocationStoreError.notificationPermissionDenied }

        try await LocationAuthorizationRequester.shared.requestWhenInUse()

        LocationRuntimeNotifier.shared.startMonitoring(location: location, taskCount: taskCount)

        if let index = notificationRules.firstIndex(where: { $0.locationID == location.id }) {
            notificationRules[index].isEnabled = true
            notificationRules[index].updatedAt = Date()
        } else {
            notificationRules.insert(LocationNotificationRule(locationID: location.id), at: 0)
        }
        saveNotificationRules()
    }

    func disableNotification(for locationID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: locationID)]
        )
        LocationRuntimeNotifier.shared.stopMonitoring(locationID: locationID)
        if let index = notificationRules.firstIndex(where: { $0.locationID == locationID }) {
            notificationRules[index].isEnabled = false
            notificationRules[index].updatedAt = Date()
            saveNotificationRules()
        }
    }

    private func notificationIdentifier(for locationID: UUID) -> String {
        "orchestrana.location.\(locationID.uuidString)"
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed.lowercased()) else { return nil }
            seen.insert(trimmed.lowercased())
            return trimmed
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: locationsKey),
           let decoded = try? decoder.decode([WorkLocation].self, from: data) {
            locations = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let data = UserDefaults.standard.data(forKey: notificationRulesKey),
           let decoded = try? decoder.decode([LocationNotificationRule].self, from: data) {
            notificationRules = decoded
        }
    }

    private func saveLocations() {
        if let encoded = try? encoder.encode(locations) {
            UserDefaults.standard.set(encoded, forKey: locationsKey)
        }
    }

    private func saveNotificationRules() {
        if let encoded = try? encoder.encode(notificationRules) {
            UserDefaults.standard.set(encoded, forKey: notificationRulesKey)
        }
    }
}

enum LocationStoreError: LocalizedError {
    case notificationPermissionDenied
    case locationPermissionDenied

    var errorDescription: String? {
        switch self {
        case .notificationPermissionDenied:
            return "Notification permission is required for location notifications."
        case .locationPermissionDenied:
            return "Location permission is required for location notifications."
        }
    }
}

final class LocationAuthorizationRequester: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizationRequester()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Error>?

    private override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse() async throws {
        let status = manager.authorizationStatus
        if status == .authorizedAlways {
            return
        }
        if status == .denied || status == .restricted {
            throw LocationStoreError.locationPermissionDenied
        }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation else { return }
        self.continuation = nil
        let status = manager.authorizationStatus
        if status == .authorizedAlways {
            continuation.resume()
        } else if status == .denied || status == .restricted {
            continuation.resume(throwing: LocationStoreError.locationPermissionDenied)
        }
    }
}

final class LocationCurrentPositionProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationCurrentPositionProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        try await LocationAuthorizationRequester.shared.requestWhenInUse()
        if let location = manager.location {
            return location
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation else { return }
        self.continuation = nil
        if let location = locations.last {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: LocationStoreError.locationPermissionDenied)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

final class LocationRuntimeNotifier: NSObject, CLLocationManagerDelegate {
    static let shared = LocationRuntimeNotifier()

    private struct Payload {
        let name: String
        let taskCount: Int
    }

    private let manager = CLLocationManager()
    private var payloadsByIdentifier: [String: Payload] = [:]

    private override init() {
        super.init()
        manager.delegate = self
    }

    func startMonitoring(location: WorkLocation, taskCount: Int) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(
            center: location.coordinate,
            radius: max(50, min(location.radiusMeters, 1_000)),
            identifier: location.id.uuidString
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false
        payloadsByIdentifier[region.identifier] = Payload(name: location.name, taskCount: taskCount)
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(locationID: UUID) {
        let identifier = locationID.uuidString
        payloadsByIdentifier.removeValue(forKey: identifier)
        for region in manager.monitoredRegions where region.identifier == identifier {
            manager.stopMonitoring(for: region)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let payload = payloadsByIdentifier[region.identifier] else { return }
        let content = UNMutableNotificationContent()
        content.title = "You're near \(payload.name)"
        content.body = payload.taskCount == 1 ? "1 task is available here." : "\(payload.taskCount) tasks are available here."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "orchestrana.location.entry.\(region.identifier)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}

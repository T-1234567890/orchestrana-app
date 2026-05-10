import SwiftUI
import MapKit

@MainActor
struct WorkLocationPickerSheet: View {
    @ObservedObject var locationStore: LocationStore

    let title: String
    let canCreateNewLocation: Bool
    let canUseLocationNotifications: Bool
    let notificationTaskCount: Int
    let onCreateLimitReached: () -> Void
    let onCancel: () -> Void
    let onSelect: (UUID) -> Void

    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var isResolvingCurrentLocation = false
    @State private var selectedCandidate: LocationCandidate?
    @State private var placeName = ""
    @State private var radiusMeters = 150.0
    @State private var tagField = ""
    @State private var notifyWhenClose = false
    @State private var errorMessage: String?
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
        )
    )
    @State private var searchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
    )

    private struct LocationCandidate: Identifiable {
        let id = UUID()
        var name: String
        var address: String
        var coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text("Use your current location or search for a place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 14) {
                mapPreview
                locationControls
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Save and Pin") {
                    saveAndPin()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCandidate == nil || placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 680)
        .onChange(of: selectedCandidate?.id) { _, _ in
            guard let selectedCandidate else { return }
            placeName = selectedCandidate.name
            centerMap(on: selectedCandidate.coordinate)
        }
        .onAppear {
            Task { await centerPreviewOnCurrentLocation() }
        }
    }

    private var mapPreview: some View {
        ZStack {
            Map(position: $mapPosition) {
                if let selectedCandidate {
                    Marker(selectedCandidate.name, coordinate: selectedCandidate.coordinate)
                        .tint(Color.accentColor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if selectedCandidate == nil {
                Text("Select a place")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(width: 300, height: 330)
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        searchRegion = region
        mapPosition = .region(region)
    }

    private var locationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                if isResolvingCurrentLocation {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finding current location")
                } else {
                    Label("Use Current Location", systemImage: "location.fill")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isResolvingCurrentLocation)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Search location", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await searchPlaces() }
                    }

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !searchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(searchResults.prefix(5).enumerated()), id: \.offset) { _, item in
                            Button {
                                selectMapItem(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Untitled Place")
                                        .lineLimit(1)
                                    Text(address(for: item.placemark))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 3)
                        }
                    }
                }
            }

            if !locationStore.locations.isEmpty {
                Divider()
                Text("Saved places")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(locationStore.locations.prefix(5)) { location in
                            Button {
                                onSelect(location.id)
                            } label: {
                                Label(location.name, systemImage: "mappin.circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 86)
            }

            Divider()

            TextField("Place name", text: $placeName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notification radius \(Int(radiusMeters))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $radiusMeters, in: 50...1_000, step: 25)
            }

            if canUseLocationNotifications {
                Toggle("Notify when close", isOn: $notifyWhenClose)
            }

            if canUseLocationNotifications {
                TextField("Location tags", text: $tagField, prompt: Text("Near Home, Downtown"))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(width: 320)
    }

    private func useCurrentLocation() async {
        isResolvingCurrentLocation = true
        errorMessage = nil
        defer { isResolvingCurrentLocation = false }

        do {
            let location = try await locationStore.currentLocation()
            let candidate = LocationCandidate(
                name: "Current Location",
                address: formattedCoordinate(location.coordinate),
                coordinate: location.coordinate
            )
            selectedCandidate = candidate
            placeName = candidate.name
            centerMap(on: candidate.coordinate)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func centerPreviewOnCurrentLocation() async {
        guard selectedCandidate == nil else { return }
        do {
            let location = try await locationStore.currentLocation()
            centerMap(on: location.coordinate)
        } catch {
            // Keep the neutral fallback until the user searches or grants Location permission.
        }
    }

    private func searchPlaces() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = searchRegion
        do {
            searchResults = try await MKLocalSearch(request: request).start().mapItems
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectMapItem(_ item: MKMapItem) {
        let candidate = LocationCandidate(
            name: item.name ?? searchText,
            address: address(for: item.placemark),
            coordinate: item.placemark.coordinate
        )
        selectedCandidate = candidate
        placeName = candidate.name
        centerMap(on: candidate.coordinate)
    }

    private func saveAndPin() {
        guard let selectedCandidate else { return }
        guard canCreateNewLocation else {
            onCreateLimitReached()
            return
        }

        let tags = canUseLocationNotifications
            ? tagField.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            : []
        guard let location = locationStore.addLocation(
            name: placeName,
            address: selectedCandidate.address,
            latitude: selectedCandidate.coordinate.latitude,
            longitude: selectedCandidate.coordinate.longitude,
            radiusMeters: radiusMeters,
            tags: tags
        ) else {
            errorMessage = "Enter a valid place name."
            return
        }

        if notifyWhenClose, canUseLocationNotifications {
            Task {
                try? await locationStore.enableNotification(
                    for: location,
                    taskCount: max(1, notificationTaskCount)
                )
            }
        }
        onSelect(location.id)
    }

    private func address(for placemark: MKPlacemark) -> String {
        [
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode,
            placemark.country
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private func formattedCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
}

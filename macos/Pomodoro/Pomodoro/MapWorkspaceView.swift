import SwiftUI
import MapKit
import EventKit

@MainActor
struct MapWorkspaceView: View {
    @ObservedObject var locationStore: LocationStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var planningStore: PlanningStore
    @ObservedObject var calendarManager: CalendarManager
    @ObservedObject var goalStore: GoalStore
    @ObservedObject var featureGate: FeatureGate
    var onScrollOffsetChange: ((CGFloat) -> Void)? = nil
    @AppStorage(DeveloperDemoMode.googleVideoDemoModeKey) private var googleVideoDemoMode = false

    @State private var filter: MapWorkFilter = .standard
    @State private var selectedLocationID: UUID?
    @State private var selectedTag: String?
    @State private var selectedWorkItemID: String?
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
        )
    )
    @State private var hasCenteredInitialMap = false
    @State private var searchText = ""
    @State private var placeResults: [MKMapItem] = []
    @State private var isSearchingPlaces = false
    @State private var tagField = ""
    @State private var mapMessage: String?
    @State private var upgradePaywallContext: SubscriptionPaywallContext?
    @State private var spatialRouteItemIDs: [String] = []
    @State private var selectedTaskDetailID: UUID?

    private enum MapWorkFilter: String, Identifiable {
        case standard = "Standard"
        case spatial = "Spatial Work"

        var id: String { rawValue }
    }

    private struct MapWorkItem: Identifiable {
        enum Kind: String {
            case task
            case event
        }

        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        let coordinate: CLLocationCoordinate2D
        let locationID: UUID?
        let date: Date?
        let isCompleted: Bool
        let isGoalRelated: Bool
    }

    private var canUseUnlimitedTaskLocations: Bool {
        switch featureGate.tier {
        case .plus, .pro, .developer:
            return true
        case .free, .beta, .expired:
            return false
        }
    }

    private var canUseLocationTagsAndNotifications: Bool {
        switch featureGate.tier {
        case .plus, .pro, .developer:
            return true
        case .free, .beta, .expired:
            return false
        }
    }

    private var canUseSpatialWork: Bool {
        switch featureGate.tier {
        case .pro, .developer:
            return true
        case .free, .beta, .plus, .expired:
            return false
        }
    }

    private var taskLocationCount: Int {
        visibleTodoItems.filter { $0.locationID != nil }.count
    }

    private var allTags: [String] {
        Array(Set(locationStore.locations.flatMap(\.tags))).sorted()
    }

    private var availableMapModes: [MapWorkFilter] {
        [.standard, .spatial]
    }

    private var allWorkItems: [MapWorkItem] {
        let taskItems = visibleTodoItems.compactMap { task -> MapWorkItem? in
            guard let location = locationStore.location(id: task.locationID) else { return nil }
            return MapWorkItem(
                id: "task-\(task.id.uuidString)",
                kind: .task,
                title: task.title,
                subtitle: location.name,
                coordinate: location.coordinate,
                locationID: location.id,
                date: task.dueDate,
                isCompleted: task.isCompleted,
                isGoalRelated: goalStore.links.contains { $0.kind == .task && $0.targetID == task.id.uuidString }
            )
        }

        let localEventItems = visiblePlanningItems.compactMap { event -> MapWorkItem? in
            guard event.isCalendarEvent,
                  let location = locationStore.location(id: event.locationID) else { return nil }
            return MapWorkItem(
                id: "event-\(event.id.uuidString)",
                kind: .event,
                title: event.title,
                subtitle: eventSubtitle(event, locationName: location.name),
                coordinate: location.coordinate,
                locationID: location.id,
                date: event.startDate,
                isCompleted: event.completed,
                isGoalRelated: goalStore.links.contains { $0.kind == .event && $0.targetID == event.id.uuidString }
            )
        }

        let systemEventItems = visibleSystemEvents.compactMap { event -> MapWorkItem? in
            guard let coordinate = event.structuredLocation?.geoLocation?.coordinate,
                  let identifier = event.eventIdentifier else { return nil }
            return MapWorkItem(
                id: "system-event-\(identifier)",
                kind: .event,
                title: event.title ?? "Untitled Event",
                subtitle: event.location ?? event.structuredLocation?.title ?? "Calendar event",
                coordinate: coordinate,
                locationID: nil,
                date: event.startDate,
                isCompleted: false,
                isGoalRelated: isSystemEventGoalRelated(identifier: identifier)
            )
        }

        return taskItems + localEventItems + systemEventItems
    }

    private var isGoogleVideoDemoModeEnabled: Bool {
        DeveloperDemoMode.isGoogleVideoDemoModeEnabled(tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private var visibleTodoItems: [TodoItem] {
        DeveloperDemoMode.visibleTasks(todoStore.items, tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private var visiblePlanningItems: [PlanningItem] {
        DeveloperDemoMode.visiblePlanningItems(planningStore.items, tier: featureGate.tier, storedValue: googleVideoDemoMode)
    }

    private var visibleSystemEvents: [EKEvent] {
        guard !isGoogleVideoDemoModeEnabled else {
            return []
        }
        return calendarManager.events.filter {
            DeveloperDemoMode.isSystemEventVisible(
                identifier: $0.eventIdentifier,
                tier: featureGate.tier,
                storedValue: googleVideoDemoMode
            )
        }
    }

    private var filteredWorkItems: [MapWorkItem] {
        var items = allWorkItems
        switch filter {
        case .standard:
            break
        case .spatial:
            items = spatialSequence(items.filter { !$0.isCompleted })
        }

        if let selectedLocationID {
            items = items.filter { $0.locationID == selectedLocationID }
        }

        if let selectedTag {
            let taggedLocationIDs = Set(
                locationStore.locations
                    .filter { $0.tags.contains(selectedTag) }
                    .map(\.id)
            )
            items = items.filter { item in
                guard let locationID = item.locationID else { return false }
                return taggedLocationIDs.contains(locationID)
            }
        }

        return items
    }

    private var visibleSpatialRouteItems: [MapWorkItem] {
        spatialRouteItemIDs.compactMap { id in
            filteredWorkItems.first { $0.id == id }
        }
    }

    private var visibleSpatialRouteCoordinates: [CLLocationCoordinate2D] {
        visibleSpatialRouteItems.map(\.coordinate)
    }

    private var selectedTaskDetail: TodoItem? {
        guard let selectedTaskDetailID else { return nil }
        return visibleTodoItems.first { $0.id == selectedTaskDetailID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let mapMessage {
                Text(mapMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(alignment: .top, spacing: 14) {
                mapPanel
                sidePanel
            }
        }
        .onAppear {
            Task { await centerInitialMapLocation() }
        }
        .onChange(of: filteredWorkItems.map(\.id)) { _, _ in
            if !hasCenteredInitialMap {
                centerMapIfPossible()
            }
        }
        .onChange(of: allWorkItems.map(\.id)) { _, itemIDs in
            spatialRouteItemIDs.removeAll { !itemIDs.contains($0) }
        }
        .onReceive(featureGate.$tier) { _ in
            resetSpatialModeIfNeeded()
        }
        .sheet(item: $upgradePaywallContext) { context in
            SubscriptionUpgradeSheetView(
                context: context,
                featureGate: featureGate,
                subscriptionStore: SubscriptionStore.shared
            )
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Work by Place")
                    .font(.title3.weight(.semibold))
                Text("See tasks and events in spatial context.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Map mode", selection: Binding(
                get: { filter },
                set: { newValue in
                    selectMapMode(newValue)
                }
            )) {
                ForEach(availableMapModes) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
        }
    }

    private var mapPanel: some View {
        VStack(spacing: 0) {
            if filteredWorkItems.isEmpty {
                emptyMapState
            } else {
                Map(position: $mapPosition) {
                    if visibleSpatialRouteCoordinates.count > 1 {
                        MapPolyline(coordinates: visibleSpatialRouteCoordinates)
                            .stroke(Color.accentColor.opacity(0.85), lineWidth: 4)
                    }

                    ForEach(filteredWorkItems) { item in
                        Annotation("", coordinate: item.coordinate) {
                            Button {
                                handleMapPinClick(item)
                            } label: {
                                mapPin(for: item)
                            }
                            .buttonStyle(.plain)
                            .help(mapPinHelp(for: item))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let selectedTaskDetail {
                        MapTaskDetailPopover(
                            task: selectedTaskDetail,
                            locationName: selectedTaskDetail.locationID.flatMap { locationStore.location(id: $0)?.name },
                            onClose: { selectedTaskDetailID = nil }
                        )
                        .padding(12)
                    }
                }
            }
        }
        .frame(minHeight: 420)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyMapState: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Add locations to tasks or events to see where your work happens.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Calendar events with structured locations appear automatically when Calendar permission is enabled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            filterPanel
            placeSearchPanel
            if filter == .spatial {
                spatialRoutePanel
            }
            workListPanel
        }
        .frame(width: 340)
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.headline)

            Picker("Location", selection: $selectedLocationID) {
                Text("All locations").tag(UUID?.none)
                ForEach(locationStore.locations) { location in
                    Text(location.name).tag(Optional(location.id))
                }
            }

            if !allTags.isEmpty {
                Picker("Tag", selection: $selectedTag) {
                    Text("All tags").tag(String?.none)
                    ForEach(allTags, id: \.self) { tag in
                        Text(tag).tag(Optional(tag))
                    }
                }
            }

            Text("Free supports up to \(LocationStore.freeTaskLocationLimit) saved task locations. Plus unlocks unlimited locations, tags, and location notifications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var placeSearchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved places")
                .font(.headline)

            HStack {
                TextField("Search a place or address", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await searchPlaces() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingPlaces)
            }

            if canUseLocationTagsAndNotifications {
                TextField("Tags, comma separated", text: $tagField)
                    .textFieldStyle(.roundedBorder)
            }

            if isSearchingPlaces {
                ProgressView()
                    .controlSize(.small)
            }

            ForEach(placeResults.prefix(4), id: \.self) { item in
                Button {
                    savePlace(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Unnamed Place")
                            .font(.subheadline.weight(.semibold))
                        Text(item.placemark.title ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if !locationStore.locations.isEmpty {
                Divider()
                ForEach(locationStore.locations.prefix(5)) { location in
                    savedLocationRow(location)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var workListPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(filter == .spatial ? "Route candidates" : "Visible work")
                    .font(.headline)
                Spacer()
                if filter == .spatial, !spatialRouteItemIDs.isEmpty {
                    Text("\(visibleSpatialRouteItems.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: MapWorkspaceScrollOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named("mapWorkListScroll")).minY
                        )
                }
                .frame(height: 0)

                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredWorkItems) { item in
                        HStack(spacing: 8) {
                            if filter == .spatial {
                                spatialRouteToggle(for: item)
                            }
                            Button {
                                selectedWorkItemID = item.id
                                centerMap(on: item.coordinate)
                            } label: {
                                workItemRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .coordinateSpace(name: "mapWorkListScroll")
            .onPreferenceChange(MapWorkspaceScrollOffsetPreferenceKey.self) { offset in
                onScrollOffsetChange?(offset)
            }
            .frame(maxHeight: 240)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var spatialRoutePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spatial route")
                        .font(.headline)
                    Text("Click pins or use the list to link tasks and events in route order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !spatialRouteItemIDs.isEmpty {
                    Button("Clear") {
                        spatialRouteItemIDs = []
                    }
                    .font(.caption)
                }
            }

            if visibleSpatialRouteItems.isEmpty {
                Text("Select tasks or events below to build a route.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(visibleSpatialRouteItems.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            routeOrderButtons(for: item)
                        }
                    }
                }
            }

            Button {
                openSpatialRouteInAppleMaps()
            } label: {
                Label("Open Apple Maps Directions", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .disabled(visibleSpatialRouteItems.isEmpty)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func savedLocationRow(_ location: WorkLocation) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.subheadline.weight(.semibold))
                if !location.tags.isEmpty {
                    Text(location.tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                if canUseLocationTagsAndNotifications {
                    Button {
                        Task { await enableNotification(for: location) }
                    } label: {
                        Label("Notify Near This Place", systemImage: "bell.badge")
                    }
                    Button {
                        locationStore.disableNotification(for: location.id)
                    } label: {
                        Label("Disable Location Notification", systemImage: "bell.slash")
                    }
                } else {
                    Button {
                        presentPaywall(requiredTier: .plus, title: "Location notifications require Plus", message: "Upgrade to Plus to use location tags and near-place notifications.")
                    } label: {
                        Label("Notify Near This Place", systemImage: "bell.badge")
                    }
                }

                Button(role: .destructive) {
                    locationStore.deleteLocation(location)
                } label: {
                    Label("Delete Place", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }

    private func workItemRow(_ item: MapWorkItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .task ? "checklist" : "calendar")
                .foregroundStyle(item.kind == .task ? Color.accentColor : Color.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let routeIndex = spatialRouteIndex(for: item) {
                Text("\(routeIndex + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.accentColor, in: Circle())
            }
            if item.isGoalRelated {
                Image(systemName: "target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(selectedWorkItemID == item.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func mapPin(for item: MapWorkItem) -> some View {
        VStack(spacing: 4) {
            Text(item.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .frame(maxWidth: 130)
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1)

            ZStack(alignment: .topTrailing) {
                Image(systemName: item.kind == .task ? "checkmark.circle.fill" : "calendar.circle.fill")
                    .font(.system(size: selectedWorkItemID == item.id ? 34 : 30, weight: .semibold))
                    .foregroundStyle(pinColor(for: item))
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2)

                if let routeIndex = spatialRouteIndex(for: item) {
                    Text("\(routeIndex + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 8, y: -8)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func pinColor(for item: MapWorkItem) -> Color {
        if spatialRouteItemIDs.contains(item.id) {
            return .accentColor
        }
        return item.kind == .task ? .accentColor : .purple
    }

    private func mapPinHelp(for item: MapWorkItem) -> String {
        if filter == .spatial {
            return spatialRouteItemIDs.contains(item.id) ? "Already in route" : "Add to route"
        }
        return "Open details"
    }

    private func spatialRouteToggle(for item: MapWorkItem) -> some View {
        Button {
            toggleSpatialRouteItem(item)
        } label: {
            Image(systemName: spatialRouteItemIDs.contains(item.id) ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(spatialRouteItemIDs.contains(item.id) ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(spatialRouteItemIDs.contains(item.id) ? "Remove from route" : "Add to route")
    }

    private func routeOrderButtons(for item: MapWorkItem) -> some View {
        HStack(spacing: 4) {
            Button {
                moveSpatialRouteItem(item, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(spatialRouteIndex(for: item) == 0)

            Button {
                moveSpatialRouteItem(item, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(spatialRouteIndex(for: item) == spatialRouteItemIDs.count - 1)
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func searchPlaces() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearchingPlaces = true
        mapMessage = nil
        defer { isSearchingPlaces = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            placeResults = Array(response.mapItems.prefix(8))
            if placeResults.isEmpty {
                mapMessage = "No matching places found."
            }
        } catch {
            mapMessage = "Could not search places right now."
        }
    }

    private func savePlace(_ item: MKMapItem) {
        let tags = canUseLocationTagsAndNotifications
            ? tagField.split(separator: ",").map { String($0) }
            : []
        _ = locationStore.addLocation(
            name: item.name ?? item.placemark.title ?? "Saved Place",
            address: item.placemark.title ?? "",
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            tags: tags
        )
        placeResults = []
        searchText = ""
        tagField = ""
        mapMessage = nil
    }

    private func enableNotification(for location: WorkLocation) async {
        do {
            try await locationStore.enableNotification(
                for: location,
                taskCount: max(1, visibleTodoItems.filter { $0.locationID == location.id && !$0.isCompleted }.count)
            )
            mapMessage = "Location notification enabled for \(location.name)."
        } catch {
            mapMessage = error.localizedDescription
        }
    }

    private func centerMapIfPossible() {
        guard let first = filteredWorkItems.first else { return }
        centerMap(on: first.coordinate)
        hasCenteredInitialMap = true
    }

    private func centerInitialMapLocation() async {
        guard !hasCenteredInitialMap else { return }
        do {
            let location = try await locationStore.currentLocation()
            centerMap(on: location.coordinate)
            hasCenteredInitialMap = true
        } catch {
            centerMapIfPossible()
        }
    }

    private func resetSpatialModeIfNeeded() {
        if filter == .spatial, !canUseSpatialWork {
            filter = .standard
            spatialRouteItemIDs = []
        }
    }

    private func selectMapMode(_ mode: MapWorkFilter) {
        guard mode != .spatial || canUseSpatialWork else {
            presentPaywall(
                requiredTier: .pro,
                title: "Unlock Spatial Work",
                message: "Pro includes spatial routes for linked tasks and events, with Apple Maps directions when you are ready to go."
            )
            return
        }

        filter = mode
    }

    private func eventSubtitle(_ event: PlanningItem, locationName: String) -> String {
        guard let startDate = event.startDate else { return locationName }
        return "\(locationName) · \(startDate.formatted(date: .abbreviated, time: .shortened))"
    }

    private func isSystemEventGoalRelated(identifier: String) -> Bool {
        guard let snapshot = visiblePlanningItems.first(where: { $0.calendarEventIdentifier == identifier }) else {
            return false
        }
        return goalStore.links.contains { $0.kind == .event && $0.targetID == snapshot.id.uuidString }
    }

    private func spatialSequence(_ items: [MapWorkItem]) -> [MapWorkItem] {
        items.sorted { lhs, rhs in
            if let lhsLocation = lhs.locationID.flatMap(locationStore.location),
               let rhsLocation = rhs.locationID.flatMap(locationStore.location) {
                return lhsLocation.name.localizedCaseInsensitiveCompare(rhsLocation.name) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func toggleSpatialRouteItem(_ item: MapWorkItem) {
        if let index = spatialRouteItemIDs.firstIndex(of: item.id) {
            spatialRouteItemIDs.remove(at: index)
        } else {
            spatialRouteItemIDs.append(item.id)
        }
    }

    private func handleMapPinClick(_ item: MapWorkItem) {
        selectedWorkItemID = item.id
        centerMap(on: item.coordinate)
        if let id = taskID(from: item.id) {
            selectedTaskDetailID = id
        }

        if filter == .spatial {
            guard !spatialRouteItemIDs.contains(item.id) else { return }
            spatialRouteItemIDs.append(item.id)
        }
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        mapPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        )
    }

    private func spatialRouteIndex(for item: MapWorkItem) -> Int? {
        spatialRouteItemIDs.firstIndex(of: item.id)
    }

    private func moveSpatialRouteItem(_ item: MapWorkItem, offset: Int) {
        guard let currentIndex = spatialRouteIndex(for: item) else { return }
        let newIndex = currentIndex + offset
        guard spatialRouteItemIDs.indices.contains(newIndex) else { return }
        spatialRouteItemIDs.swapAt(currentIndex, newIndex)
    }

    private func openSpatialRouteInAppleMaps() {
        let routeItems = visibleSpatialRouteItems
        guard !routeItems.isEmpty else {
            mapMessage = "Select at least one task or event for the route."
            return
        }

        let mapItems = routeItems.map { item -> MKMapItem in
            let placemark = MKPlacemark(coordinate: item.coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = item.title
            return mapItem
        }
        let launchOptions = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]

        if mapItems.count == 1 {
            mapItems[0].openInMaps(launchOptions: launchOptions)
        } else {
            MKMapItem.openMaps(with: mapItems, launchOptions: launchOptions)
        }
    }

    private func taskID(from itemID: String) -> UUID? {
        guard itemID.hasPrefix("task-") else { return nil }
        return UUID(uuidString: String(itemID.dropFirst("task-".count)))
    }

    private func presentPaywall(requiredTier: PlanTier, title: String, message: String) {
        upgradePaywallContext = SubscriptionPaywallContext(requiredTier: requiredTier, title: title, message: message)
    }
}

private struct MapWorkspaceScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MapTaskDetailPopover: View {
    let task: TodoItem
    let locationName: String?
    let onClose: () -> Void

    private var completedSubtaskCount: Int {
        task.subtasks.filter(\.completed).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(task.isCompleted ? "Completed" : "Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                if let dueDate = task.dueDate {
                    detailRow(
                        title: "Due",
                        value: dueDate.formatted(date: .abbreviated, time: task.hasDueTime ? .shortened : .omitted),
                        systemImage: "calendar"
                    )
                }

                if task.priority != .none {
                    detailRow(title: "Priority", value: task.priority.displayName, systemImage: "flag")
                }

                if let durationMinutes = task.durationMinutes {
                    detailRow(title: "Duration", value: "\(durationMinutes)m", systemImage: "timer")
                }

                if let locationName {
                    detailRow(title: "Location", value: locationName, systemImage: "mappin.and.ellipse")
                }

                if !task.tags.isEmpty {
                    detailRow(title: "Tags", value: task.tags.joined(separator: ", "), systemImage: "tag")
                }

                if !task.subtasks.isEmpty {
                    detailRow(
                        title: "Subtasks",
                        value: "\(completedSubtaskCount) / \(task.subtasks.count) complete",
                        systemImage: "checklist"
                    )
                }
            }

            if let notes = task.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
    }

    private func detailRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .font(.caption)
    }
}

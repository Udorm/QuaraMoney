import CoreLocation
import MapKit
import SwiftUI

struct TransactionLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: TransactionLocationSelection?

    @State private var searchModel = TransactionPlaceSearchModel()
    @State private var locationService = CurrentLocationService()
    @State private var draftSelection: TransactionLocationSelection?
    @State private var currentLocationSelection: TransactionLocationSelection?
    @State private var nearbySuggestions: [TransactionLocationSelection] = []
    /// Device location, kept so suggestion rows can show how far away each place is.
    @State private var userLocation: CLLocation?
    @State private var isLoadingCurrentLocation = false
    @State private var isLoadingSuggestions = false
    @State private var hasAttemptedNearbyLoad = false
    @State private var showManualMapPicker = false
    @State private var errorMessage: String?
    @State private var scrollToSelectionToken = 0
    @FocusState private var isSearchFocused: Bool

    private static let selectedSectionID = "selectedLocationSection"

    init(selection: Binding<TransactionLocationSelection?>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue)
    }

    private var trimmedQuery: String {
        searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool { !trimmedQuery.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if isSearchActive {
                        searchResultsSection
                    } else {
                        if let draftSelection {
                            selectedLocationSection(draftSelection)
                        }
                        quickActionsSection
                        suggestionsSection
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: scrollToSelectionToken) { _, _ in
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(Self.selectedSectionID, anchor: .top)
                    }
                }
            }
            .navigationTitle("transaction.location.pick".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localized) {
                        selection = draftSelection
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaBar(edge: .bottom) {
                searchBar
            }
            .sheet(isPresented: $showManualMapPicker) {
                TransactionManualMapPinView(initialSelection: draftSelection ?? currentLocationSelection) { selectedLocation in
                    selectDraft(selectedLocation)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("transaction.location.errorTitle".localized, isPresented: errorBinding) {
                Button("common.ok".localized, role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await loadNearbySuggestionsIfNeeded()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func selectedLocationSection(_ selection: TransactionLocationSelection) -> some View {
        Section {
            Button {
                showManualMapPicker = true
            } label: {
                SelectedLocationMapPreview(selection: selection)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("transaction.location.adjustOnMap".localized)

            SelectedLocationRow(selection: selection) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    draftSelection = nil
                }
            }
        } header: {
            Text("transaction.location.selected".localized)
        }
        .id(Self.selectedSectionID)
    }

    private var quickActionsSection: some View {
        Section {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                LocationActionRow(
                    title: "transaction.location.useCurrent".localized,
                    subtitle: currentLocationSelection?.subtitle ?? "transaction.location.useCurrentSubtitle".localized,
                    systemImage: "location.fill",
                    isLoading: isLoadingCurrentLocation,
                    isSelected: isSelected(currentLocationSelection)
                )
            }
            // Without `.plain`, a List tints the whole custom label with the accent
            // colour, which washes out the place names and addresses.
            .buttonStyle(.plain)
            .disabled(isLoadingCurrentLocation)

            Button {
                showManualMapPicker = true
            } label: {
                LocationActionRow(
                    title: "transaction.location.pinOnMap".localized,
                    subtitle: "transaction.location.pinOnMapSubtitle".localized,
                    systemImage: "map.fill"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        Section {
            if isLoadingSuggestions {
                loadingRow("transaction.location.loadingNearby")
            }

            ForEach(Array(nearbySuggestions.enumerated()), id: \.offset) { _, suggestion in
                Button {
                    selectDraft(suggestion)
                } label: {
                    LocationSelectionRow(
                        selection: suggestion,
                        distance: distance(to: suggestion),
                        isSelected: isSelected(suggestion)
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(isSelected(suggestion) ? Color.blue.opacity(0.08) : nil)
            }

            if nearbySuggestions.isEmpty && !isLoadingSuggestions && hasAttemptedNearbyLoad {
                ContentUnavailableView(
                    "transaction.location.noNearby".localized,
                    systemImage: "mappin.slash"
                )
                .frame(maxWidth: .infinity)
            }
        } header: {
            Text("transaction.location.suggestions".localized)
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        Section {
            if searchModel.isSearching {
                loadingRow("transaction.location.searching")
            }

            ForEach(searchModel.completions, id: \.self) { completion in
                Button {
                    isSearchFocused = false
                    Task { await selectCompletion(completion) }
                } label: {
                    SearchCompletionRow(completion: completion)
                }
                .buttonStyle(.plain)
            }

            if searchModel.completions.isEmpty && !searchModel.isSearching {
                ContentUnavailableView(
                    "transaction.location.noResults".localized,
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity)
            }
        } header: {
            Text("transaction.location.searchResults".localized)
        }
    }

    private func loadingRow(_ key: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(key.localized)
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bottom search bar (floating, iOS 26 Liquid Glass)

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .appFont(.body)
                .foregroundStyle(.secondary)

            TextField("transaction.location.searchPrompt".localized, text: $searchModel.query)
                .appFont(.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)

            if !searchModel.query.isEmpty {
                Button {
                    searchModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("transaction.location.clearSearch".localized)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func useCurrentLocation() async {
        if let currentLocationSelection {
            selectDraft(currentLocationSelection)
            return
        }

        isLoadingCurrentLocation = true
        defer { isLoadingCurrentLocation = false }

        do {
            let location = try await locationService.requestCurrentLocation()
            userLocation = location
            let selectedLocation = try await TransactionPlaceLookup.reverseGeocode(
                location: location,
                source: .currentLocation
            )
            currentLocationSelection = selectedLocation
            selectDraft(selectedLocation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadNearbySuggestionsIfNeeded() async {
        guard !hasAttemptedNearbyLoad else { return }
        hasAttemptedNearbyLoad = true
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        do {
            let location = try await locationService.requestCurrentLocation()
            userLocation = location
            let currentSelection = try? await TransactionPlaceLookup.reverseGeocode(
                location: location,
                source: .currentLocation
            )
            currentLocationSelection = currentSelection
            searchModel.updateRegion(centeredAt: location.coordinate)
            nearbySuggestions = try await TransactionPlaceLookup.nearbyPlaces(around: location.coordinate)
        } catch {
            nearbySuggestions = []
        }
    }

    private func selectCompletion(_ completion: MKLocalSearchCompletion) async {
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        do {
            let selectedLocation = try await searchModel.resolve(completion)
            selectDraft(selectedLocation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectDraft(_ selectedLocation: TransactionLocationSelection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            draftSelection = selectedLocation
        }
        searchModel.query = ""
        isSearchFocused = false
        HapticManager.shared.impact(style: .light)
        // Reveal the "Selected Location" section (with its map) so the change is visible
        // even when the user picked a row near the bottom of the list.
        scrollToSelectionToken += 1
    }

    /// How far a suggestion is from the device, or `nil` when the location is unknown
    /// (permission denied, or the fix hasn't landed yet).
    private func distance(to candidate: TransactionLocationSelection) -> CLLocationDistance? {
        userLocation?.distance(to: candidate.coordinate)
    }

    /// Whether a given selection is the one currently held in the draft (drives the row checkmark).
    private func isSelected(_ candidate: TransactionLocationSelection?) -> Bool {
        guard let candidate, let draftSelection else { return false }
        return draftSelection == candidate
    }
}

private struct TransactionManualMapPinView: View {
    @Environment(\.dismiss) private var dismiss

    let initialSelection: TransactionLocationSelection?
    let onUse: (TransactionLocationSelection) -> Void

    @State private var position: MapCameraPosition
    @State private var centerCoordinate: CLLocationCoordinate2D
    @State private var resolvedSelection: TransactionLocationSelection?
    /// Coordinate of an *explicitly chosen* place: the selection this sheet opened with,
    /// or a place label the user tapped on the map. While it is set, camera movement no
    /// longer re-resolves the name — that re-resolve is what used to rename a chosen
    /// "Dara Coffee" to the street it sits on the moment this sheet appeared.
    @State private var pinnedPlaceCoordinate: CLLocationCoordinate2D?
    @State private var mapSelection: MapSelection<String>?
    @State private var isResolvingLocation = false
    @State private var pendingResolveTask: Task<Void, Never>?
    /// Guards against a slow place lookup landing after the user has moved on.
    @State private var placeLookupToken = 0
    @State private var errorMessage: String?

    private let markerID = "selected-location"

    /// How far the map must move away from a chosen place before the pan counts as
    /// "I want a different spot" and the pin goes back to following the map centre.
    private static let pinBreakDistance: CLLocationDistance = 25

    init(
        initialSelection: TransactionLocationSelection?,
        onUse: @escaping (TransactionLocationSelection) -> Void
    ) {
        self.initialSelection = initialSelection
        self.onUse = onUse

        let initialLatitude = initialSelection?.latitude ?? 11.5564
        let initialLongitude = initialSelection?.longitude ?? 104.9282
        let initialCoordinate = CLLocationCoordinate2D(latitude: initialLatitude, longitude: initialLongitude)
        let region = MKCoordinateRegion(
            center: initialCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )

        _position = State(initialValue: .region(region))
        _centerCoordinate = State(initialValue: initialCoordinate)
        _resolvedSelection = State(initialValue: initialSelection)
        _pinnedPlaceCoordinate = State(initialValue: initialSelection.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position, selection: $mapSelection) {
                    Marker(markerTitle, systemImage: markerStyle.symbolName, coordinate: markerCoordinate)
                        .tint(markerStyle.tint)
                        // Must be tagged with the binding's own type: a bare `markerID`
                        // never matches a `MapSelection` selection, so tapping the pin
                        // would silently do nothing.
                        .tag(MapSelection(markerID))
                }
                // The bottom panel already names whatever is pinned; the system callout
                // would just cover the map with a second, competing place card.
                .mapFeatureSelectionAccessory(nil)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    handleCameraChange(center: context.region.center, isFinal: false)
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    handleCameraChange(center: context.region.center, isFinal: true)
                }
                .onChange(of: mapSelection) { _, newValue in
                    guard let newValue else { return }
                    if let feature = newValue.feature {
                        Task { await pin(feature) }
                    } else if newValue.value == markerID {
                        Task { await useSelectedCoordinate() }
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    if let resolvedSelection {
                        SelectedLocationRow(selection: resolvedSelection)
                    } else {
                        Text("transaction.location.moveMapToPin".localized)
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await useSelectedCoordinate() }
                    } label: {
                        Label {
                            Text(isResolvingLocation ? "transaction.location.resolvingPin".localized : "transaction.location.useSelected".localized)
                        } icon: {
                            if isResolvingLocation {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .appFont(.body, weight: .semibold)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResolvingLocation)
                }
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                .padding(16)
            }
            .navigationTitle("transaction.location.pinOnMap".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("common.cancel".localized)
                }
            }
            .alert("transaction.location.errorTitle".localized, isPresented: errorBinding) {
                Button("common.ok".localized, role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .onDisappear {
                pendingResolveTask?.cancel()
            }
        }
    }

    /// Where the pin sits: on the chosen place if there is one, otherwise wherever the
    /// user has dragged the map to.
    private var markerCoordinate: CLLocationCoordinate2D {
        pinnedPlaceCoordinate ?? centerCoordinate
    }

    private var markerTitle: String {
        resolvedSelection?.title ?? "transaction.location.selected".localized
    }

    private var markerStyle: PlaceCategoryStyle {
        guard pinnedPlaceCoordinate != nil, let resolvedSelection else { return .droppedPin }
        return PlaceCategoryStyle.style(forCategoryRawValue: resolvedSelection.pointOfInterestCategoryRaw)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// Single entry point for camera movement, so the "keep the chosen place" rule is
    /// applied identically to the continuous and settled callbacks.
    private func handleCameraChange(center: CLLocationCoordinate2D, isFinal: Bool) {
        if let pinnedPlaceCoordinate {
            guard pinnedPlaceCoordinate.distance(to: center) > Self.pinBreakDistance else {
                centerCoordinate = center
                return
            }
            // Panned away from the chosen place — go back to pinning the map centre.
            self.pinnedPlaceCoordinate = nil
            resolvedSelection = nil
            mapSelection = nil
        } else if centerCoordinate.distance(to: center) > 5 {
            resolvedSelection = nil
            mapSelection = nil
        }

        centerCoordinate = center

        if isFinal {
            scheduleResolveCenterCoordinate()
        }
    }

    /// Adopts a place label the user tapped on the map, keeping its name.
    private func pin(_ feature: MapFeature) async {
        pendingResolveTask?.cancel()

        let coordinate = feature.coordinate
        let title = feature.title

        placeLookupToken += 1
        let token = placeLookupToken

        // Show the tapped label straight away; the address fills in behind it.
        pinnedPlaceCoordinate = coordinate
        withAnimation(.easeInOut(duration: 0.2)) {
            resolvedSelection = TransactionLocationSelection(
                displayName: title,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                source: .mapTap,
                pointOfInterestCategoryRaw: feature.pointOfInterestCategory?.rawValue
            )
        }
        HapticManager.shared.impact(style: .light)

        let enriched: TransactionLocationSelection?
        if let title, !title.isEmpty {
            enriched = await TransactionPlaceLookup.place(named: title, near: coordinate, source: .mapTap)
        } else {
            // A territory or physical feature has no name to search for.
            enriched = try? await TransactionPlaceLookup.reverseGeocode(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                source: .mapTap
            )
        }

        // Only take the richer result if the user hasn't picked something else meanwhile,
        // and never let it drop the name the map showed.
        guard token == placeLookupToken, var enriched else { return }
        if enriched.displayName?.isEmpty ?? true {
            enriched.displayName = title
        }
        pinnedPlaceCoordinate = CLLocationCoordinate2D(latitude: enriched.latitude, longitude: enriched.longitude)
        resolvedSelection = enriched
    }

    private func useSelectedCoordinate() async {
        if let resolvedSelection {
            apply(resolvedSelection)
            return
        }

        guard let selectedLocation = await resolveCenterCoordinate(showProgress: true) else { return }
        apply(selectedLocation)
    }

    private func scheduleResolveCenterCoordinate() {
        pendingResolveTask?.cancel()
        let coordinate = centerCoordinate

        pendingResolveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await resolveCenterCoordinate(at: coordinate, showProgress: false)
        }
    }

    @discardableResult
    private func resolveCenterCoordinate(showProgress: Bool) async -> TransactionLocationSelection? {
        await resolveCenterCoordinate(at: centerCoordinate, showProgress: showProgress)
    }

    @discardableResult
    private func resolveCenterCoordinate(
        at coordinate: CLLocationCoordinate2D,
        showProgress: Bool
    ) async -> TransactionLocationSelection? {
        if showProgress {
            isResolvingLocation = true
        }
        defer {
            if showProgress {
                isResolvingLocation = false
            }
        }

        placeLookupToken += 1
        let token = placeLookupToken

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: kCLLocationAccuracyHundredMeters,
            verticalAccuracy: -1,
            timestamp: Date()
        )

        let selectedLocation: TransactionLocationSelection
        do {
            selectedLocation = try await TransactionPlaceLookup.reverseGeocode(
                location: location,
                source: .mapTap
            )
        } catch {
            selectedLocation = TransactionLocationSelection(
                displayName: "transaction.location.selected".localized,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                source: .mapTap
            )
        }

        // A tapped place label outranks a coordinate that was only reverse geocoded.
        guard token == placeLookupToken, pinnedPlaceCoordinate == nil else { return selectedLocation }
        resolvedSelection = selectedLocation
        return selectedLocation
    }

    private func apply(_ selectedLocation: TransactionLocationSelection) {
        onUse(selectedLocation)
        dismiss()
    }
}

private struct SelectedLocationMapPreview: View {
    let selection: TransactionLocationSelection

    @State private var position: MapCameraPosition

    init(selection: TransactionLocationSelection) {
        self.selection = selection
        _position = State(initialValue: .region(Self.region(for: selection)))
    }

    var body: some View {
        Map(position: $position) {
            Marker(selection.title, systemImage: style.symbolName, coordinate: selection.coordinate)
                .tint(style.tint)
        }
        .frame(height: 150)
        // The preview is a button; the map must not swallow the tap or pan under it.
        .allowsHitTesting(false)
        .overlay(alignment: .bottomTrailing) {
            Label("transaction.location.adjustOnMap".localized, systemImage: "hand.tap.fill")
                .appFont(.caption2, weight: .semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: Capsule())
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        // initialPosition only applies once; re-center whenever the selection moves.
        .onChange(of: selection.coordinateKey) { _, _ in
            withAnimation(.easeInOut) {
                position = .region(Self.region(for: selection))
            }
        }
    }

    private var style: PlaceCategoryStyle {
        PlaceCategoryStyle.style(forCategoryRawValue: selection.pointOfInterestCategoryRaw)
    }

    private static func region(for selection: TransactionLocationSelection) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: selection.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }
}

private struct LocationActionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var isLoading = false
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 32, height: 32)

                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.blue)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.body, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .appFont(.subheadline, weight: .bold)
                    .foregroundStyle(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct LocationSelectionRow: View {
    let selection: TransactionLocationSelection
    /// Distance from the device, when it is known.
    var distance: CLLocationDistance?
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            PlaceCategoryIcon(
                style: PlaceCategoryStyle.style(forCategoryRawValue: selection.pointOfInterestCategoryRaw),
                isProminent: isSelected
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .appFont(.body, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = selection.subtitle {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let formattedDistance {
                Text(formattedDistance)
                    .appFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .accessibilityLabel("transaction.location.distanceAway".localized(with: formattedDistance))
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .appFont(.subheadline, weight: .bold)
                    .foregroundStyle(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
    }

    private var formattedDistance: String? {
        distance.map(PlaceDistanceFormatterCache.string(for:))
    }
}

/// The circular category glyph shared by the picker's place rows — a café shows a cup,
/// a bank shows a column, an address falls back to a pin.
private struct PlaceCategoryIcon: View {
    let style: PlaceCategoryStyle
    var isProminent = false

    var body: some View {
        ZStack {
            Circle()
                .fill(style.tint.opacity(isProminent ? 0.22 : 0.12))
                .frame(width: 32, height: 32)

            Image(systemName: style.symbolName)
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(style.tint)
        }
        .frame(width: 32, height: 32)
    }
}

private struct SearchCompletionRow: View {
    let completion: MKLocalSearchCompletion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .appFont(.body)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(completion.title)
                    .appFont(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !completion.subtitle.isEmpty {
                    Text(completion.subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }
}

private struct SelectedLocationRow: View {
    let selection: TransactionLocationSelection
    /// Supplied by the picker, where clearing the choice lives on this row rather than
    /// in a separate destructive row below it. Omitted on the map sheet's panel.
    var onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            PlaceCategoryIcon(
                style: PlaceCategoryStyle.style(forCategoryRawValue: selection.pointOfInterestCategoryRaw),
                isProminent: true
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .appFont(.body, weight: .medium)

                if let subtitle = selection.subtitle {
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onClear {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("transaction.location.clear".localized)
            }
        }
    }
}

@Observable
@MainActor
private final class TransactionPlaceSearchModel {
    var query: String = "" {
        didSet {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            isSearching = !trimmedQuery.isEmpty
            completer.queryFragment = trimmedQuery
            if trimmedQuery.isEmpty {
                completions = []
                isSearching = false
            }
        }
    }

    var completions: [MKLocalSearchCompletion] = []
    var isSearching = false

    @ObservationIgnored private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 11.5564, longitude: 104.9282),
        span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
    )
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private let completerDelegate = PlaceSearchCompleterDelegate()

    init() {
        completerDelegate.model = self
        completer.delegate = completerDelegate
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = region
    }

    func updateRegion(centeredAt coordinate: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
        completer.region = region
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> TransactionLocationSelection {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = region

        let response = try await performSearch(request: request)
        guard let mapItem = response.mapItems.first else {
            throw LocationServiceError.noLocation
        }

        return TransactionPlaceLookup.selection(from: mapItem, source: .mapSearch, accuracy: nil)
    }

    private func performSearch(request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { continuation in
            let search = MKLocalSearch(request: request)
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: LocationServiceError.noLocation)
                }
            }
        }
    }
}

private final class PlaceSearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    weak var model: TransactionPlaceSearchModel?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak model] in
            model?.completions = results
            model?.isSearching = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak model] in
            model?.completions = []
            model?.isSearching = false
        }
    }
}

private extension CLLocationCoordinate2D {
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(
            from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }
}

private extension TransactionLocationSelection {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Stable identity for the coordinate, used to detect when the map should re-center.
    var coordinateKey: String {
        "\(latitude),\(longitude)"
    }
}

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
            SelectedLocationMapPreview(selection: selection)

            SelectedLocationRow(selection: selection)

            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    draftSelection = nil
                }
            } label: {
                Label("transaction.location.clear".localized, systemImage: "xmark.circle")
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
                    LocationSelectionRow(selection: suggestion, isSelected: isSelected(suggestion))
                }
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
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bottom search bar (floating, iOS 26 Liquid Glass)

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.app(.body))
                .foregroundStyle(.secondary)

            TextField("transaction.location.searchPrompt".localized, text: $searchModel.query)
                .font(.app(.body))
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
    @State private var selectedMarkerID: String?
    @State private var isResolvingLocation = false
    @State private var pendingResolveTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private let markerID = "selected-location"

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
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $position, selection: $selectedMarkerID) {
                    Marker(markerTitle, coordinate: centerCoordinate)
                        .tag(markerID)
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    if centerCoordinate.distance(to: context.region.center) > 5 {
                        resolvedSelection = nil
                        selectedMarkerID = nil
                    }
                    centerCoordinate = context.region.center
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    centerCoordinate = context.region.center
                    scheduleResolveCenterCoordinate()
                }
                .onChange(of: selectedMarkerID) { _, newValue in
                    guard newValue == markerID else { return }
                    Task { await useCenterCoordinate() }
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 10) {
                    if let resolvedSelection {
                        SelectedLocationRow(selection: resolvedSelection)
                    } else {
                        Text("transaction.location.moveMapToPin".localized)
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await useCenterCoordinate() }
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
                        .font(.app(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResolvingLocation)
                }
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
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

    private var markerTitle: String {
        resolvedSelection?.title ?? "transaction.location.selected".localized
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func useCenterCoordinate() async {
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

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: kCLLocationAccuracyHundredMeters,
            verticalAccuracy: -1,
            timestamp: Date()
        )

        do {
            let selectedLocation = try await TransactionPlaceLookup.reverseGeocode(
                location: location,
                source: .mapTap
            )
            resolvedSelection = selectedLocation
            return selectedLocation
        } catch {
            let selectedLocation = TransactionLocationSelection(
                displayName: "transaction.location.selected".localized,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                source: .mapTap
            )
            resolvedSelection = selectedLocation
            return selectedLocation
        }
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
            Marker(selection.title, coordinate: selection.coordinate)
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        // initialPosition only applies once; re-center whenever the selection moves.
        .onChange(of: selection.coordinateKey) { _, _ in
            withAnimation(.easeInOut) {
                position = .region(Self.region(for: selection))
            }
        }
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
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct LocationSelectionRow: View {
    let selection: TransactionLocationSelection
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "mappin.circle.fill" : "mappin.circle")
                .font(.app(.title3))
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.app(.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = selection.subtitle {
                    Text(subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SearchCompletionRow: View {
    let completion: MKLocalSearchCompletion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.app(.body))
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(completion.title)
                    .font(.app(.body))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !completion.subtitle.isEmpty {
                    Text(completion.subtitle)
                        .font(.app(.caption))
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

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.app(.body, weight: .medium))

                if let subtitle = selection.subtitle {
                    Text(subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.blue)
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

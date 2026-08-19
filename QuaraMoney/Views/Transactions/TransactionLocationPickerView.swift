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
    @State private var headerCamera: MapCameraPosition
    @State private var deviceCoordinate: CLLocationCoordinate2D?
    @FocusState private var isSearchFocused: Bool

    private static let selectedSectionID = "selectedLocationSection"
    private static let mapPreviewHeight: CGFloat = 230

    init(selection: Binding<TransactionLocationSelection?>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue)
        _headerCamera = State(initialValue: .region(Self.headerRegion(for: selection.wrappedValue)))
    }

    private var trimmedQuery: String {
        searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool { !trimmedQuery.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mapPreviewHeader

                ScrollViewReader { proxy in
                    List {
                        if isSearchActive {
                            searchResultsSection
                        } else {
                            selectedLocationSection
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
            .onChange(of: draftSelection?.coordinateKey) { _, _ in
                recenterHeaderCamera()
            }
            .onChange(of: currentLocationSelection?.coordinateKey) { _, _ in
                // Only follow the device location while nothing is picked yet.
                guard draftSelection == nil else { return }
                recenterHeaderCamera()
            }
        }
    }

    // MARK: - Map preview header

    private var mapPreviewHeader: some View {
        Map(position: $headerCamera, interactionModes: []) {
            if let draftSelection {
                Marker(draftSelection.title, coordinate: draftSelection.coordinate)
                    .tint(.blue)
            }

            UserAnnotation()
        }
        .frame(height: Self.mapPreviewHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = false
            showManualMapPicker = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("transaction.location.pinOnMap".localized)
        .overlay(alignment: .topTrailing) { mapPreviewActions }
        .overlay(alignment: .bottomLeading) { mapPreviewHint }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var mapPreviewActions: some View {
        VStack(spacing: 10) {
            Button {
                Task { await useCurrentLocation() }
            } label: {
                mapActionIcon("location.fill", isLoading: isLoadingCurrentLocation)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(isLoadingCurrentLocation)
            .accessibilityLabel("transaction.location.useCurrent".localized)

            Button {
                isSearchFocused = false
                showManualMapPicker = true
            } label: {
                mapActionIcon("mappin.and.ellipse")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("transaction.location.pinOnMap".localized)
        }
        .padding(12)
    }

    private func mapActionIcon(_ systemImage: String, isLoading: Bool = false) -> some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 24, height: 24)
    }

    @ViewBuilder
    private var mapPreviewHint: some View {
        if draftSelection == nil {
            Text("transaction.location.tapMapTitle".localized)
                .appFont(.caption, weight: .medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: Capsule())
                .padding(12)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Sections

    private var selectedLocationSection: some View {
        Section {
            if let draftSelection {
                SelectedLocationRow(selection: draftSelection)

                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.draftSelection = nil
                    }
                } label: {
                    Label("transaction.location.clear".localized, systemImage: "xmark.circle")
                }
            } else {
                EmptySelectionRow()
            }
        } header: {
            Text("transaction.location.selected".localized)
        }
        .id(Self.selectedSectionID)
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
            deviceCoordinate = location.coordinate
            if draftSelection == nil {
                recenterHeaderCamera()
            }
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
        // Reveal the "Selected Location" section so the change is visible even when the
        // user picked a row near the bottom of the list (the map header recenters too).
        scrollToSelectionToken += 1
    }

    /// Whether a given selection is the one currently held in the draft (drives the row checkmark).
    private func isSelected(_ candidate: TransactionLocationSelection?) -> Bool {
        guard let candidate, let draftSelection else { return false }
        return draftSelection == candidate
    }

    // MARK: - Header camera

    /// Keeps the always-visible preview centred on the draft pin, falling back to the
    /// device location (when known) and finally to a wide default region.
    private func recenterHeaderCamera() {
        let coordinate = draftSelection?.coordinate
            ?? currentLocationSelection?.coordinate
            ?? deviceCoordinate
        withAnimation(.easeInOut) {
            headerCamera = .region(Self.headerRegion(centeredAt: coordinate))
        }
    }

    private static func headerRegion(for selection: TransactionLocationSelection?) -> MKCoordinateRegion {
        headerRegion(centeredAt: selection.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        })
    }

    private static func headerRegion(centeredAt coordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        guard let coordinate else { return defaultRegion }
        return MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 11.5564, longitude: 104.9282),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )
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
                            .appFont(.subheadline)
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
                        .appFont(.body, weight: .semibold)
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

/// Placeholder shown in the "Selected Location" section before the user picks anything,
/// so the section (and the map above it) stays in place from the moment the sheet opens.
private struct EmptySelectionRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .appFont(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("transaction.location.noneSelected".localized)
                    .appFont(.body, weight: .medium)

                Text("transaction.location.noneSelectedHint".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LocationSelectionRow: View {
    let selection: TransactionLocationSelection
    var isSelected = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "mappin.circle.fill" : "mappin.circle")
                .appFont(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

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

    var body: some View {
        Label {
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

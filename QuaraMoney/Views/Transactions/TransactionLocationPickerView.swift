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
    @FocusState private var isSearchFocused: Bool

    init(selection: Binding<TransactionLocationSelection?>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField

                    if !searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResults
                    }
                }

                if let draftSelection {
                    Section {
                        SelectedLocationRow(selection: draftSelection)
                        SelectedLocationMapPreview(selection: draftSelection)

                        Button(role: .destructive) {
                            self.draftSelection = nil
                        } label: {
                            Label("transaction.location.clear".localized, systemImage: "xmark.circle")
                        }
                    } header: {
                        Text("transaction.location.selected".localized)
                    }
                }

                Section {
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        LocationActionRow(
                            title: "transaction.location.useCurrent".localized,
                            subtitle: currentLocationSelection?.subtitle ?? "transaction.location.useCurrentSubtitle".localized,
                            systemImage: "location.fill",
                            isLoading: isLoadingCurrentLocation
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

                if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        if isLoadingSuggestions {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("transaction.location.loadingNearby".localized)
                                    .font(.app(.subheadline))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(Array(nearbySuggestions.enumerated()), id: \.offset) { _, suggestion in
                            Button {
                                selectDraft(suggestion)
                            } label: {
                                LocationSelectionRow(selection: suggestion)
                            }
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
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("transaction.location.pick".localized)
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

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        selection = draftSelection
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("common.save".localized)
                }
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("transaction.location.searchPrompt".localized, text: $searchModel.query)
                .font(.app(.body))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFocused)

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
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var searchResults: some View {
        if searchModel.isSearching {
            HStack(spacing: 10) {
                ProgressView()
                Text("transaction.location.searching".localized)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
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
            let selectedLocation = try await TransactionPlaceSearchModel.reverseGeocode(
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
            let currentSelection = try? await TransactionPlaceSearchModel.reverseGeocode(
                location: location,
                source: .currentLocation
            )
            currentLocationSelection = currentSelection
            searchModel.updateRegion(centeredAt: location.coordinate)
            nearbySuggestions = try await searchModel.nearbySelections(around: location.coordinate)
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
        draftSelection = selectedLocation
        searchModel.query = ""
        isSearchFocused = false
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
            let selectedLocation = try await TransactionPlaceSearchModel.reverseGeocode(
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

    var body: some View {
        Map(
            initialPosition: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: selection.latitude, longitude: selection.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        ) {
            Marker(selection.title, coordinate: CLLocationCoordinate2D(latitude: selection.latitude, longitude: selection.longitude))
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }
}

private struct LocationActionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var isLoading = false

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
                    .font(.app(.body))
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
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

private struct LocationSelectionRow: View {
    let selection: TransactionLocationSelection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle")
                .font(.app(.title3))
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.app(.body))
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

        return Self.selection(from: mapItem, source: .mapSearch, accuracy: nil)
    }

    func nearbySelections(around coordinate: CLLocationCoordinate2D) async throws -> [TransactionLocationSelection] {
        updateRegion(centeredAt: coordinate)

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "point of interest"
        request.resultTypes = [.pointOfInterest]
        request.region = region

        let response = try await performSearch(request: request)
        return Array(response.mapItems.prefix(8)).map {
            Self.selection(from: $0, source: .mapSearch, accuracy: nil)
        }
    }

    static func reverseGeocode(
        location: CLLocation,
        source: TransactionLocationSource
    ) async throws -> TransactionLocationSelection {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw LocationServiceError.noLocation
        }

        let mapItems = try await request.mapItems
        guard let mapItem = mapItems.first else {
            throw LocationServiceError.noLocation
        }

        return selection(from: mapItem, source: source, accuracy: location.horizontalAccuracy)
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

    private static func selection(
        from mapItem: MKMapItem,
        source: TransactionLocationSource,
        accuracy: CLLocationAccuracy?
    ) -> TransactionLocationSelection {
        let placemark = mapItem.placemark
        let coordinate = placemark.coordinate
        let fullAddress = placemark.title
        let shortAddress = [placemark.thoroughfare, placemark.locality]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")

        var applePlaceID: String?
        var alternatePlaceIDs: [String] = []
        if #available(iOS 18.0, *) {
            applePlaceID = mapItem.identifier?.rawValue
            alternatePlaceIDs = mapItem.alternateIdentifiers.map(\.rawValue)
        }

        return TransactionLocationSelection(
            displayName: mapItem.name ?? fullAddress,
            fullAddress: fullAddress,
            shortAddress: shortAddress.isEmpty ? nil : shortAddress,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            horizontalAccuracyMeters: accuracy,
            source: source,
            applePlaceID: applePlaceID,
            alternateApplePlaceIDs: alternatePlaceIDs,
            pointOfInterestCategoryRaw: mapItem.pointOfInterestCategory?.rawValue,
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            countryCode: placemark.countryCode
        )
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

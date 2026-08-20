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
                        locationSection
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
                TransactionManualMapPinView(
                    pinnedSelection: draftSelection,
                    fallbackCoordinate: currentLocationSelection?.coordinate ?? userLocation?.coordinate
                ) { selectedLocation in
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

    /// The map is permanent: it frames the chosen place, or just the area the user is in
    /// when nothing is picked yet, and carries both ways of choosing a place on top of it.
    private var locationSection: some View {
        Section {
            LocationMapPreview(
                selection: draftSelection,
                fallbackCoordinate: userLocation?.coordinate,
                isLoadingCurrentLocation: isLoadingCurrentLocation,
                isCurrentLocationSelected: isSelected(currentLocationSelection),
                onUseCurrentLocation: { Task { await useCurrentLocation() } },
                onOpenMap: { showManualMapPicker = true }
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            if let draftSelection {
                SelectedLocationRow(selection: draftSelection) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.draftSelection = nil
                    }
                }
            } else {
                emptySelectionRow
            }
        } header: {
            Text("transaction.location".localized)
        }
        .id(Self.selectedSectionID)
    }

    private var emptySelectionRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("transaction.location.noneSelected".localized)
                .appFont(.body, weight: .medium)
                .foregroundStyle(.secondary)

            Text("transaction.location.noneSelectedHint".localized)
                .appFont(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            ForEach(Array(searchModel.results.enumerated()), id: \.offset) { _, result in
                Button {
                    isSearchFocused = false
                    selectDraft(result)
                } label: {
                    LocationSelectionRow(
                        selection: result,
                        distance: distance(to: result),
                        isSelected: isSelected(result)
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(isSelected(result) ? Color.blue.opacity(0.08) : nil)
            }

            if searchModel.results.isEmpty && !searchModel.isSearching {
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

/// Everything about the pin sheet that changes *after* a pin has landed: the card's place,
/// and whether a lookup is running.
///
/// Kept out of the map view's `@State` so the address arriving redraws the card alone
/// rather than the whole sheet — every redraw of the map costs MapKit a fresh pass over
/// its annotations.
@Observable
@MainActor
private final class PinSheetModel {
    var resolvedSelection: TransactionLocationSelection?
    var isResolvingLocation = false

    /// Guards against a slow place lookup landing after the user has moved on. Never
    /// observed — bumping it must not redraw anything.
    @ObservationIgnored var placeLookupToken = 0
}

/// Scratch state for the drop gesture, held in a plain reference for the same reason:
/// the finger's position changes on every touch event and must never redraw the map.
private final class PinTouchTracker {
    var location: CGPoint?
}

private struct TransactionManualMapPinView: View {
    @Environment(\.dismiss) private var dismiss

    /// The place the picker already holds, if any. The sheet opens on it — pin, card and
    /// camera — so adjusting a choice starts from that choice.
    let pinnedSelection: TransactionLocationSelection?
    let onUse: (TransactionLocationSelection) -> Void

    @State private var position: MapCameraPosition
    /// Our own pin, or `nil` for the states that must not show one: the sheet opened with
    /// nothing chosen, and a tapped map label that carries its own icon — MapKit enlarges
    /// that icon itself, and a pin of ours on top is the doubled-up marker.
    @State private var pin: DroppedPin?
    @State private var mapSelection: MapSelection<String>?
    @State private var model = PinSheetModel()
    @State private var touch = PinTouchTracker()
    /// How much room the card takes at the bottom, fed back to the map so MapKit can keep
    /// its attribution above it. Changes only when the card gains or loses the confirm
    /// button, not as the address fills in.
    @State private var cardHeight: CGFloat = 0

    /// Long enough that panning the map never leaves a pin behind, short enough that the
    /// pin still feels like it lands under the finger.
    private static let dropPinDelay: TimeInterval = 0.4

    /// Opens on the pinned place when there is one, and otherwise on a clean map centred
    /// on `fallbackCoordinate` — the map only frames the area, nothing is marked, the way
    /// Maps opens.
    init(
        pinnedSelection: TransactionLocationSelection?,
        fallbackCoordinate: CLLocationCoordinate2D?,
        onUse: @escaping (TransactionLocationSelection) -> Void
    ) {
        self.pinnedSelection = pinnedSelection
        self.onUse = onUse

        let center = pinnedSelection?.coordinate
            ?? fallbackCoordinate
            ?? TransactionLocationMapDefaults.coordinate
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )

        _position = State(initialValue: .region(region))
        _pin = State(initialValue: pinnedSelection.map(DroppedPin.init(restoring:)))
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                map
                    // Both must be simultaneous: a plain `.gesture` here claims the
                    // touch and the map stops panning altogether.
                    .simultaneousGesture(touchTrackingGesture)
                    .simultaneousGesture(dropPinGesture(using: proxy))
                    // An overlay rather than a `ZStack`, so the card growing by a line
                    // never re-proposes a size to the map underneath it.
                    .overlay(alignment: .bottom) {
                        PinSheetPanel(model: model, onUse: apply)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                cardHeight = $0
                            }
                    }
                    // After the overlay, so the card is bottom-aligned in the full-bleed
                    // frame and its own 16pt padding is measured from the screen's edge.
                    // Above the overlay it sat on the sheet's 39pt bottom inset instead,
                    // floating 55pt clear of an edge it is 16pt clear of at the sides.
                    .ignoresSafeArea(edges: .bottom)
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
            // The card names the pin the sheet opened on, so "Use this location" is live
            // straight away for someone who only came here to look. Seeded here rather
            // than in `init` because the card's model is `@MainActor`.
            .onAppear {
                guard model.resolvedSelection == nil else { return }
                model.resolvedSelection = pinnedSelection
            }
        }
    }

    private var map: some View {
        Map(position: $position, selection: $mapSelection) {
            if let pin {
                // Drawn by us rather than as a `Marker`: a marker only reaches Maps' full
                // dropped-pin size while it is *selected*, and MapKit clears that selection
                // every time this sheet redraws — the card filling in with the address was
                // enough to make the pin shrink and bounce back a second after it landed.
                Annotation(
                    pin.title,
                    coordinate: pin.coordinate,
                    anchor: PlacePinMetrics.coordinateAnchor
                ) {
                    PlacePinMarker(style: pin.style, animatesEntry: pin.animatesEntry)
                        // Identity is the spot itself: the marker is rebuilt — and so
                        // replays its entry — only when the pin actually moves, never
                        // when the card behind it fills in with an address.
                        .id(pin.coordinateKey)
                }
            }

            UserAnnotation()
        }
        // MapKit anchors the Apple logo and the Legal link to the map's own safe area, and
        // the card floats outside it — so grow that safe area by the card's height and the
        // attribution rides above the card instead of behind it. It has to stay visible.
        //
        // `safeAreaPadding` rather than `safeAreaInset`: the map must keep filling the sheet,
        // and an inset would lay a spacer out beneath it instead. Applied here, inside the
        // map, because the `.ignoresSafeArea` further out zeroes this edge before it — an
        // inset added outside that is one MapKit never sees.
        .safeAreaPadding(.bottom, cardHeight)
        // The bottom card already names whatever is pinned; the system callout
        // would just cover the map with a second, competing place card.
        .mapFeatureSelectionAccessory(nil)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .onChange(of: mapSelection) { _, newValue in
            guard let feature = newValue?.feature else { return }
            Task { await adopt(feature) }
        }
    }

    // MARK: - Dropping a pin

    /// Records the finger's position without consuming the touch, so the map keeps panning
    /// and zooming as it always did. `LongPressGesture` never reports where it happened,
    /// which is the only reason this exists.
    private var touchTrackingGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { touch.location = $0.location }
            .onEnded { _ in touch.location = nil }
    }

    /// Maps' own way of marking a spot: hold a finger still on the map and a pin drops
    /// there. Moving the finger cancels the press — that movement is a pan — so scrolling
    /// the map never leaves a pin behind.
    private func dropPinGesture(using proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: Self.dropPinDelay)
            .onEnded { _ in
                guard let point = touch.location,
                      let coordinate = proxy.convert(point, from: .local) else { return }
                dropPin(at: coordinate)
            }
    }

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        // Anything still in flight — a tapped label's lookup, an earlier pin's geocode —
        // must not land on top of the pin the user just dropped.
        model.placeLookupToken += 1

        HapticManager.shared.impact(style: .medium)

        pin = DroppedPin(
            coordinate: coordinate,
            title: "transaction.location.droppedPin".localized,
            style: .droppedPin
        )
        model.resolvedSelection = droppedPinSelection(at: coordinate)

        Task { await resolve(coordinate) }
    }

    /// The pin's stand-in place while the address is still being looked up.
    private func droppedPinSelection(at coordinate: CLLocationCoordinate2D) -> TransactionLocationSelection {
        TransactionLocationSelection(
            displayName: "transaction.location.droppedPin".localized,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: .mapTap
        )
    }

    // MARK: - Tapping a place label

    /// Adopts a place label the user tapped on the map, keeping its name.
    ///
    /// A label that carries its own icon needs no pin from us — MapKit enlarges that icon
    /// while it is selected. A label the map draws as bare text (a park, a street, a
    /// neighbourhood) has nothing to enlarge, so it gets the same pin a touch-and-hold
    /// drops, selected so it too comes up at full size.
    private func adopt(_ feature: MapFeature) async {
        let coordinate = feature.coordinate
        let title = feature.title
        let category = feature.pointOfInterestCategory

        model.placeLookupToken += 1
        let token = model.placeLookupToken

        // Show the tapped label straight away; the address fills in behind it.
        model.resolvedSelection = TransactionLocationSelection(
            displayName: title,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            source: .mapTap,
            pointOfInterestCategoryRaw: category?.rawValue
        )

        if feature.image == nil {
            pin = DroppedPin(
                coordinate: coordinate,
                title: title ?? "transaction.location.droppedPin".localized,
                style: PlaceCategoryStyle.style(for: category)
            )
        } else {
            pin = nil
        }

        HapticManager.shared.impact(style: .light)

        let enriched: TransactionLocationSelection?
        // A matched place brings its own anchor and should keep it — a shop's real door beats
        // wherever the finger landed on its label. A reverse geocode brings no such thing.
        let isReverseGeocoded: Bool

        if let title, !title.isEmpty {
            enriched = await TransactionPlaceLookup.place(named: title, near: coordinate, source: .mapTap)
            isReverseGeocoded = false
        } else {
            // A territory or physical feature has no name to search for.
            enriched = try? await TransactionPlaceLookup.reverseGeocode(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                source: .mapTap
            )
            isReverseGeocoded = true
        }

        // Only take the richer result if the user hasn't picked something else meanwhile,
        // and never let it drop the name the map showed.
        guard token == model.placeLookupToken, var enriched else { return }
        if enriched.displayName?.isEmpty ?? true {
            enriched.displayName = title
        }
        if isReverseGeocoded {
            enriched = enriched.anchored(at: coordinate)
        }
        model.resolvedSelection = enriched
    }

    // MARK: - Naming a coordinate

    private func resolve(_ coordinate: CLLocationCoordinate2D) async {
        model.isResolvingLocation = true
        defer { model.isResolvingLocation = false }

        model.placeLookupToken += 1
        let token = model.placeLookupToken

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: kCLLocationAccuracyHundredMeters,
            verticalAccuracy: -1,
            timestamp: Date()
        )

        guard let named = try? await TransactionPlaceLookup.reverseGeocode(location: location, source: .mapTap) else {
            // Nothing to name it with — the pin keeps its coordinates and the placeholder title.
            return
        }

        // A newer pin (or a tapped label) already owns the card.
        guard token == model.placeLookupToken else { return }
        // Its name, never its coordinate — see `anchored(at:)`.
        model.resolvedSelection = named.anchored(at: coordinate)
    }

    private func apply(_ selectedLocation: TransactionLocationSelection) {
        onUse(selectedLocation)
        dismiss()
    }
}

/// The card under the map: what is pinned, and the button that takes it.
///
/// Built as Maps' own place card. The place's name carries the card at title weight with
/// its address beneath, and a single prominent action sits below that — no leading icon,
/// because the pin directly above already shows the category glyph in its colour and a
/// second copy here is the doubled-up marker.
///
/// Glass rather than a material: this floats over a live map, which is exactly the
/// controls layer Liquid Glass belongs to and gives it real content to refract.
///
/// Separate from the map's view so the lookup can refresh it without the map noticing.
private struct PinSheetPanel: View {
    let model: PinSheetModel
    let onUse: (TransactionLocationSelection) -> Void

    /// Concentric with the display, uniformly.
    ///
    /// The card is inset 16pt from the screen on the left, the right *and* the bottom, so
    /// its two bottom corners share a centre of curvature with the display's own and resolve
    /// against it — no radius to pick, and it tracks whatever hardware it lands on. The top
    /// corners have no such partner, sitting some 700pt down inside the display's inner
    /// region, and plain `ConcentricRectangle()` renders them square for exactly that reason.
    ///
    /// `isUniform: true` is what carries the bottom corners' resolved radius up to the top
    /// two, so the card reads as one shape. It is deliberate here, not a default: the whole
    /// card is meant to echo the screen's corner, not just the half of it that can prove a
    /// shared centre.
    private static let shape = ConcentricRectangle(corners: .concentric, isUniform: true)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let selection = model.resolvedSelection {
                placeHeader(selection)
                confirmButton(selection)
            } else {
                hint
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        // Glass goes on after layout, and the clip after the glass — without it the glass
        // layer renders proud of the content and leaves a pale halo around the card.
        .glassEffect(.regular, in: Self.shape)
        .clipShape(Self.shape)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .animation(.smooth(duration: 0.28), value: model.resolvedSelection)
        .animation(.smooth(duration: 0.28), value: model.isResolvingLocation)
    }

    /// Name over address, the way Maps titles a place. While the lookup is still running the
    /// address line carries the progress instead, so the button below never changes shape.
    private func placeHeader(_ selection: TransactionLocationSelection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(selection.title)
                .appFont(.title3, weight: .semibold)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if model.isResolvingLocation {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)

                    Text("transaction.location.resolvingPin".localized)
                        .appFont(.subheadline)
                }
                .foregroundStyle(.secondary)
            } else if let detail = detail(for: selection) {
                Text(detail)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The address line, with the name trimmed off the front when the address merely repeats
    /// it. Reverse-geocoding a street gives "Street 19" as the name and "Street 19, Phnom
    /// Penh" as the address; Maps prints the street once and the city under it, never both
    /// in full. Returns `nil` when nothing is left to say.
    private func detail(for selection: TransactionLocationSelection) -> String? {
        guard let subtitle = selection.subtitle else { return nil }
        guard subtitle.hasPrefix(selection.title) else { return subtitle }

        let remainder = subtitle
            .dropFirst(selection.title.count)
            .trimmingCharacters(in: Self.addressSeparators)
        return remainder.isEmpty ? nil : remainder
    }

    /// What sits between an address's parts once the name in front of it is gone.
    private static let addressSeparators = CharacterSet(charactersIn: " ,·-–—").union(.whitespacesAndNewlines)

    private func confirmButton(_ selection: TransactionLocationSelection) -> some View {
        Button {
            onUse(selection)
        } label: {
            Text("transaction.location.useSelected".localized)
                .appFont(.body, weight: .semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(model.isResolvingLocation)
    }

    /// Nothing pinned yet, so there is nothing to confirm — the card is only the
    /// instruction, and grows the button in when a pin lands.
    private var hint: some View {
        Text("transaction.location.holdToDropPin".localized)
            .appFont(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Maps' own measurements for a place it has marked, read off a selected place label in
/// the simulator (iOS 26.2): a 60pt tinted circle inside a 4pt white ring, a white teardrop
/// tail falling 7pt past it, and a small dot sitting on the coordinate itself.
private enum PlacePinMetrics {
    static let circle: CGFloat = 60
    static let ring: CGFloat = 4
    /// How far the tail's tip falls below the ring.
    static let tailDrop: CGFloat = 7
    /// Clear air between the tail's tip and the dot.
    static let dotGap: CGFloat = 3
    static let dotCore: CGFloat = 6
    static let dotRing: CGFloat = 1.5
    static let glyph: CGFloat = 28

    static let balloon = circle + ring * 2
    static let dot = dotCore + dotRing * 2
    static let height = balloon + tailDrop + dotGap + dot

    /// The part of the marker that belongs on the coordinate is the dot at its foot — the
    /// balloon floats above the place, the way Maps' does.
    static let coordinateAnchor = UnitPoint(x: 0.5, y: (height - dot / 2) / height)
}

/// The white backing of a place pin: the circle and its teardrop tail as a single shape, so
/// the tail flares out of the circle instead of meeting it at a corner.
private struct PlacePinBalloon: Shape {
    let tailDrop: CGFloat

    /// How far round from the bottom of the circle the tail parts from it, and how far the
    /// sides are pulled in on the way to the tip. Both measured off Maps' pin.
    private static let junction = Angle.degrees(27)
    private static let shoulderInset: CGFloat = 0.13
    private static let shoulderDrop: CGFloat = 0.97

    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let circle = Path(ellipseIn: CGRect(
            origin: rect.origin,
            size: CGSize(width: rect.width, height: rect.width)
        ))

        let dx = radius * sin(Self.junction.radians)
        let dy = radius * cos(Self.junction.radians)
        let left = CGPoint(x: center.x - dx, y: center.y + dy)
        let right = CGPoint(x: center.x + dx, y: center.y + dy)
        let tip = CGPoint(x: center.x, y: center.y + radius + tailDrop)
        let shoulderY = center.y + radius * Self.shoulderDrop
        let shoulderX = radius * Self.shoulderInset

        var tail = Path()
        tail.move(to: left)
        tail.addQuadCurve(to: tip, control: CGPoint(x: center.x - shoulderX, y: shoulderY))
        tail.addQuadCurve(to: right, control: CGPoint(x: center.x + shoulderX, y: shoulderY))
        // Closes across the circle's own interior, where the union swallows the seam.
        tail.closeSubpath()

        return circle.union(tail)
    }
}

/// The one marker this sheet uses for a chosen spot, built to Maps' own measurements so it
/// is indistinguishable from the pin MapKit puts on a place label the user taps.
///
/// Holding to drop a pin, tapping a label the map draws as bare text, and re-opening the
/// sheet on an earlier choice all end in this same mark — no way of choosing a place looks
/// like a different kind of place from the others.
private struct PlacePinMarker: View {
    let style: PlaceCategoryStyle
    /// A mark the user has just made grows into place; one restored along with the sheet
    /// was already there and simply appears.
    let animatesEntry: Bool

    @State private var isPlaced: Bool

    init(style: PlaceCategoryStyle, animatesEntry: Bool) {
        self.style = style
        self.animatesEntry = animatesEntry
        _isPlaced = State(initialValue: !animatesEntry)
    }

    var body: some View {
        VStack(spacing: PlacePinMetrics.dotGap) {
            balloon
            dot
        }
        .frame(width: PlacePinMetrics.balloon, height: PlacePinMetrics.height)
        // Grows out of the coordinate it marks, not out of thin air.
        .scaleEffect(isPlaced ? 1 : 0.3, anchor: .bottom)
        .opacity(isPlaced ? 1 : 0)
        .onAppear {
            guard !isPlaced else { return }
            // One-shot: the mark grows in once. Never a repeating animation — those leak
            // onto every later change of this view.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) {
                isPlaced = true
            }
        }
    }

    private var balloon: some View {
        ZStack(alignment: .top) {
            PlacePinBalloon(tailDrop: PlacePinMetrics.tailDrop)
                .fill(.white)

            Circle()
                // Maps shades its pins top-to-bottom rather than filling them flat.
                .fill(style.tint.gradient)
                .frame(width: PlacePinMetrics.circle, height: PlacePinMetrics.circle)
                .overlay {
                    Image(systemName: style.symbolName)
                        .appFont(size: PlacePinMetrics.glyph, weight: .semibold)
                        .foregroundStyle(.white)
                }
                .padding(.top, PlacePinMetrics.ring)
        }
        .frame(
            width: PlacePinMetrics.balloon,
            height: PlacePinMetrics.balloon + PlacePinMetrics.tailDrop
        )
        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    }

    /// The coordinate itself, marked under the balloon exactly as Maps marks it.
    private var dot: some View {
        Circle()
            .fill(style.tint)
            .frame(width: PlacePinMetrics.dotCore, height: PlacePinMetrics.dotCore)
            .padding(PlacePinMetrics.dotRing)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

/// A pin of our own, frozen at the moment it is placed.
///
/// Nothing here changes while the address is being looked up: re-titling or re-styling the
/// annotation would rebuild it on the map, replaying its entry. The lookup updates the card
/// and nothing else.
private struct DroppedPin: Equatable {
    let latitude: Double
    let longitude: Double
    let title: String
    let style: PlaceCategoryStyle
    /// `false` for a pin restored along with the sheet: it was placed on an earlier visit,
    /// so re-opening the sheet must not replay it landing.
    let animatesEntry: Bool

    init(
        coordinate: CLLocationCoordinate2D,
        title: String,
        style: PlaceCategoryStyle,
        animatesEntry: Bool = true
    ) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.title = title
        self.style = style
        self.animatesEntry = animatesEntry
    }

    /// Rebuilt from the place the picker already holds, so "Adjust" opens on that place
    /// instead of an empty map.
    init(restoring selection: TransactionLocationSelection) {
        self.init(
            coordinate: selection.coordinate,
            title: selection.title,
            style: PlaceCategoryStyle.style(forCategoryRawValue: selection.pointOfInterestCategoryRaw),
            animatesEntry: false
        )
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Stable identity for the spot the pin marks.
    var coordinateKey: String {
        "\(latitude),\(longitude)"
    }
}

/// Fallback map centre for a device that has not given up a location yet (Phnom Penh).
private enum TransactionLocationMapDefaults {
    static let coordinate = CLLocationCoordinate2D(latitude: 11.5564, longitude: 104.9282)
}

/// The picker's permanent map header. With a selection it frames the chosen place; without
/// one it simply shows the area the user is in, so the map is never a blank slot. Both ways
/// of choosing a place — the device location and the full-screen pin sheet — ride on top of
/// it, and tapping the map itself opens that sheet.
private struct LocationMapPreview: View {
    let selection: TransactionLocationSelection?
    /// Device location, used to frame the map before anything has been chosen.
    let fallbackCoordinate: CLLocationCoordinate2D?
    let isLoadingCurrentLocation: Bool
    let isCurrentLocationSelected: Bool
    let onUseCurrentLocation: () -> Void
    let onOpenMap: () -> Void

    @State private var position: MapCameraPosition

    init(
        selection: TransactionLocationSelection?,
        fallbackCoordinate: CLLocationCoordinate2D?,
        isLoadingCurrentLocation: Bool,
        isCurrentLocationSelected: Bool,
        onUseCurrentLocation: @escaping () -> Void,
        onOpenMap: @escaping () -> Void
    ) {
        self.selection = selection
        self.fallbackCoordinate = fallbackCoordinate
        self.isLoadingCurrentLocation = isLoadingCurrentLocation
        self.isCurrentLocationSelected = isCurrentLocationSelected
        self.onUseCurrentLocation = onUseCurrentLocation
        self.onOpenMap = onOpenMap
        _position = State(initialValue: .region(Self.region(for: selection, fallback: fallbackCoordinate)))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                if let selection {
                    Marker(selection.title, systemImage: style.symbolName, coordinate: selection.coordinate)
                        .tint(style.tint)
                }
                UserAnnotation()
            }
            // The preview is a shortcut into the full map sheet, not a map to drive: panning
            // it here would fight the List's scrolling and steal the buttons' taps.
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenMap)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(mapActionTitle)

            HStack(spacing: 8) {
                MapOverlayButton(
                    title: "transaction.location.currentShort".localized,
                    accessibilityTitle: "transaction.location.useCurrent".localized,
                    systemImage: "location.fill",
                    isLoading: isLoadingCurrentLocation,
                    isProminent: isCurrentLocationSelected,
                    action: onUseCurrentLocation
                )
                .disabled(isLoadingCurrentLocation)

                Spacer(minLength: 8)

                MapOverlayButton(
                    title: mapActionTitle,
                    accessibilityTitle: mapActionTitle,
                    systemImage: "mappin.and.ellipse",
                    action: onOpenMap
                )
            }
            .padding(10)
        }
        .frame(height: 176)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        // The camera is set once at init; re-frame it whenever the pin — or the first
        // device location fix — moves.
        .onChange(of: cameraKey) { _, _ in
            withAnimation(.easeInOut) {
                position = .region(Self.region(for: selection, fallback: fallbackCoordinate))
            }
        }
    }

    private var mapActionTitle: String {
        selection == nil
            ? "transaction.location.pinShort".localized
            : "transaction.location.adjustShort".localized
    }

    private var style: PlaceCategoryStyle {
        PlaceCategoryStyle.style(forCategoryRawValue: selection?.pointOfInterestCategoryRaw)
    }

    /// Stable identity for whatever the camera is currently framing.
    private var cameraKey: String {
        if let selection {
            return selection.coordinateKey
        }
        guard let fallbackCoordinate else { return "none" }
        return "\(fallbackCoordinate.latitude),\(fallbackCoordinate.longitude)"
    }

    private static func region(
        for selection: TransactionLocationSelection?,
        fallback: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion {
        if let selection {
            return MKCoordinateRegion(
                center: selection.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        // Nothing chosen yet: show the neighbourhood rather than pretending to a precision
        // the picker does not have.
        return MKCoordinateRegion(
            center: fallback ?? TransactionLocationMapDefaults.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    }
}

/// A compact glass control sitting on the map preview.
private struct MapOverlayButton: View {
    let title: String
    let accessibilityTitle: String
    let systemImage: String
    var isLoading = false
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Group {
            if isProminent {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.glass)
            }
        }
        .controlSize(.small)
        .accessibilityLabel(accessibilityTitle)
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: systemImage)
                }

                Text(title)
                    .lineLimit(1)
            }
            .appFont(.caption, weight: .semibold)
        }
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
                style: PlaceCategoryStyle.style(forCategoryRawValue: selection.pointOfInterestCategoryRaw)
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

    var body: some View {
        Circle()
            .fill(style.tint)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: style.symbolName)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.white)
            }
    }
}

private struct SelectedLocationRow: View {
    let selection: TransactionLocationSelection
    /// Clearing the choice lives on this row rather than in a separate destructive row
    /// below it.
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlaceCategoryIcon(
                style: PlaceCategoryStyle.style(forCategoryRawValue: selection.pointOfInterestCategoryRaw)
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

/// Text search over places, returning the same `TransactionLocationSelection` values the
/// nearby-suggestions list is built from.
///
/// Deliberately a real `MKLocalSearch` rather than `MKLocalSearchCompleter`: completions
/// are only a title and a subtitle, with no coordinate and no category, so a completion
/// row could show neither the place's icon nor how far away it is. Searching costs a
/// round trip, so typing is debounced and each new keystroke cancels the search in flight.
@Observable
@MainActor
private final class TransactionPlaceSearchModel {
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    private(set) var results: [TransactionLocationSelection] = []
    private(set) var isSearching = false

    @ObservationIgnored private var region = MKCoordinateRegion(
        center: TransactionLocationMapDefaults.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
    )
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Long enough that an ordinary typing burst issues one search, short enough that the
    /// list still feels like it is keeping up.
    private static let debounce = Duration.milliseconds(350)

    deinit {
        searchTask?.cancel()
    }

    func updateRegion(centeredAt coordinate: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            isSearching = false
            return
        }

        // Shown from the first keystroke: the list is already replaced by search results,
        // and an empty section while the debounce runs reads as "nothing found".
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.search(trimmedQuery)
        }
    }

    private func search(_ text: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = region
        request.resultTypes = [.pointOfInterest, .address]

        let places: [TransactionLocationSelection]
        do {
            let response = try await TransactionPlaceLookup.run(MKLocalSearch(request: request))
            places = response.mapItems.map {
                TransactionPlaceLookup.selection(from: $0, source: .mapSearch, accuracy: nil)
            }
        } catch {
            places = []
        }

        // A newer keystroke already owns the list; its own search will fill it in.
        guard !Task.isCancelled else { return }
        results = places
        isSearching = false
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

    /// Moves a reverse-geocoded result back onto the exact point the user picked, keeping
    /// everything the geocoder found *about* that point — name, address, locality.
    ///
    /// Reverse geocoding answers "what address is at this coordinate", and an address has to
    /// be an addressable feature: pin a lake, a field, or the middle of a long block and the
    /// nearest one can be the road beside it, or the parallel street. Taking that answer's
    /// coordinate wholesale slid the pin off the chosen spot the moment it was confirmed —
    /// the map showed it in the right place, the saved location was somewhere else. Maps
    /// itself leaves a dropped pin where it was dropped and prints the address underneath.
    func anchored(at coordinate: CLLocationCoordinate2D) -> Self {
        var anchored = self
        anchored.latitude = coordinate.latitude
        anchored.longitude = coordinate.longitude
        // The geocode's accuracy describes the address it matched, not a hand-placed point;
        // there is no measurement uncertainty to record for a coordinate the user chose.
        anchored.horizontalAccuracyMeters = nil
        return anchored
    }
}

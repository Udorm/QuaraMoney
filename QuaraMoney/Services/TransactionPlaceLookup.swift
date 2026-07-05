import CoreLocation
import MapKit

/// Shared MapKit lookups for transaction locations: reverse geocoding, nearby
/// point-of-interest discovery, and mapping `MKMapItem` → `TransactionLocationSelection`.
///
/// Used by both `TransactionLocationPickerView` (full picker) and `AddTransactionView`
/// (compact one-tap "use current location") so the selection-building logic lives in one place.
@MainActor
enum TransactionPlaceLookup {
    /// Resolves a coordinate into a named place via reverse geocoding.
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

    /// Fetches nearby points of interest around a coordinate, ranked by distance (closest first).
    /// Returns genuinely local results instead of a single generic match.
    static func nearbyPlaces(
        around coordinate: CLLocationCoordinate2D,
        radius: CLLocationDistance = 1_000,
        limit: Int = 12
    ) async throws -> [TransactionLocationSelection] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        let response = try await run(MKLocalSearch(request: request))

        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let sorted = response.mapItems.sorted { lhs, rhs in
            origin.distance(to: lhs.location.coordinate) < origin.distance(to: rhs.location.coordinate)
        }

        return Array(sorted.prefix(limit)).map {
            selection(from: $0, source: .mapSearch, accuracy: nil)
        }
    }

    /// Maps an `MKMapItem` into a `TransactionLocationSelection`, including iOS 18 place identifiers.
    static func selection(
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

    static func run(_ search: MKLocalSearch) async throws -> MKLocalSearch.Response {
        try await withCheckedThrowingContinuation { continuation in
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

extension CLLocation {
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

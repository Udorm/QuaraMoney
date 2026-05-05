import Foundation
import SwiftData

enum TransactionLocationSource: String, Codable, CaseIterable {
    case currentLocation
    case mapSearch
    case mapTap
    case manual
    case receipt
}

@Model
final class TransactionLocation {
    @Attribute(.unique) var id: UUID

    var displayName: String?
    var fullAddress: String?
    var shortAddress: String?

    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double?
    var capturedAt: Date
    var sourceRaw: String

    var applePlaceID: String?
    var alternateApplePlaceIDs: String?
    var pointOfInterestCategoryRaw: String?

    var locality: String?
    var administrativeArea: String?
    var countryCode: String?

    var normalizedSpatialKey: String?

    init(
        displayName: String? = nil,
        fullAddress: String? = nil,
        shortAddress: String? = nil,
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double? = nil,
        capturedAt: Date = Date(),
        source: TransactionLocationSource,
        applePlaceID: String? = nil,
        alternateApplePlaceIDs: [String] = [],
        pointOfInterestCategoryRaw: String? = nil,
        locality: String? = nil,
        administrativeArea: String? = nil,
        countryCode: String? = nil
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.fullAddress = fullAddress
        self.shortAddress = shortAddress
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.capturedAt = capturedAt
        self.sourceRaw = source.rawValue
        self.applePlaceID = applePlaceID
        self.alternateApplePlaceIDs = alternateApplePlaceIDs.isEmpty ? nil : alternateApplePlaceIDs.joined(separator: "|")
        self.pointOfInterestCategoryRaw = pointOfInterestCategoryRaw
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.countryCode = countryCode
        self.normalizedSpatialKey = Self.spatialKey(latitude: latitude, longitude: longitude)
    }

    var source: TransactionLocationSource {
        get { TransactionLocationSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var alternateApplePlaceIDList: [String] {
        get {
            alternateApplePlaceIDs?
                .split(separator: "|")
                .map(String.init) ?? []
        }
        set {
            alternateApplePlaceIDs = newValue.isEmpty ? nil : newValue.joined(separator: "|")
        }
    }

    static func spatialKey(latitude: Double, longitude: Double) -> String {
        let roundedLatitude = (latitude * 1_000).rounded() / 1_000
        let roundedLongitude = (longitude * 1_000).rounded() / 1_000
        return "\(roundedLatitude),\(roundedLongitude)"
    }

    func updateSpatialKey() {
        normalizedSpatialKey = Self.spatialKey(latitude: latitude, longitude: longitude)
    }
}

import Foundation

struct TransactionLocationSelection: Equatable {
    var displayName: String?
    var fullAddress: String?
    var shortAddress: String?
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMeters: Double?
    var capturedAt: Date
    var source: TransactionLocationSource
    var applePlaceID: String?
    var alternateApplePlaceIDs: [String]
    var pointOfInterestCategoryRaw: String?
    var locality: String?
    var administrativeArea: String?
    var countryCode: String?

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
        self.displayName = displayName
        self.fullAddress = fullAddress
        self.shortAddress = shortAddress
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.capturedAt = capturedAt
        self.source = source
        self.applePlaceID = applePlaceID
        self.alternateApplePlaceIDs = alternateApplePlaceIDs
        self.pointOfInterestCategoryRaw = pointOfInterestCategoryRaw
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.countryCode = countryCode
    }

    init(location: TransactionLocation) {
        self.displayName = location.displayName
        self.fullAddress = location.fullAddress
        self.shortAddress = location.shortAddress
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.horizontalAccuracyMeters = location.horizontalAccuracyMeters
        self.capturedAt = location.capturedAt
        self.source = location.source
        self.applePlaceID = location.applePlaceID
        self.alternateApplePlaceIDs = location.alternateApplePlaceIDList
        self.pointOfInterestCategoryRaw = location.pointOfInterestCategoryRaw
        self.locality = location.locality
        self.administrativeArea = location.administrativeArea
        self.countryCode = location.countryCode
    }

    var title: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return "transaction.location.selected".localized
    }

    var subtitle: String? {
        if let shortAddress, !shortAddress.isEmpty, shortAddress != displayName {
            return shortAddress
        }
        if let fullAddress, !fullAddress.isEmpty, fullAddress != displayName {
            return fullAddress
        }
        return nil
    }

    func makePersistentLocation() -> TransactionLocation {
        TransactionLocation(
            displayName: displayName,
            fullAddress: fullAddress,
            shortAddress: shortAddress,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            capturedAt: capturedAt,
            source: source,
            applePlaceID: applePlaceID,
            alternateApplePlaceIDs: alternateApplePlaceIDs,
            pointOfInterestCategoryRaw: pointOfInterestCategoryRaw,
            locality: locality,
            administrativeArea: administrativeArea,
            countryCode: countryCode
        )
    }

    func apply(to location: TransactionLocation) {
        location.displayName = displayName
        location.fullAddress = fullAddress
        location.shortAddress = shortAddress
        location.latitude = latitude
        location.longitude = longitude
        location.horizontalAccuracyMeters = horizontalAccuracyMeters
        location.capturedAt = capturedAt
        location.source = source
        location.applePlaceID = applePlaceID
        location.alternateApplePlaceIDList = alternateApplePlaceIDs
        location.pointOfInterestCategoryRaw = pointOfInterestCategoryRaw
        location.locality = locality
        location.administrativeArea = administrativeArea
        location.countryCode = countryCode
        location.updateSpatialKey()
    }
}

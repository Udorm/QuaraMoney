import CoreLocation
import MapKit
import SwiftUI

/// The glyph and tint used to represent a place in lists and on map pins.
///
/// Mirrors how Maps draws a place: the point-of-interest category picks a category
/// glyph — a cup for a café, a fork for a restaurant — instead of a generic pin, so a
/// list of nearby places is scannable at a glance. Places without a category (plain
/// addresses, dropped pins) fall back to `.generic`.
///
/// MapKit only hands out Apple's own icon artwork (`MKIconStyle`) for a feature the
/// user taps on a map — there is no public API that turns an `MKMapItem` or a bare
/// category into that image. So the icons here are rebuilt from SF Symbols on the
/// colours Apple Maps actually uses, sampled from its own pins; see `Palette`.
struct PlaceCategoryStyle: Equatable {
    let symbolName: String
    let tint: Color

    /// No point-of-interest category — a street address or an unnamed coordinate.
    /// Maps draws these as the rose marker, same as a search result it cannot categorize.
    static let generic = PlaceCategoryStyle(symbolName: "mappin", tint: Palette.marker)
    /// The device's own location.
    static let currentLocation = PlaceCategoryStyle(symbolName: "location.fill", tint: Palette.transport)
    /// A pin the user is placing by hand, before it resolves to a real place.
    static let droppedPin = PlaceCategoryStyle(symbolName: "mappin", tint: Palette.marker)

    /// Apple Maps' place-pin colours, sampled from Maps on iOS 26 so a row here reads
    /// the same as the equivalent row in Maps. One colour per family, exactly as Maps
    /// groups them: every eatery is the same orange, every bank the same warm grey.
    enum Palette {
        /// Restaurants, cafés, bakeries, bars.
        static let food = Color(red: 252 / 255, green: 122 / 255, blue: 33 / 255)
        /// Shops, markets, supermarkets.
        static let retail = Color(red: 245 / 255, green: 168 / 255, blue: 27 / 255)
        /// Banks and ATMs.
        static let financial = Color(red: 126 / 255, green: 119 / 255, blue: 118 / 255)
        /// Hospitals, pharmacies, clinics, vets.
        static let health = Color(red: 232 / 255, green: 56 / 255, blue: 99 / 255)
        /// Airports, transit, parking, fuel, vehicles.
        static let transport = Color(red: 66 / 255, green: 144 / 255, blue: 244 / 255)
        /// Parks, nature, sport and recreation.
        static let outdoors = Color(red: 56 / 255, green: 190 / 255, blue: 85 / 255)
        /// Hotels and other lodging.
        static let lodging = Color(red: 151 / 255, green: 89 / 255, blue: 217 / 255)
        /// Museums, theatres, nightlife, attractions.
        static let culture = Color(red: 216 / 255, green: 84 / 255, blue: 168 / 255)
        /// Landmarks, monuments and civic buildings.
        static let landmark = Color(red: 92 / 255, green: 114 / 255, blue: 204 / 255)
        /// Schools, universities, libraries.
        static let education = Color(red: 127 / 255, green: 90 / 255, blue: 66 / 255)
        /// The plain marker Maps uses for anything it has no category for.
        static let marker = Color(red: 232 / 255, green: 56 / 255, blue: 106 / 255)
    }

    static func style(forCategoryRawValue rawValue: String?) -> PlaceCategoryStyle {
        guard let rawValue, !rawValue.isEmpty else { return .generic }
        return style(for: MKPointOfInterestCategory(rawValue: rawValue))
    }

    static func style(for category: MKPointOfInterestCategory?) -> PlaceCategoryStyle {
        guard let category else { return .generic }

        switch category {
        // Food & drink
        case .restaurant: return PlaceCategoryStyle(symbolName: "fork.knife", tint: Palette.food)
        case .cafe: return PlaceCategoryStyle(symbolName: "cup.and.saucer.fill", tint: Palette.food)
        case .bakery: return PlaceCategoryStyle(symbolName: "birthday.cake.fill", tint: Palette.food)
        case .brewery, .distillery: return PlaceCategoryStyle(symbolName: "mug.fill", tint: Palette.food)
        case .winery: return PlaceCategoryStyle(symbolName: "wineglass.fill", tint: Palette.food)
        case .nightlife: return PlaceCategoryStyle(symbolName: "music.microphone", tint: Palette.culture)

        // Shopping & money
        case .store: return PlaceCategoryStyle(symbolName: "bag.fill", tint: Palette.retail)
        case .foodMarket: return PlaceCategoryStyle(symbolName: "cart.fill", tint: Palette.retail)
        case .bank: return PlaceCategoryStyle(symbolName: "building.columns.fill", tint: Palette.financial)
        case .atm: return PlaceCategoryStyle(symbolName: "banknote.fill", tint: Palette.financial)

        // Travel & transport
        case .airport: return PlaceCategoryStyle(symbolName: "airplane", tint: Palette.transport)
        case .publicTransport: return PlaceCategoryStyle(symbolName: "tram.fill", tint: Palette.transport)
        case .parking: return PlaceCategoryStyle(symbolName: "parkingsign", tint: Palette.transport)
        case .gasStation: return PlaceCategoryStyle(symbolName: "fuelpump.fill", tint: Palette.transport)
        case .evCharger: return PlaceCategoryStyle(symbolName: "bolt.car.fill", tint: Palette.transport)
        case .carRental: return PlaceCategoryStyle(symbolName: "car.fill", tint: Palette.transport)
        case .automotiveRepair: return PlaceCategoryStyle(symbolName: "wrench.and.screwdriver.fill", tint: Palette.transport)
        case .marina: return PlaceCategoryStyle(symbolName: "sailboat.fill", tint: Palette.transport)
        case .hotel: return PlaceCategoryStyle(symbolName: "bed.double.fill", tint: Palette.lodging)
        case .rvPark, .campground: return PlaceCategoryStyle(symbolName: "tent.fill", tint: Palette.outdoors)

        // Health & safety
        case .hospital: return PlaceCategoryStyle(symbolName: "cross.fill", tint: Palette.health)
        case .pharmacy: return PlaceCategoryStyle(symbolName: "pills.fill", tint: Palette.health)
        case .animalService: return PlaceCategoryStyle(symbolName: "pawprint.fill", tint: Palette.health)
        case .fireStation: return PlaceCategoryStyle(symbolName: "flame.fill", tint: Palette.landmark)
        case .police: return PlaceCategoryStyle(symbolName: "shield.lefthalf.filled", tint: Palette.landmark)

        // Services
        case .postOffice: return PlaceCategoryStyle(symbolName: "envelope.fill", tint: Palette.landmark)
        case .mailbox: return PlaceCategoryStyle(symbolName: "envelope.fill", tint: Palette.landmark)
        case .laundry: return PlaceCategoryStyle(symbolName: "washer.fill", tint: Palette.transport)
        case .restroom: return PlaceCategoryStyle(symbolName: "toilet.fill", tint: Palette.transport)
        case .beauty: return PlaceCategoryStyle(symbolName: "scissors", tint: Palette.culture)
        case .spa: return PlaceCategoryStyle(symbolName: "leaf.fill", tint: Palette.culture)

        // Education & culture
        case .school: return PlaceCategoryStyle(symbolName: "building.2.fill", tint: Palette.education)
        case .university: return PlaceCategoryStyle(symbolName: "graduationcap.fill", tint: Palette.education)
        case .library: return PlaceCategoryStyle(symbolName: "books.vertical.fill", tint: Palette.education)
        case .museum: return PlaceCategoryStyle(symbolName: "building.columns.fill", tint: Palette.culture)
        case .planetarium: return PlaceCategoryStyle(symbolName: "moon.stars.fill", tint: Palette.culture)
        case .theater: return PlaceCategoryStyle(symbolName: "theatermasks.fill", tint: Palette.culture)
        case .movieTheater: return PlaceCategoryStyle(symbolName: "popcorn.fill", tint: Palette.culture)
        case .musicVenue: return PlaceCategoryStyle(symbolName: "guitars.fill", tint: Palette.culture)
        case .conventionCenter: return PlaceCategoryStyle(symbolName: "building.fill", tint: Palette.landmark)

        // Attractions
        case .amusementPark: return PlaceCategoryStyle(symbolName: "balloon.2.fill", tint: Palette.culture)
        case .aquarium: return PlaceCategoryStyle(symbolName: "fish.fill", tint: Palette.culture)
        case .zoo: return PlaceCategoryStyle(symbolName: "pawprint.fill", tint: Palette.culture)
        case .fairground: return PlaceCategoryStyle(symbolName: "party.popper.fill", tint: Palette.culture)
        case .castle, .fortress: return PlaceCategoryStyle(symbolName: "building.columns.fill", tint: Palette.landmark)
        case .landmark, .nationalMonument: return PlaceCategoryStyle(symbolName: "star.fill", tint: Palette.landmark)

        // Outdoors
        case .park, .nationalPark: return PlaceCategoryStyle(symbolName: "tree.fill", tint: Palette.outdoors)
        case .beach: return PlaceCategoryStyle(symbolName: "beach.umbrella.fill", tint: Palette.outdoors)
        case .hiking: return PlaceCategoryStyle(symbolName: "figure.hiking", tint: Palette.outdoors)
        case .fishing: return PlaceCategoryStyle(symbolName: "figure.fishing", tint: Palette.outdoors)
        case .kayaking: return PlaceCategoryStyle(symbolName: "oar.2.crossed", tint: Palette.outdoors)
        case .surfing: return PlaceCategoryStyle(symbolName: "figure.surfing", tint: Palette.outdoors)
        case .swimming: return PlaceCategoryStyle(symbolName: "figure.pool.swim", tint: Palette.outdoors)
        case .skiing: return PlaceCategoryStyle(symbolName: "figure.skiing.downhill", tint: Palette.outdoors)
        case .skating: return PlaceCategoryStyle(symbolName: "figure.ice.skating", tint: Palette.outdoors)
        case .skatePark: return PlaceCategoryStyle(symbolName: "skateboard.fill", tint: Palette.outdoors)
        case .rockClimbing: return PlaceCategoryStyle(symbolName: "figure.climbing", tint: Palette.outdoors)

        // Sport & fitness
        case .fitnessCenter: return PlaceCategoryStyle(symbolName: "dumbbell.fill", tint: Palette.outdoors)
        case .stadium: return PlaceCategoryStyle(symbolName: "sportscourt.fill", tint: Palette.outdoors)
        case .golf, .miniGolf: return PlaceCategoryStyle(symbolName: "figure.golf", tint: Palette.outdoors)
        case .tennis: return PlaceCategoryStyle(symbolName: "tennis.racket", tint: Palette.outdoors)
        case .soccer: return PlaceCategoryStyle(symbolName: "soccerball", tint: Palette.outdoors)
        case .basketball: return PlaceCategoryStyle(symbolName: "basketball.fill", tint: Palette.outdoors)
        case .baseball: return PlaceCategoryStyle(symbolName: "baseball.fill", tint: Palette.outdoors)
        case .volleyball: return PlaceCategoryStyle(symbolName: "volleyball.fill", tint: Palette.outdoors)
        case .bowling: return PlaceCategoryStyle(symbolName: "figure.bowling", tint: Palette.outdoors)
        case .goKart: return PlaceCategoryStyle(symbolName: "flag.pattern.checkered", tint: Palette.outdoors)

        default: return .generic
        }
    }
}

/// Process-wide cache of the distance formatters used by the location picker.
///
/// `MeasurementFormatter` wraps a `NumberFormatter`, so constructing one loads ICU
/// locale data — far too expensive to do per row while a list scrolls. Configured
/// once and only read afterwards; wiped when the in-app language changes so the
/// locale (and Khmer digits) can rebuild.
enum PlaceDistanceFormatterCache {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (formatter: MeasurementFormatter, numbers: NumberFormatter)?

    /// Below this, the distance is written in metres; at or above it, in kilometres.
    private static let kilometreThreshold: CLLocationDistance = 1_000

    nonisolated static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
    }

    /// A short, localized distance: metres under a kilometre ("350 m"), kilometres at or
    /// above one ("1.2 km", "12 km").
    ///
    /// Deliberately not `MKDistanceFormatter`, which follows the locale into feet and
    /// miles; this app states distances in metric everywhere.
    nonisolated static func string(for distance: CLLocationDistance) -> String {
        // Rounding decides the unit: 999.7 m must read "1 km", never "1,000 m".
        let metresAway = roundedForDisplay(max(0, distance))

        guard metresAway >= kilometreThreshold else {
            return string(Measurement(value: metresAway, unit: UnitLength.meters), fractionDigits: 0)
        }

        let kilometresAway = metresAway / 1_000
        return string(
            Measurement(value: kilometresAway, unit: UnitLength.kilometers),
            // Past ten kilometres the decimal is noise.
            fractionDigits: kilometresAway < 10 ? 1 : 0
        )
    }

    /// Maps' own granularity: single metres are noise at walking distance, so round to
    /// 10 m up close and 50 m the rest of the way to a kilometre.
    nonisolated private static func roundedForDisplay(_ metres: CLLocationDistance) -> CLLocationDistance {
        let step: CLLocationDistance = metres < 100 ? 10 : 50
        return (metres / step).rounded() * step
    }

    nonisolated private static func string(
        _ measurement: Measurement<UnitLength>,
        fractionDigits: Int
    ) -> String {
        lock.lock(); defer { lock.unlock() }

        let pair: (formatter: MeasurementFormatter, numbers: NumberFormatter)
        if let cached {
            pair = cached
        } else {
            let numbers = NumberFormatter()
            numbers.locale = .app

            let formatter = MeasurementFormatter()
            // Without this the formatter converts metres into whatever the locale
            // prefers, which turns "350 m" into "1,148 ft" on a US locale.
            formatter.unitOptions = .providedUnit
            formatter.unitStyle = .medium
            formatter.locale = .app

            pair = (formatter, numbers)
            cached = pair
        }

        // `numberFormatter` hands back a *copy*, so mutating it through the getter is
        // silently discarded — the digit count has to be assigned back to take effect.
        pair.numbers.maximumFractionDigits = fractionDigits
        pair.formatter.numberFormatter = pair.numbers
        return pair.formatter.string(from: measurement)
    }
}

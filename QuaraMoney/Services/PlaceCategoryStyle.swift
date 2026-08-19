import CoreLocation
import MapKit
import SwiftUI

/// The glyph and tint used to represent a place in lists and on map pins.
///
/// Mirrors how Maps draws a place: the point-of-interest category picks a category
/// glyph — a cup for a café, a fork for a restaurant — instead of a generic pin, so a
/// list of nearby places is scannable at a glance. Places without a category (plain
/// addresses, dropped pins) fall back to `.generic`.
struct PlaceCategoryStyle: Equatable {
    let symbolName: String
    let tint: Color

    /// No point-of-interest category — a street address or an unnamed coordinate.
    static let generic = PlaceCategoryStyle(symbolName: "mappin", tint: .blue)
    /// The device's own location.
    static let currentLocation = PlaceCategoryStyle(symbolName: "location.fill", tint: .blue)
    /// A pin the user is placing by hand, before it resolves to a real place.
    static let droppedPin = PlaceCategoryStyle(symbolName: "mappin", tint: .red)

    static func style(forCategoryRawValue rawValue: String?) -> PlaceCategoryStyle {
        guard let rawValue, !rawValue.isEmpty else { return .generic }
        return style(for: MKPointOfInterestCategory(rawValue: rawValue))
    }

    static func style(for category: MKPointOfInterestCategory?) -> PlaceCategoryStyle {
        guard let category else { return .generic }

        switch category {
        // Food & drink
        case .restaurant: return PlaceCategoryStyle(symbolName: "fork.knife", tint: .orange)
        case .cafe: return PlaceCategoryStyle(symbolName: "cup.and.saucer.fill", tint: .orange)
        case .bakery: return PlaceCategoryStyle(symbolName: "birthday.cake.fill", tint: .orange)
        case .brewery, .distillery: return PlaceCategoryStyle(symbolName: "mug.fill", tint: .orange)
        case .winery: return PlaceCategoryStyle(symbolName: "wineglass.fill", tint: .orange)
        case .nightlife: return PlaceCategoryStyle(symbolName: "music.microphone", tint: .purple)
        case .foodMarket: return PlaceCategoryStyle(symbolName: "carrot.fill", tint: .orange)

        // Shopping & money
        case .store: return PlaceCategoryStyle(symbolName: "storefront.fill", tint: .orange)
        case .bank: return PlaceCategoryStyle(symbolName: "building.columns.fill", tint: .green)
        case .atm: return PlaceCategoryStyle(symbolName: "banknote.fill", tint: .green)

        // Travel & transport
        case .airport: return PlaceCategoryStyle(symbolName: "airplane", tint: .blue)
        case .publicTransport: return PlaceCategoryStyle(symbolName: "tram.fill", tint: .blue)
        case .parking: return PlaceCategoryStyle(symbolName: "parkingsign", tint: .blue)
        case .gasStation: return PlaceCategoryStyle(symbolName: "fuelpump.fill", tint: .blue)
        case .evCharger: return PlaceCategoryStyle(symbolName: "bolt.car.fill", tint: .green)
        case .carRental: return PlaceCategoryStyle(symbolName: "car.fill", tint: .blue)
        case .automotiveRepair: return PlaceCategoryStyle(symbolName: "wrench.and.screwdriver.fill", tint: .blue)
        case .marina: return PlaceCategoryStyle(symbolName: "sailboat.fill", tint: .blue)
        case .hotel: return PlaceCategoryStyle(symbolName: "bed.double.fill", tint: .indigo)
        case .rvPark, .campground: return PlaceCategoryStyle(symbolName: "tent.fill", tint: .green)

        // Health & safety
        case .hospital: return PlaceCategoryStyle(symbolName: "cross.case.fill", tint: .red)
        case .pharmacy: return PlaceCategoryStyle(symbolName: "pills.fill", tint: .red)
        case .fireStation: return PlaceCategoryStyle(symbolName: "flame.fill", tint: .red)
        case .police: return PlaceCategoryStyle(symbolName: "shield.lefthalf.filled", tint: .red)

        // Services
        case .postOffice: return PlaceCategoryStyle(symbolName: "envelope.fill", tint: .blue)
        case .mailbox: return PlaceCategoryStyle(symbolName: "envelope.fill", tint: .blue)
        case .laundry: return PlaceCategoryStyle(symbolName: "washer.fill", tint: .blue)
        case .beauty: return PlaceCategoryStyle(symbolName: "scissors", tint: .pink)
        case .spa: return PlaceCategoryStyle(symbolName: "leaf.fill", tint: .pink)
        case .restroom: return PlaceCategoryStyle(symbolName: "toilet.fill", tint: .blue)
        case .animalService: return PlaceCategoryStyle(symbolName: "pawprint.fill", tint: .brown)

        // Education & culture
        case .school: return PlaceCategoryStyle(symbolName: "building.2.fill", tint: .indigo)
        case .university: return PlaceCategoryStyle(symbolName: "graduationcap.fill", tint: .indigo)
        case .library: return PlaceCategoryStyle(symbolName: "books.vertical.fill", tint: .indigo)
        case .museum: return PlaceCategoryStyle(symbolName: "building.columns.fill", tint: .purple)
        case .planetarium: return PlaceCategoryStyle(symbolName: "moon.stars.fill", tint: .purple)
        case .theater: return PlaceCategoryStyle(symbolName: "theatermasks.fill", tint: .purple)
        case .movieTheater: return PlaceCategoryStyle(symbolName: "popcorn.fill", tint: .purple)
        case .musicVenue: return PlaceCategoryStyle(symbolName: "guitars.fill", tint: .purple)
        case .conventionCenter: return PlaceCategoryStyle(symbolName: "building.fill", tint: .purple)

        // Attractions
        case .amusementPark: return PlaceCategoryStyle(symbolName: "balloon.2.fill", tint: .purple)
        case .aquarium: return PlaceCategoryStyle(symbolName: "fish.fill", tint: .teal)
        case .zoo: return PlaceCategoryStyle(symbolName: "pawprint.fill", tint: .green)
        case .fairground: return PlaceCategoryStyle(symbolName: "party.popper.fill", tint: .purple)
        case .castle, .fortress: return PlaceCategoryStyle(symbolName: "building.columns.fill", tint: .brown)
        case .landmark, .nationalMonument: return PlaceCategoryStyle(symbolName: "star.fill", tint: .brown)

        // Outdoors
        case .park, .nationalPark: return PlaceCategoryStyle(symbolName: "tree.fill", tint: .green)
        case .beach: return PlaceCategoryStyle(symbolName: "beach.umbrella.fill", tint: .teal)
        case .hiking: return PlaceCategoryStyle(symbolName: "figure.hiking", tint: .green)
        case .fishing: return PlaceCategoryStyle(symbolName: "figure.fishing", tint: .teal)
        case .kayaking: return PlaceCategoryStyle(symbolName: "oar.2.crossed", tint: .teal)
        case .surfing: return PlaceCategoryStyle(symbolName: "figure.surfing", tint: .teal)
        case .swimming: return PlaceCategoryStyle(symbolName: "figure.pool.swim", tint: .teal)
        case .skiing: return PlaceCategoryStyle(symbolName: "figure.skiing.downhill", tint: .teal)
        case .skating: return PlaceCategoryStyle(symbolName: "figure.ice.skating", tint: .teal)
        case .skatePark: return PlaceCategoryStyle(symbolName: "skateboard.fill", tint: .green)
        case .rockClimbing: return PlaceCategoryStyle(symbolName: "figure.climbing", tint: .green)

        // Sport & fitness
        case .fitnessCenter: return PlaceCategoryStyle(symbolName: "dumbbell.fill", tint: .green)
        case .stadium: return PlaceCategoryStyle(symbolName: "sportscourt.fill", tint: .green)
        case .golf, .miniGolf: return PlaceCategoryStyle(symbolName: "figure.golf", tint: .green)
        case .tennis: return PlaceCategoryStyle(symbolName: "tennis.racket", tint: .green)
        case .soccer: return PlaceCategoryStyle(symbolName: "soccerball", tint: .green)
        case .basketball: return PlaceCategoryStyle(symbolName: "basketball.fill", tint: .green)
        case .baseball: return PlaceCategoryStyle(symbolName: "baseball.fill", tint: .green)
        case .volleyball: return PlaceCategoryStyle(symbolName: "volleyball.fill", tint: .green)
        case .bowling: return PlaceCategoryStyle(symbolName: "figure.bowling", tint: .green)
        case .goKart: return PlaceCategoryStyle(symbolName: "flag.pattern.checkered", tint: .green)

        default: return .generic
        }
    }
}

/// Process-wide cache of the distance formatter used by the location picker.
///
/// `MKDistanceFormatter` wraps a `NumberFormatter`, so constructing one loads ICU
/// locale data — far too expensive to do per row while a list scrolls. Configured
/// once and only read afterwards; wiped when the in-app language changes so the
/// locale (and Khmer digits) can rebuild.
enum PlaceDistanceFormatterCache {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: MKDistanceFormatter?

    nonisolated static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
    }

    /// A short, localized distance such as "350 m" or "1.2 km".
    nonisolated static func string(for distance: CLLocationDistance) -> String {
        lock.lock(); defer { lock.unlock() }

        let formatter: MKDistanceFormatter
        if let cached {
            formatter = cached
        } else {
            formatter = MKDistanceFormatter()
            formatter.unitStyle = .abbreviated
            formatter.locale = .app
            cached = formatter
        }

        return formatter.string(fromDistance: distance)
    }
}

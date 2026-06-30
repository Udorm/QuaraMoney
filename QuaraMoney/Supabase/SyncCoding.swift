import Foundation

/// Forces an optional value to encode as an explicit JSON `null` instead of being
/// omitted.
///
/// Swift's synthesized `Codable` encodes optional properties with
/// `encodeIfPresent`, so a `nil` is dropped from the payload entirely. PostgREST
/// `upsert` treats a **missing** key as "leave this column unchanged" — so
/// clearing a field locally (e.g. uncategorizing a transaction → `category_id =
/// nil`) would never reach the server, and the next pull would restore the old
/// value. Wrapping the property emits `null`, which PostgREST applies as a real
/// `NULL`.
@propertyWrapper
struct NullEncodable<T: Codable & Sendable>: Codable, Sendable {
    var wrappedValue: T?

    init(wrappedValue: T?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = container.decodeNil() ? nil : try container.decode(T.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = wrappedValue {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

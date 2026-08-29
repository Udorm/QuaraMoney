import Foundation
import SwiftData

/// Lightweight location payload for cross-device shared expenses.
struct SharedExpenseLocation: Codable, Equatable, Sendable {
    var displayName: String?
    var fullAddress: String?
    var shortAddress: String?
    var latitude: Double
    var longitude: Double
    var locality: String?
    var administrativeArea: String?
    var countryCode: String?

    var primaryTitle: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let shortAddress, !shortAddress.isEmpty { return shortAddress }
        if let fullAddress, !fullAddress.isEmpty { return fullAddress }
        return "split.location".localized
    }

    var secondaryTitle: String? {
        if let fullAddress, !fullAddress.isEmpty, fullAddress != displayName {
            return fullAddress
        }
        if let shortAddress, !shortAddress.isEmpty, shortAddress != displayName {
            return shortAddress
        }
        return nil
    }
}

// MARK: - Payload limits

/// Bounds applied to every decoded payload.
///
/// A custom URL scheme is an **unauthenticated** entry point: any app, web page
/// or QR code can invoke `quaramoney://split?data=…`. Nothing about a decoded
/// payload is trustworthy, so every field is range-checked and every string is
/// length-capped before it reaches the model layer.
enum SharedExpenseLimits {
    /// Cap on `entries`. A trip with more expenses than this exports
    /// consolidated instead.
    static let maxEntries = 300
    static let maxTitleLength = 120
    static let maxNoteLength = 500
    static let maxNameLength = 80
    static let maxIdentifierLength = 64
    /// Upper bound in major units. Generous enough for any real ledger, small
    /// enough that a hostile value can't overflow downstream arithmetic.
    static let maxAmount: Decimal = 1_000_000_000
    static let maxSplitCount = 1_000
    /// Accepted date window — guards against sentinel dates (`.distantPast`,
    /// year 40000) that would corrupt reporting buckets.
    static let earliestDate = Date(timeIntervalSince1970: 0)
    static let latestDateInterval: TimeInterval = 60 * 60 * 24 * 365 * 10

    /// Links older than this are surfaced as stale in the staging screen.
    /// Payloads carry no nonce, so an old link stays replayable forever.
    static let stalenessInterval: TimeInterval = 60 * 60 * 24 * 7
}

// MARK: - v2 additions

/// Provenance of a v2 payload.
///
/// > Important: `app` is a **claim made by the sender**, not a verified fact.
/// > Custom URL schemes carry no origin attestation, so this must never be
/// > rendered as a trust signal.
struct SharedExpenseSource: Codable, Equatable, Sendable {
    /// Sending app identifier, e.g. `"mitratrip"`. Unverified.
    var app: String
    var tripId: String
    var tripName: String
    /// When the link was generated, used to flag stale links.
    var createdAt: Date
    /// ISO fraction digits for `currencyCode`, stated explicitly so the
    /// receiver never has to infer precision from the currency code.
    var currencyExponent: Int
    /// Authoritative consolidated total, in minor units. Takes precedence over
    /// the v1 `Decimal` mirror so the two can never drift apart.
    var totalMinor: Int64
}

/// One expense's worth of the sender's own share.
struct SharedExpenseEntry: Codable, Equatable, Sendable, Identifiable {
    /// The sending app's expense id — stable across re-exports of the same trip.
    var sourceId: String
    var title: String
    /// The sender's share of this expense, in minor units of `currencyCode`.
    var amountMinor: Int64
    var categoryKey: String?
    var date: Date

    var id: String { sourceId }
}

// MARK: - Payload

/// Lightweight transfer payload for one-off split expenses across devices.
/// Transient and self-contained — requires zero schema migrations or server storage.
///
/// **v2 is a strict superset of v1.** `decodePayload` decodes with `try?`, so a
/// v2 payload that broke v1 decoding would fail *silently*: it would fall through
/// to the query-parameter path, return `nil`, and do nothing visible. Every v1
/// field therefore stays populated with the consolidated figures, and an older
/// build degrades to a single consolidated import rather than dropping the link.
struct SharedExpensePayload: Codable, Equatable, Sendable, Identifiable {
    var id: String {
        if let source { return "\(source.app)-\(source.tripId)-\(source.totalMinor)-\(entries?.count ?? 0)" }
        return "\(date.timeIntervalSince1970)-\(splitAmount)-\(currencyCode)-\(categoryKey ?? "")"
    }

    var version: Int = 1
    var originalAmount: Decimal
    var splitAmount: Decimal
    var currencyCode: String
    var categoryKey: String?
    var categoryName: String?
    var note: String?
    var date: Date
    var splitCount: Int
    var isCustomSplit: Bool
    var location: SharedExpenseLocation?

    // v2 — absent on payloads from a v1 sender.
    var source: SharedExpenseSource?
    var entries: [SharedExpenseEntry]?

    init(
        version: Int = 1,
        originalAmount: Decimal,
        splitAmount: Decimal,
        currencyCode: String,
        categoryKey: String? = nil,
        categoryName: String? = nil,
        note: String? = nil,
        date: Date = Date(),
        splitCount: Int = 2,
        isCustomSplit: Bool = false,
        location: SharedExpenseLocation? = nil,
        source: SharedExpenseSource? = nil,
        entries: [SharedExpenseEntry]? = nil
    ) {
        self.version = version
        self.originalAmount = originalAmount
        self.splitAmount = splitAmount
        self.currencyCode = currencyCode.uppercased()
        self.categoryKey = categoryKey
        self.categoryName = categoryName
        self.note = note
        self.date = date
        self.splitCount = max(1, splitCount)
        self.isCustomSplit = isCustomSplit
        self.location = location
        self.source = source
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case version, originalAmount, splitAmount, currencyCode, categoryKey
        case categoryName, note, date, splitCount, isCustomSplit, location
        case source, entries
    }

    /// Validating decode.
    ///
    /// Without this the compiler synthesises `init(from:)`, which **bypasses the
    /// memberwise initialiser entirely** — so the `max(1, splitCount)` clamp and
    /// the `.uppercased()` normalisation above never ran on the path that
    /// actually matters. Negative amounts, malformed currency codes and unbounded
    /// strings all reached the model layer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        version = (try? c.decode(Int.self, forKey: .version)) ?? 1

        let rawSplit = try c.decode(Decimal.self, forKey: .splitAmount)
        let rawOriginal = (try? c.decode(Decimal.self, forKey: .originalAmount)) ?? rawSplit
        splitAmount = try Self.validAmount(rawSplit, key: .splitAmount, allowZero: false)
        originalAmount = try Self.validAmount(rawOriginal, key: .originalAmount, allowZero: true)

        currencyCode = try Self.validCurrencyCode(try c.decode(String.self, forKey: .currencyCode))

        categoryKey = Self.clamped(try? c.decode(String.self, forKey: .categoryKey),
                                   max: SharedExpenseLimits.maxIdentifierLength)
        categoryName = Self.clamped(try? c.decode(String.self, forKey: .categoryName),
                                    max: SharedExpenseLimits.maxNameLength)
        note = Self.clamped(try? c.decode(String.self, forKey: .note),
                            max: SharedExpenseLimits.maxNoteLength)

        date = try Self.validDate(try c.decode(Date.self, forKey: .date), key: .date)

        let rawCount = (try? c.decode(Int.self, forKey: .splitCount)) ?? 1
        splitCount = min(max(1, rawCount), SharedExpenseLimits.maxSplitCount)
        isCustomSplit = (try? c.decode(Bool.self, forKey: .isCustomSplit)) ?? false

        location = try Self.validLocation(try? c.decode(SharedExpenseLocation.self, forKey: .location))

        // v2 — an unreadable v2 section degrades to a consolidated v1 import
        // rather than discarding the whole payload.
        source = try? c.decode(SharedExpenseSource.self, forKey: .source)
        if let decodedSource = source {
            guard (0...4).contains(decodedSource.currencyExponent),
                  decodedSource.totalMinor > 0,
                  decodedSource.totalMinor < Int64(truncating: NSDecimalNumber(decimal: SharedExpenseLimits.maxAmount * 10_000))
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .source, in: c, debugDescription: "Source out of range"
                )
            }
            source?.app = Self.clamped(decodedSource.app, max: SharedExpenseLimits.maxNameLength) ?? ""
            source?.tripId = Self.clamped(decodedSource.tripId, max: SharedExpenseLimits.maxIdentifierLength) ?? ""
            source?.tripName = Self.clamped(decodedSource.tripName, max: SharedExpenseLimits.maxNameLength) ?? ""
            source?.createdAt = try Self.validDate(decodedSource.createdAt, key: .source)
        }

        if let rawEntries = try? c.decode([SharedExpenseEntry].self, forKey: .entries) {
            guard rawEntries.count <= SharedExpenseLimits.maxEntries else {
                throw DecodingError.dataCorruptedError(
                    forKey: .entries, in: c, debugDescription: "Too many entries"
                )
            }
            let sanitized = try rawEntries.map { entry -> SharedExpenseEntry in
                guard entry.amountMinor > 0 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .entries, in: c, debugDescription: "Non-positive entry amount"
                    )
                }
                return SharedExpenseEntry(
                    sourceId: Self.clamped(entry.sourceId, max: SharedExpenseLimits.maxIdentifierLength) ?? UUID().uuidString,
                    title: Self.clamped(entry.title, max: SharedExpenseLimits.maxTitleLength) ?? "",
                    amountMinor: entry.amountMinor,
                    categoryKey: Self.clamped(entry.categoryKey, max: SharedExpenseLimits.maxIdentifierLength),
                    date: try Self.validDate(entry.date, key: .entries)
                )
            }
            entries = sanitized.isEmpty ? nil : sanitized
        } else {
            entries = nil
        }
    }

    // MARK: Validation helpers

    private static func validAmount(
        _ value: Decimal, key: CodingKeys, allowZero: Bool
    ) throws -> Decimal {
        guard !value.isNaN, value <= SharedExpenseLimits.maxAmount,
              allowZero ? value >= 0 : value > 0
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [key], debugDescription: "Amount out of range: \(value)")
            )
        }
        return value
    }

    private static func validCurrencyCode(_ raw: String) throws -> String {
        let code = raw.uppercased()
        guard code.count == 3, code.allSatisfy({ $0.isLetter && $0.isASCII }) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [CodingKeys.currencyCode], debugDescription: "Bad currency code")
            )
        }
        return code
    }

    private static func validDate(_ date: Date, key: CodingKeys) throws -> Date {
        let latest = Date().addingTimeInterval(SharedExpenseLimits.latestDateInterval)
        guard date >= SharedExpenseLimits.earliestDate, date <= latest else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [key], debugDescription: "Date out of range")
            )
        }
        return date
    }

    private static func validLocation(_ location: SharedExpenseLocation?) throws -> SharedExpenseLocation? {
        guard var location else { return nil }
        guard (-90...90).contains(location.latitude), (-180...180).contains(location.longitude) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [CodingKeys.location], debugDescription: "Coordinate out of range")
            )
        }
        location.displayName = clamped(location.displayName, max: SharedExpenseLimits.maxNameLength)
        location.fullAddress = clamped(location.fullAddress, max: SharedExpenseLimits.maxNoteLength)
        location.shortAddress = clamped(location.shortAddress, max: SharedExpenseLimits.maxNoteLength)
        location.locality = clamped(location.locality, max: SharedExpenseLimits.maxNameLength)
        location.administrativeArea = clamped(location.administrativeArea, max: SharedExpenseLimits.maxNameLength)
        location.countryCode = clamped(location.countryCode, max: 8)
        return location
    }

    /// Trims and truncates, mapping an empty result to `nil`.
    private static func clamped(_ value: String?, max limit: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit))
    }

    // MARK: Derived

    /// True when the payload carries a per-expense breakdown.
    var isDetailed: Bool { (entries?.isEmpty == false) }

    /// Fraction digits for this payload's currency. Uses the exponent the sender
    /// stated when present, so the receiver never infers precision.
    var currencyExponent: Int {
        source?.currencyExponent ?? MoneyMinorUnitConverter.fractionDigits(for: currencyCode)
    }

    /// The consolidated total. Minor units win when a v2 source is present, so
    /// the integer and `Decimal` representations can never disagree.
    var consolidatedAmount: Decimal {
        if let source {
            return MoneyMinorUnitConverter.fromMinorUnits(source.totalMinor, currencyCode: currencyCode)
        }
        return splitAmount
    }

    /// True when the link was generated long enough ago to be worth flagging.
    /// Payloads carry no nonce, so an old link remains replayable indefinitely.
    var isStale: Bool {
        guard let created = source?.createdAt else { return false }
        return Date().timeIntervalSince(created) > SharedExpenseLimits.stalenessInterval
    }
}

// MARK: - Service

enum SplitExpenseService {
    static let urlScheme = "quaramoney"
    static let urlHost = "split"

    // MARK: - URL Generation

    /// Generates a `quaramoney://split?data=<base64>` deep link from a payload.
    static func generateURL(for payload: SharedExpensePayload) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(payload) else { return nil }

        let base64String = jsonData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))

        var components = URLComponents()
        components.scheme = urlScheme
        components.host = urlHost
        components.queryItems = [
            URLQueryItem(name: "data", value: base64String)
        ]
        return components.url
    }

    /// Generates user-facing share text to accompany the link in messaging apps.
    static func generateShareText(for payload: SharedExpensePayload, deepLink: URL) -> String {
        let title = payload.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (payload.note ?? "")
            : (payload.categoryName ?? "split.title".localized)
        let formattedSplit = payload.splitAmount.formattedAmount(for: payload.currencyCode)
        let formattedOriginal = payload.originalAmount.formattedAmount(for: payload.currencyCode)

        let isFullAmount = payload.splitCount <= 1 || payload.splitAmount == payload.originalAmount
        let body: String
        if isFullAmount {
            let fullTemplate = "split.shareMessageFull".localized
            if fullTemplate.contains("%@") {
                body = String(format: fullTemplate, title, formattedOriginal, deepLink.absoluteString)
            } else {
                body = "Expense for \(title): \(formattedOriginal). Open in QuaraMoney: \(deepLink.absoluteString)"
            }
        } else {
            let messageTemplate = "split.shareMessage".localized
            if messageTemplate.contains("%@") {
                body = String(format: messageTemplate, title, "\(formattedSplit) (\(formattedOriginal))", deepLink.absoluteString)
            } else {
                body = "Split bill for \(title): \(formattedSplit) (from \(formattedOriginal)). Open in QuaraMoney: \(deepLink.absoluteString)"
            }
        }
        return body
    }

    // MARK: - URL Handling & Decoding

    /// Checks if a given deep link URL is a Split Bill intent.
    static func canHandle(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == urlScheme else { return false }
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        return host == urlHost || path.hasPrefix("/split") || path.contains("split")
    }

    /// Decodes a `SharedExpensePayload` from a `quaramoney://split` deep link URL.
    /// Returns `nil` for anything that fails validation — see
    /// `SharedExpensePayload.init(from:)`.
    static func decodePayload(from url: URL) -> SharedExpensePayload? {
        guard canHandle(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        // 1. Try base64 encoded data parameter
        if let base64Param = components.queryItems?.first(where: { $0.name == "data" })?.value {
            var base64 = base64Param
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let remainder = base64.count % 4
            if remainder > 0 {
                base64.append(String(repeating: "=", count: 4 - remainder))
            }

            if let data = Data(base64Encoded: base64) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let payload = try? decoder.decode(SharedExpensePayload.self, from: data) {
                    return payload
                }
            }
        }

        // 2. Fallback to individual query parameters
        let queryDict = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        guard let splitAmountStr = queryDict["amount"] ?? queryDict["splitAmount"],
              let splitAmount = Decimal(string: splitAmountStr),
              splitAmount > 0, splitAmount <= SharedExpenseLimits.maxAmount else {
            return nil
        }

        let currency = (queryDict["cur"] ?? queryDict["currency"] ?? "USD").uppercased()
        guard currency.count == 3, currency.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }

        let originalAmount = Decimal(string: queryDict["orig"] ?? queryDict["originalAmount"] ?? "") ?? (splitAmount * 2)
        let categoryKey = queryDict["cat"] ?? queryDict["categoryKey"]
        let categoryName = queryDict["catName"] ?? queryDict["categoryName"]
        let note = queryDict["note"]
        let splitCount = Int(queryDict["count"] ?? queryDict["splitCount"] ?? "2") ?? 2
        let isCustom = (queryDict["custom"] == "true" || queryDict["isCustom"] == "true")

        let date: Date
        if let dateStr = queryDict["date"], let parsedDate = ISO8601DateFormatter().date(from: dateStr) {
            date = parsedDate
        } else {
            date = Date()
        }

        let location: SharedExpenseLocation?
        if let latStr = queryDict["lat"], let lat = Double(latStr),
           let lngStr = queryDict["lng"], let lng = Double(lngStr),
           (-90...90).contains(lat), (-180...180).contains(lng) {
            location = SharedExpenseLocation(
                displayName: queryDict["locName"],
                fullAddress: queryDict["locAddr"],
                shortAddress: queryDict["locShortAddr"],
                latitude: lat,
                longitude: lng,
                locality: queryDict["locCity"],
                administrativeArea: queryDict["locState"],
                countryCode: queryDict["locCountry"]
            )
        } else {
            location = nil
        }

        return SharedExpensePayload(
            version: 1,
            originalAmount: min(originalAmount, SharedExpenseLimits.maxAmount),
            splitAmount: splitAmount,
            currencyCode: currency,
            categoryKey: categoryKey,
            categoryName: categoryName,
            note: note,
            date: date,
            splitCount: splitCount,
            isCustomSplit: isCustom,
            location: location
        )
    }

    // MARK: - Split Calculation

    /// Calculates equal split amount for a total amount and person count.
    ///
    /// Precision comes from `MoneyPrecision.splitFractionDigits` — ISO, plus the
    /// practice overrides that keep a split settleable in cash. This used to
    /// hardcode `KHR ? 0 : 2`, which got riel right for the right reason but
    /// gave JPY two decimal places it doesn't have and KWD two instead of three.
    static func calculateEqualSplit(totalAmount: Decimal, peopleCount: Int, currencyCode: String) -> Decimal {
        guard peopleCount > 0 else { return totalAmount }
        guard totalAmount > 0 else { return 0 }

        let countDecimal = Decimal(peopleCount)
        let rawDivision = totalAmount / countDecimal

        let scale = Int16(MoneyPrecision.splitFractionDigits(for: currencyCode))
        let behavior = NSDecimalNumberHandler(
            roundingMode: .bankers,
            scale: scale,
            raiseOnExactness: false,
            raiseOnOverflow: false,
            raiseOnUnderflow: false,
            raiseOnDivideByZero: false
        )
        let decimalNumber = NSDecimalNumber(decimal: rawDivision)
        return decimalNumber.rounding(accordingToBehavior: behavior) as Decimal
    }

    // MARK: - Category Resolution

    /// Resolves an active `Category` in the recipient's ModelContext from the incoming payload.
    @MainActor
    static func resolveCategory(for payload: SharedExpensePayload, in context: ModelContext) -> Category? {
        resolveCategory(key: payload.categoryKey, name: payload.categoryName, in: context)
    }

    /// Resolves a category from a canonical key or a display name.
    ///
    /// `CategoryCatalog.fetchOrCreate` **throws** for keys outside the shipped
    /// catalog and the name path only *matches* existing rows, so a hostile
    /// payload cannot mint arbitrary categories here.
    @MainActor
    static func resolveCategory(key: String?, name: String?, in context: ModelContext) -> Category? {
        // 1. Try canonical category key
        if let key, !key.isEmpty {
            if let category = try? CategoryCatalog.fetchOrCreate(key: key, in: context) {
                return category
            }
        }

        // 2. Try matching by category name
        if let name, !name.isEmpty {
            let descriptor = FetchDescriptor<Category>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
            if let allCats = try? context.fetch(descriptor) {
                if let match = allCats.first(where: { $0.type == .expense && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                    return match
                }
            }
        }

        // 3. Fallback to default "food_drink" or any expense category
        if let foodCategory = try? CategoryCatalog.fetchOrCreate(key: "food_drink", in: context) {
            return foodCategory
        }

        let fallbackDescriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        return try? context.fetch(fallbackDescriptor).first(where: { $0.type == .expense })
    }
}

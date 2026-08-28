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

/// Lightweight transfer payload for one-off split expenses across devices.
/// Transient and self-contained — requires zero schema migrations or server storage.
struct SharedExpensePayload: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(splitAmount)-\(currencyCode)-\(categoryKey ?? "")" }
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
        location: SharedExpenseLocation? = nil
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
    }
}

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
              splitAmount > 0 else {
            return nil
        }

        let currency = (queryDict["cur"] ?? queryDict["currency"] ?? "USD").uppercased()
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
           let lngStr = queryDict["lng"], let lng = Double(lngStr) {
            location = SharedExpenseLocation(
                displayName: queryDict["locName"],
                fullAddress: queryDict["locAddr"],
                shortAddress: queryDict["locShortAddr"],
                latitude: lat,
                longitude: lng
            )
        } else {
            location = nil
        }

        return SharedExpensePayload(
            version: 1,
            originalAmount: originalAmount,
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
    static func calculateEqualSplit(totalAmount: Decimal, peopleCount: Int, currencyCode: String) -> Decimal {
        guard peopleCount > 0 else { return totalAmount }
        guard totalAmount > 0 else { return 0 }

        let countDecimal = Decimal(peopleCount)
        let rawDivision = totalAmount / countDecimal

        // Round to 2 decimal places for USD or 0 for KHR
        let scale: Int16 = currencyCode.uppercased() == "KHR" ? 0 : 2
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
        // 1. Try canonical category key
        if let key = payload.categoryKey, !key.isEmpty {
            if let category = try? CategoryCatalog.fetchOrCreate(key: key, in: context) {
                return category
            }
        }

        // 2. Try matching by category name
        if let name = payload.categoryName, !name.isEmpty {
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

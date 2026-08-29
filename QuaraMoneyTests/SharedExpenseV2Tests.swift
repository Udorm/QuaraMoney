import XCTest
import SwiftData
@testable import QuaraMoney

/// Covers the v2 (MitraTrip) payload: the superset property that keeps older
/// builds working, minor-unit precedence, and the validation that guards an
/// unauthenticated URL entry point.
@MainActor
final class SharedExpenseV2Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let day: TimeInterval = 86_400
    private lazy var fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeV2Payload(
        entries: [SharedExpenseEntry]? = nil,
        currency: String = "USD",
        exponent: Int = 2,
        totalMinor: Int64 = 4_250,
        createdAt: Date? = nil
    ) -> SharedExpensePayload {
        let resolvedEntries = entries ?? [
            SharedExpenseEntry(sourceId: "exp-1", title: "Dinner", amountMinor: 2_500,
                               categoryKey: "food_drink", date: fixedDate),
            SharedExpenseEntry(sourceId: "exp-2", title: "Tuk-tuk", amountMinor: 1_750,
                               categoryKey: "transportation", date: fixedDate),
        ]
        let total = totalMinor
        return SharedExpensePayload(
            version: 2,
            originalAmount: MoneyMinorUnitConverter.fromMinorUnits(total, currencyCode: currency),
            splitAmount: MoneyMinorUnitConverter.fromMinorUnits(total, currencyCode: currency),
            currencyCode: currency,
            categoryKey: "trip",
            categoryName: "Trip",
            note: "Siem Reap",
            date: fixedDate,
            splitCount: 1,
            isCustomSplit: true,
            location: nil,
            source: SharedExpenseSource(
                app: "mitratrip",
                tripId: "trip-abc",
                tripName: "Siem Reap",
                createdAt: createdAt ?? fixedDate,
                currencyExponent: exponent,
                totalMinor: total
            ),
            entries: resolvedEntries
        )
    }

    private func roundTrip(_ payload: SharedExpensePayload) -> SharedExpensePayload? {
        guard let url = SplitExpenseService.generateURL(for: payload) else { return nil }
        return SplitExpenseService.decodePayload(from: url)
    }

    // MARK: - Round trip

    func testV2RoundTripPreservesSourceAndEntries() throws {
        let decoded = try XCTUnwrap(roundTrip(makeV2Payload()))

        XCTAssertEqual(decoded.version, 2)
        XCTAssertTrue(decoded.isDetailed)
        XCTAssertEqual(decoded.entries?.count, 2)
        XCTAssertEqual(decoded.source?.tripName, "Siem Reap")
        XCTAssertEqual(decoded.source?.totalMinor, 4_250)
        XCTAssertEqual(decoded.source?.currencyExponent, 2)
        XCTAssertEqual(decoded.entries?.first?.sourceId, "exp-1")
        XCTAssertEqual(decoded.entries?.first?.amountMinor, 2_500)
        XCTAssertEqual(decoded.entries?.last?.categoryKey, "transportation")
    }

    /// The whole point of the superset design: a build that only knows v1 fields
    /// must still get a usable consolidated import instead of silently dropping
    /// the link. Decoding into a v1-shaped struct proves the v1 fields stand alone.
    func testV2PayloadRemainsDecodableAsV1() throws {
        /// Mirrors the v1 field set exactly — no `source`, no `entries`.
        struct LegacyPayload: Decodable {
            var version: Int
            var originalAmount: Decimal
            var splitAmount: Decimal
            var currencyCode: String
            var categoryKey: String?
            var note: String?
            var date: Date
            var splitCount: Int
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeV2Payload())

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(LegacyPayload.self, from: data)

        XCTAssertEqual(legacy.currencyCode, "USD")
        XCTAssertEqual(legacy.splitAmount, Decimal(string: "42.50"))
        XCTAssertEqual(legacy.categoryKey, "trip")
        XCTAssertEqual(legacy.date, fixedDate)
    }

    // MARK: - Minor-unit precedence

    func testConsolidatedAmountPrefersMinorUnitsOverDecimalMirror() throws {
        var payload = makeV2Payload()
        // Simulate drift between the two representations; minor units must win.
        payload.splitAmount = 999
        let decoded = try XCTUnwrap(roundTrip(payload))

        XCTAssertEqual(decoded.consolidatedAmount, Decimal(string: "42.50"))
    }

    func testEntriesSumToConsolidatedTotal() throws {
        let decoded = try XCTUnwrap(roundTrip(makeV2Payload()))
        let sum = (decoded.entries ?? []).reduce(into: Int64(0)) { $0 += $1.amountMinor }

        XCTAssertEqual(sum, decoded.source?.totalMinor)
    }

    /// A zero-decimal currency must survive the wire as whole units.
    func testZeroDecimalCurrencyRoundTrip() throws {
        let entries = [
            SharedExpenseEntry(sourceId: "e1", title: "Ramen", amountMinor: 1_200,
                               categoryKey: "food_drink", date: fixedDate)
        ]
        let payload = makeV2Payload(entries: entries, currency: "JPY", exponent: 0, totalMinor: 1_200)
        let decoded = try XCTUnwrap(roundTrip(payload))

        XCTAssertEqual(decoded.currencyExponent, 0)
        XCTAssertEqual(decoded.consolidatedAmount, 1_200)
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "JPY"), 0)
    }

    /// The exponent travels in the payload, so the receiver never re-derives it.
    func testStatedExponentIsUsedOverInference() throws {
        let payload = makeV2Payload(currency: "USD", exponent: 3, totalMinor: 4_250)
        let decoded = try XCTUnwrap(roundTrip(payload))

        XCTAssertEqual(decoded.currencyExponent, 3)
    }

    // MARK: - Staleness

    func testFreshLinkIsNotStale() throws {
        let payload = makeV2Payload(createdAt: Date())
        let decoded = try XCTUnwrap(roundTrip(payload))
        XCTAssertFalse(decoded.isStale)
    }

    func testOldLinkIsStale() throws {
        let payload = makeV2Payload(createdAt: Date().addingTimeInterval(-10 * day))
        let decoded = try XCTUnwrap(roundTrip(payload))
        XCTAssertTrue(decoded.isStale)
    }

    // MARK: - Validation (S1)

    /// Decoding must reject hostile values. Before the validating `init(from:)`
    /// these all decoded successfully, because the synthesised initialiser
    /// bypassed the memberwise init's clamps entirely.
    private func assertRejected(
        _ mutate: (inout [String: Any]) -> Void,
        _ message: String,
        line: UInt = #line
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeV2Payload())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&json)

        let mutated = try JSONSerialization.data(withJSONObject: json)
        let base64 = mutated.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        let url = try XCTUnwrap(URL(string: "quaramoney://split?data=\(base64)"))

        XCTAssertNil(SplitExpenseService.decodePayload(from: url), message, line: line)
    }

    func testRejectsNegativeAmount() throws {
        try assertRejected({ $0["splitAmount"] = -50 }, "Negative amount must be rejected")
    }

    func testRejectsZeroAmount() throws {
        try assertRejected({ $0["splitAmount"] = 0 }, "Zero amount must be rejected")
    }

    func testRejectsAbsurdlyLargeAmount() throws {
        try assertRejected({ $0["splitAmount"] = 9_999_999_999_999 }, "Out-of-range amount must be rejected")
    }

    func testRejectsMalformedCurrencyCode() throws {
        try assertRejected({ $0["currencyCode"] = "US" }, "Two-letter currency must be rejected")
        try assertRejected({ $0["currencyCode"] = "12345" }, "Non-alphabetic currency must be rejected")
    }

    func testRejectsOutOfRangeCoordinates() throws {
        try assertRejected({
            $0["location"] = ["latitude": 999.0, "longitude": 0.0]
        }, "Impossible latitude must be rejected")
    }

    func testRejectsNonPositiveEntryAmount() throws {
        try assertRejected({ json in
            var entries = json["entries"] as? [[String: Any]] ?? []
            entries[0]["amountMinor"] = 0
            json["entries"] = entries
        }, "Zero-amount entry must be rejected")
    }

    func testRejectsTooManyEntries() throws {
        try assertRejected({ json in
            let template = (json["entries"] as? [[String: Any]] ?? []).first ?? [:]
            json["entries"] = (0...SharedExpenseLimits.maxEntries).map { index -> [String: Any] in
                var copy = template
                copy["sourceId"] = "e\(index)"
                return copy
            }
        }, "Entry count above the cap must be rejected")
    }

    func testClampsOverlongStrings() throws {
        var payload = makeV2Payload()
        payload.note = String(repeating: "a", count: 5_000)
        let decoded = try XCTUnwrap(roundTrip(payload))

        XCTAssertEqual(decoded.note?.count, SharedExpenseLimits.maxNoteLength)
    }

    func testClampsSplitCountOnDecodePath() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeV2Payload())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["splitCount"] = -5

        let mutated = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SharedExpensePayload.self, from: mutated)

        XCTAssertEqual(decoded.splitCount, 1, "splitCount must be clamped on the decode path, not just the memberwise init")
    }

    func testUppercasesCurrencyOnDecodePath() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeV2Payload())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["currencyCode"] = "usd"

        let mutated = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SharedExpensePayload.self, from: mutated)

        XCTAssertEqual(decoded.currencyCode, "USD")
    }

    // MARK: - Equal split precision (regression)

    /// `calculateEqualSplit` used to hardcode `KHR ? 0 : 2`, which got riel right
    /// for the right reason but gave JPY two decimal places it doesn't have and
    /// KWD two instead of three.
    func testEqualSplitRespectsPerCurrencyPrecision() {
        let jpy = SplitExpenseService.calculateEqualSplit(totalAmount: 1_000, peopleCount: 3, currencyCode: "JPY")
        XCTAssertEqual(jpy, 333, "JPY is zero-decimal")

        let kwd = SplitExpenseService.calculateEqualSplit(totalAmount: 1, peopleCount: 3, currencyCode: "KWD")
        XCTAssertEqual(kwd, Decimal(string: "0.333"), "KWD is three-decimal")

        let usd = SplitExpenseService.calculateEqualSplit(totalAmount: 10, peopleCount: 3, currencyCode: "USD")
        XCTAssertEqual(usd, Decimal(string: "3.33"))

        let khr = SplitExpenseService.calculateEqualSplit(totalAmount: 10_000, peopleCount: 3, currencyCode: "KHR")
        XCTAssertEqual(khr, 3_333, "Riel splits to whole units — the smallest note in circulation is 100")
    }

    /// The two precision authorities answer different questions and must be
    /// allowed to disagree. Collapsing them is how stored riel ends up 100x off.
    func testWireAndSplitPrecisionDivergeOnlyWherePracticeDemands() {
        XCTAssertEqual(MoneyPrecision.wireFractionDigits(for: "KHR"), 2, "ISO: riel has two minor digits")
        XCTAssertEqual(MoneyPrecision.splitFractionDigits(for: "KHR"), 0, "Practice: riel is settled in whole units")

        for code in ["USD", "EUR", "THB", "JPY", "KWD"] {
            XCTAssertEqual(
                MoneyPrecision.wireFractionDigits(for: code),
                MoneyPrecision.splitFractionDigits(for: code),
                "\(code) has no practice override and must agree on both"
            )
        }
    }

    // MARK: - Duplicate guard

    func testDuplicateGuardFlagsMatchingTransaction() throws {
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#4CAF50")
        context.insert(wallet)

        let existing = Transaction(amount: 25, currencyCode: "USD", date: fixedDate, type: .expense)
        existing.sourceWallet = wallet
        context.insert(existing)
        try context.save()

        let flagged = SharedExpenseImportGuard.likelyDuplicateIndices(
            among: [
                .init(amount: 25, currencyCode: "USD", date: fixedDate, searchHint: "Dinner"),
                .init(amount: 17.5, currencyCode: "USD", date: fixedDate, searchHint: "Tuk-tuk"),
            ],
            in: context
        )

        XCTAssertEqual(flagged, [0])
    }

    /// One existing transaction can only account for one candidate, so importing
    /// two genuinely separate identical expenses flags exactly one.
    func testDuplicateGuardConsumesEachMatchOnce() throws {
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#4CAF50")
        context.insert(wallet)

        let existing = Transaction(amount: 3, currencyCode: "USD", date: fixedDate, type: .expense)
        existing.sourceWallet = wallet
        context.insert(existing)
        try context.save()

        let flagged = SharedExpenseImportGuard.likelyDuplicateIndices(
            among: [
                .init(amount: 3, currencyCode: "USD", date: fixedDate, searchHint: "Coffee"),
                .init(amount: 3, currencyCode: "USD", date: fixedDate, searchHint: "Coffee"),
            ],
            in: context
        )

        XCTAssertEqual(flagged.count, 1)
    }

    func testDuplicateGuardIgnoresDifferentCurrency() throws {
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#4CAF50")
        context.insert(wallet)

        let existing = Transaction(amount: 25, currencyCode: "USD", date: fixedDate, type: .expense)
        existing.sourceWallet = wallet
        context.insert(existing)
        try context.save()

        let flagged = SharedExpenseImportGuard.likelyDuplicateIndices(
            among: [.init(amount: 25, currencyCode: "THB", date: fixedDate, searchHint: nil)],
            in: context
        )

        XCTAssertTrue(flagged.isEmpty)
    }
}

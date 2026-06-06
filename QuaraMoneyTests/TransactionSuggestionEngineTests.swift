import XCTest
import SwiftData
@testable import QuaraMoney

// Alias to avoid ambiguity with system Category
private typealias AppCategory = QuaraMoney.Category

@MainActor
final class TransactionSuggestionEngineTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    /// Fixed reference "now" so recency/weekday/hour signals are deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    // MARK: - Helpers

    private func makeWallet(_ name: String) -> Wallet {
        let w = Wallet(name: name, currencyCode: "USD", icon: "wallet.pass", colorHex: "#0000FF")
        context.insert(w)
        return w
    }

    private func makeCategory(_ name: String, type: TransactionType = .expense) -> AppCategory {
        let c = AppCategory(name: name, icon: "bag", colorHex: "#FF0000", type: type)
        context.insert(c)
        return c
    }

    private func makeLocation(latitude: Double, longitude: Double, placeID: String? = nil) -> TransactionLocation {
        let loc = TransactionLocation(latitude: latitude, longitude: longitude, source: .manual, applePlaceID: placeID)
        context.insert(loc)
        return loc
    }

    @discardableResult
    private func makeTransaction(
        type: TransactionType,
        sourceWallet: Wallet? = nil,
        destinationWallet: Wallet? = nil,
        category: AppCategory? = nil,
        date: Date,
        location: TransactionLocation? = nil
    ) -> Transaction {
        let txn = Transaction(amount: 10, currencyCode: "USD", date: date, type: type)
        txn.sourceWallet = sourceWallet
        txn.destinationWallet = destinationWallet
        txn.category = category
        txn.location = location
        context.insert(txn)
        return txn
    }

    private func date(daysAgo: Double) -> Date {
        now.addingTimeInterval(-daysAgo * 86_400)
    }

    private func flush() {
        try? context.save()
    }

    private func allCategories() -> [AppCategory] {
        (try? context.fetch(FetchDescriptor<AppCategory>())) ?? []
    }

    private func allWallets() -> [Wallet] {
        (try? context.fetch(FetchDescriptor<Wallet>())) ?? []
    }

    // MARK: - Recency

    func testRecentFewBeatsOldMany() {
        let recent = makeCategory("Recent")
        let stale = makeCategory("Stale")

        makeTransaction(type: .expense, category: recent, date: date(daysAgo: 1))
        for _ in 0..<10 {
            makeTransaction(type: .expense, category: stale, date: date(daysAgo: 300))
        }
        flush()

        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: nil, now: now
        )
        XCTAssertEqual(ranked.first?.category.name, "Recent",
                       "A recent transaction should outrank many stale ones")
    }

    // MARK: - Type-aware wallets

    func testWalletRankingIsTypeAware() {
        let spender = makeWallet("Spender")
        let earner = makeWallet("Earner")

        // Spender used for expenses; Earner used for income — same recent dates.
        for _ in 0..<3 {
            makeTransaction(type: .expense, sourceWallet: spender, date: date(daysAgo: 2))
            makeTransaction(type: .income, sourceWallet: earner, date: date(daysAgo: 2))
        }
        flush()

        let forExpense = TransactionSuggestionEngine.rankWallets(
            allWallets(), type: .expense, selectedCategory: nil, location: nil, now: now
        )
        XCTAssertEqual(forExpense.first?.wallet.name, "Spender",
                       "Expense entry should surface the wallet used for expenses")

        let forIncome = TransactionSuggestionEngine.rankWallets(
            allWallets(), type: .income, selectedCategory: nil, location: nil, now: now
        )
        XCTAssertEqual(forIncome.first?.wallet.name, "Earner",
                       "Income entry should surface the wallet used for income")
    }

    // MARK: - Co-occurrence

    func testCategoryCoOccurrenceWithSelectedWallet() {
        let walletW = makeWallet("W")
        let walletV = makeWallet("V")
        let food = makeCategory("Food")
        let transport = makeCategory("Transport")

        // Equal base (same dates/counts); only the paired wallet differs.
        for _ in 0..<2 {
            makeTransaction(type: .expense, sourceWallet: walletW, category: food, date: date(daysAgo: 3))
            makeTransaction(type: .expense, sourceWallet: walletV, category: transport, date: date(daysAgo: 3))
        }
        flush()

        let withW = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: walletW, location: nil, now: now
        )
        XCTAssertEqual(withW.first?.category.name, "Food",
                       "Selecting wallet W should boost the category usually paired with W")

        let withV = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: walletV, location: nil, now: now
        )
        XCTAssertEqual(withV.first?.category.name, "Transport",
                       "Selecting wallet V should boost the category usually paired with V")
    }

    // MARK: - Temporal boosts

    func testWeekdayBoost() {
        let sameWeekday = makeCategory("SameWeekday")
        let otherWeekday = makeCategory("OtherWeekday")

        // 7 days ago = same weekday & same time-of-day; 6 days ago = different weekday, same time.
        makeTransaction(type: .expense, category: sameWeekday, date: date(daysAgo: 7))
        makeTransaction(type: .expense, category: otherWeekday, date: date(daysAgo: 6))
        flush()

        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: nil, now: now
        )
        XCTAssertEqual(ranked.first?.category.name, "SameWeekday",
                       "Matching the current weekday should outweigh a one-day recency edge")
    }

    func testHourOfDayBoost() {
        let nearHour = makeCategory("NearHour")
        let farHour = makeCategory("FarHour")

        // Same day (negligible recency difference): one within ±2h of now, one far away.
        makeTransaction(type: .expense, category: nearHour, date: now.addingTimeInterval(-3600))      // 1h before
        makeTransaction(type: .expense, category: farHour, date: now.addingTimeInterval(-10 * 3600))   // 10h before
        flush()

        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: nil, now: now
        )
        XCTAssertEqual(ranked.first?.category.name, "NearHour",
                       "A transaction near the current hour should rank ahead")
    }

    // MARK: - Location

    func testLocationPlaceMatchBoostsOverNoLocation() {
        let here = makeCategory("Here")
        let elsewhere = makeCategory("Elsewhere")

        let loc = makeLocation(latitude: 11.500, longitude: 104.900, placeID: "PLACE_A")
        makeTransaction(type: .expense, category: here, date: date(daysAgo: 5), location: loc)
        makeTransaction(type: .expense, category: elsewhere, date: date(daysAgo: 5)) // no location
        flush()

        let context = SuggestionLocationContext(
            applePlaceID: "PLACE_A",
            spatialKey: TransactionLocation.spatialKey(latitude: 11.500, longitude: 104.900)
        )
        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: context, now: now
        )
        XCTAssertEqual(ranked.first?.category.name, "Here",
                       "Exact place match should outrank a location-less category")
    }

    func testSpatialKeyOnlyContextBoosts() {
        // Background-location path: no place ID, only a spatial key.
        let near = makeCategory("Near")
        let none = makeCategory("None")

        let loc = makeLocation(latitude: 11.500, longitude: 104.900, placeID: nil)
        makeTransaction(type: .expense, category: near, date: date(daysAgo: 5), location: loc)
        makeTransaction(type: .expense, category: none, date: date(daysAgo: 5))
        flush()

        let key = TransactionLocation.spatialKey(latitude: 11.500, longitude: 104.900)
        let context = SuggestionLocationContext(applePlaceID: nil, spatialKey: key)
        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: context, now: now
        )
        XCTAssertEqual(ranked.first?.category.name, "Near",
                       "A spatial-key-only context (background location) should still boost matching history")
        let nearScore = ranked.first { $0.category.name == "Near" }?.score ?? 0
        let noneScore = ranked.first { $0.category.name == "None" }?.score ?? 0
        XCTAssertGreaterThan(nearScore, noneScore)
    }

    func testPlaceMatchOutranksSpatialMatch() {
        let placeCat = makeCategory("PlaceCat")
        let nearCat = makeCategory("NearCat")

        let placeLoc = makeLocation(latitude: 11.500, longitude: 104.900, placeID: "PLACE_A")
        let nearLoc = makeLocation(latitude: 11.600, longitude: 104.900, placeID: nil)
        makeTransaction(type: .expense, category: placeCat, date: date(daysAgo: 5), location: placeLoc)
        makeTransaction(type: .expense, category: nearCat, date: date(daysAgo: 5), location: nearLoc)
        flush()

        // Context: exact place is PLACE_A, but we are physically on nearCat's grid cell.
        let context = SuggestionLocationContext(
            applePlaceID: "PLACE_A",
            spatialKey: TransactionLocation.spatialKey(latitude: 11.600, longitude: 104.900)
        )
        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: context, now: now
        )
        XCTAssertEqual(ranked.first?.category.name, "PlaceCat",
                       "An exact place match should outrank a mere spatial-cell match")
    }

    // MARK: - Cold start

    func testColdStartFallsBackToNameOrderNoHighlight() {
        _ = makeCategory("Transport")
        _ = makeCategory("Apparel")
        _ = makeCategory("Food")
        flush()

        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: nil, now: now
        )
        XCTAssertEqual(ranked.map { $0.category.name }, ["Apparel", "Food", "Transport"],
                       "With no history, categories should fall back to name order")
        XCTAssertFalse(ranked.contains { $0.isHighlighted },
                       "Nothing should be highlighted when there is no usage signal")
    }

    // MARK: - Highlight threshold

    func testDominantCategoryIsHighlighted() {
        let big = makeCategory("Big")
        _ = makeCategory("Small1")
        _ = makeCategory("Small2")

        for _ in 0..<4 {
            makeTransaction(type: .expense, category: big, date: date(daysAgo: 0.2))
        }
        flush()

        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: nil, now: now
        )
        XCTAssertEqual(ranked.first?.category.name, "Big")
        XCTAssertTrue(ranked.first?.isHighlighted ?? false,
                      "A clearly dominant category should be highlighted")
        XCTAssertFalse(ranked.dropFirst().contains { $0.isHighlighted },
                       "Only the top suggestion may be highlighted")
    }

    func testFlatDistributionIsNotHighlighted() {
        let a = makeCategory("A")
        let b = makeCategory("B")
        let c = makeCategory("C")

        // Three equal categories → top share ≈ 0.33 < 0.35 threshold, so no highlight.
        makeTransaction(type: .expense, category: a, date: date(daysAgo: 1))
        makeTransaction(type: .expense, category: b, date: date(daysAgo: 1))
        makeTransaction(type: .expense, category: c, date: date(daysAgo: 1))
        flush()

        let ranked = TransactionSuggestionEngine.rankCategories(
            allCategories(), type: .expense, selectedWallet: nil, location: nil, now: now
        )
        XCTAssertFalse(ranked.contains { $0.isHighlighted },
                       "No single category should be highlighted when usage is evenly spread")
    }
}

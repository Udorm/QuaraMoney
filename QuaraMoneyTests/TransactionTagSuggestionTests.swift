import XCTest
import SwiftData
@testable import QuaraMoney

// Alias to avoid ambiguity with system Category
private typealias AppCategory = QuaraMoney.Category

@MainActor
final class TransactionTagSuggestionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    /// Fixed reference "now" so recency signals are deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    // MARK: - Parser

    func testExtractsTagsInOrder() {
        XCTAssertEqual(
            TransactionTagParser.tags(in: "Lunch #food with team #work today"),
            ["food", "work"]
        )
    }

    func testNoHashReturnsEmpty() {
        XCTAssertEqual(TransactionTagParser.tags(in: "plain note"), [])
        XCTAssertEqual(TransactionTagParser.tags(in: nil), [])
        XCTAssertEqual(TransactionTagParser.tags(in: "lonely # sign"), [])
    }

    func testDeduplicatesCaseInsensitively() {
        XCTAssertEqual(
            TransactionTagParser.tags(in: "#Food then #food then #FOOD"),
            ["Food"]
        )
    }

    func testTagStopsAtPunctuationAndWhitespace() {
        XCTAssertEqual(
            TransactionTagParser.tags(in: "#coffee, #tea! and #milk_2x"),
            ["coffee", "tea", "milk_2x"]
        )
    }

    func testKhmerTags() {
        // Khmer relies on combining marks (vowel signs) — they must stay in the tag.
        XCTAssertEqual(
            TransactionTagParser.tags(in: "ទិញ #អាហារ និង #កាហ្វេ"),
            ["អាហារ", "កាហ្វេ"]
        )
    }

    func testActiveTagToken() {
        XCTAssertEqual(TransactionTagParser.activeTagToken(in: "lunch #fo"), "fo")
        XCTAssertEqual(TransactionTagParser.activeTagToken(in: "lunch #"), "")
        XCTAssertNil(TransactionTagParser.activeTagToken(in: "lunch #food "))
        XCTAssertNil(TransactionTagParser.activeTagToken(in: "no tags here"))
        XCTAssertEqual(TransactionTagParser.activeTagToken(in: "#a #b"), "b")
        XCTAssertEqual(TransactionTagParser.activeTagToken(in: "ទិញ #អាហា"), "អាហា")
    }

    // MARK: - Ranking

    private func makeTransaction(
        note: String?,
        daysAgo: Double,
        type: TransactionType = .expense,
        category: AppCategory? = nil,
        wallet: Wallet? = nil,
        extractTags: Bool = true
    ) -> Transaction {
        let txn = Transaction(
            amount: 10,
            currencyCode: "USD",
            date: now.addingTimeInterval(-daysAgo * 86_400),
            type: type
        )
        txn.note = note
        if extractTags { txn.tags = TransactionTagParser.tags(in: note) }
        txn.category = category
        txn.sourceWallet = wallet
        context.insert(txn)
        return txn
    }

    private func rank(
        _ transactions: [Transaction],
        type: TransactionType = .expense,
        wallet: Wallet? = nil,
        category: AppCategory? = nil
    ) -> [ScoredTag] {
        TransactionSuggestionEngine.rankTags(
            in: transactions,
            type: type,
            selectedWallet: wallet,
            selectedCategory: category,
            location: nil,
            now: now
        )
    }

    func testRecentTagOutranksStaleFrequentTag() {
        var txns: [Transaction] = []
        // "stale" used often, but ~10 months ago.
        for i in 0..<5 {
            txns.append(makeTransaction(note: "#stale", daysAgo: 300 + Double(i)))
        }
        // "fresh" used twice this week.
        txns.append(makeTransaction(note: "#fresh", daysAgo: 1))
        txns.append(makeTransaction(note: "#fresh", daysAgo: 2))

        let ranked = rank(txns)
        XCTAssertEqual(ranked.first?.tag, "fresh")
    }

    func testCategoryPairBoostReordersTags() {
        let food = AppCategory(name: "Food", icon: "bag", colorHex: "#FF0000", type: .expense)
        let travel = AppCategory(name: "Travel", icon: "car", colorHex: "#00FF00", type: .expense)
        context.insert(food)
        context.insert(travel)

        // Same recency: "lunch" rides with Food, "fuel" with Travel (twice, so it
        // wins on raw score) — selecting Food must flip the order.
        let txns = [
            makeTransaction(note: "#lunch", daysAgo: 3, category: food),
            makeTransaction(note: "#fuel", daysAgo: 3, category: travel),
            makeTransaction(note: "#fuel", daysAgo: 4, category: travel)
        ]

        XCTAssertEqual(rank(txns).first?.tag, "fuel")
        XCTAssertEqual(rank(txns, category: food).first?.tag, "lunch")
    }

    func testFallsBackToParsingNoteWhenTagsArrayEmpty() {
        // Row written by a path that never populated `tags`.
        let legacy = makeTransaction(note: "coffee run #coffee", daysAgo: 1, extractTags: false)
        XCTAssertTrue(legacy.tags.isEmpty)

        let ranked = rank([legacy])
        XCTAssertEqual(ranked.map(\.tag), ["coffee"])
    }

    func testFiltersByTransactionType() {
        let txns = [
            makeTransaction(note: "#salary", daysAgo: 1, type: .income),
            makeTransaction(note: "#groceries", daysAgo: 1, type: .expense)
        ]
        XCTAssertEqual(rank(txns, type: .expense).map(\.tag), ["groceries"])
        XCTAssertEqual(rank(txns, type: .income).map(\.tag), ["salary"])
    }

    func testMergesCasingsAndDisplaysMostRecentSpelling() {
        let txns = [
            makeTransaction(note: "#Coffee", daysAgo: 5),
            makeTransaction(note: "#coffee", daysAgo: 1)
        ]
        let ranked = rank(txns)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.tag, "coffee")
    }
}

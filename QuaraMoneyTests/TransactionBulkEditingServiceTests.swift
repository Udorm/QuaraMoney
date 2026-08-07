import XCTest
import SwiftData
@testable import QuaraMoney

private typealias AppCategory = QuaraMoney.Category

@MainActor
final class TransactionBulkEditingServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    private func makeTransaction(
        type: TransactionType = .expense,
        note: String? = nil,
        category: AppCategory? = nil
    ) -> Transaction {
        let transaction = Transaction(
            amount: 10,
            currencyCode: "USD",
            date: Date(),
            type: type
        )
        transaction.note = note
        transaction.tags = TransactionTagParser.tags(in: note)
        transaction.category = category
        let source = Wallet(name: "Source", currencyCode: "USD", icon: "wallet.pass", colorHex: "#000000")
        context.insert(source)
        transaction.sourceWallet = source
        transaction.needsSync = false
        transaction.updatedAt = Date(timeIntervalSince1970: 1)
        context.insert(transaction)
        return transaction
    }

    func testChangesCategoryForEntireCompatibleSelection() throws {
        let oldCategory = AppCategory(name: "Old", icon: "circle", colorHex: "000000", type: .expense)
        let newCategory = AppCategory(name: "Food", icon: "fork.knife", colorHex: "00AA00", type: .expense)
        context.insert(oldCategory)
        context.insert(newCategory)
        let first = makeTransaction(category: oldCategory)
        let second = makeTransaction(category: oldCategory)

        _ = try TransactionBulkEditingService.changeCategory(of: [first, second], to: newCategory, in: context)

        XCTAssertEqual(first.category?.id, newCategory.id)
        XCTAssertEqual(second.category?.id, newCategory.id)
        XCTAssertTrue(first.needsSync)
        XCTAssertTrue(second.needsSync)
        XCTAssertGreaterThan(first.updatedAt, Date(timeIntervalSince1970: 1))
    }

    func testRejectsMixedTypesBeforeChangingAnyCategory() throws {
        let expenseCategory = AppCategory(name: "Food", icon: "fork.knife", colorHex: "00AA00", type: .expense)
        let oldExpenseCategory = AppCategory(name: "Old Expense", icon: "circle", colorHex: "000000", type: .expense)
        let incomeCategory = AppCategory(name: "Salary", icon: "banknote", colorHex: "0000AA", type: .income)
        context.insert(expenseCategory)
        context.insert(oldExpenseCategory)
        context.insert(incomeCategory)
        let expense = makeTransaction(category: oldExpenseCategory)
        let income = makeTransaction(type: .income, category: incomeCategory)

        XCTAssertThrowsError(
            try TransactionBulkEditingService.changeCategory(
                of: [expense, income],
                to: expenseCategory,
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? TransactionBulkEditingService.BulkEditError, .incompatibleCategory)
        }
        XCTAssertEqual(expense.category?.id, oldExpenseCategory.id)
        XCTAssertEqual(income.category?.id, incomeCategory.id)
        XCTAssertFalse(expense.needsSync)
        XCTAssertFalse(income.needsSync)
    }

    func testAddsTagToNotesAndCachedTagsWithoutCaseInsensitiveDuplicates() throws {
        let first = makeTransaction(note: "Lunch")
        let second = makeTransaction(note: "Coffee #Work")

        _ = try TransactionBulkEditingService.addTag("#work", to: [first, second], in: context)

        XCTAssertEqual(first.note, "Lunch #work")
        XCTAssertEqual(first.tags, ["work"])
        XCTAssertEqual(second.note, "Coffee #Work")
        XCTAssertEqual(second.tags, ["Work"])
        XCTAssertTrue(first.needsSync)
        XCTAssertTrue(second.needsSync)
    }

    func testRemovesTagCaseInsensitivelyAndKeepsOtherNoteContent() throws {
        let first = makeTransaction(note: "Coffee #Food with #work")
        let second = makeTransaction(note: "Only #food")

        _ = try TransactionBulkEditingService.removeTag("FOOD", from: [first, second], in: context)

        XCTAssertEqual(first.note, "Coffee with #work")
        XCTAssertEqual(first.tags, ["work"])
        XCTAssertEqual(second.note, "Only")
        XCTAssertTrue(second.tags.isEmpty)
    }

    // MARK: - Undo

    func testUndoRestoresPreviousCategoryAndTimestamp() throws {
        let oldCategory = AppCategory(name: "Old", icon: "circle", colorHex: "000000", type: .expense)
        let newCategory = AppCategory(name: "Food", icon: "fork.knife", colorHex: "00AA00", type: .expense)
        context.insert(oldCategory)
        context.insert(newCategory)
        let transaction = makeTransaction(category: oldCategory)

        let mutation = try TransactionBulkEditingService.changeCategory(
            of: [transaction],
            to: newCategory,
            in: context
        )
        XCTAssertEqual(transaction.category?.id, newCategory.id)

        try mutation.revert(in: context)

        XCTAssertEqual(transaction.category?.id, oldCategory.id)
        XCTAssertEqual(transaction.updatedAt, Date(timeIntervalSince1970: 1))
        XCTAssertTrue(transaction.needsSync)
    }

    func testUndoRestoresNoteAndCachedTags() throws {
        let transaction = makeTransaction(note: "Coffee #Work")

        let mutation = try TransactionBulkEditingService.removeTag("work", from: [transaction], in: context)
        XCTAssertEqual(transaction.note, "Coffee")

        try mutation.revert(in: context)

        XCTAssertEqual(transaction.note, "Coffee #Work")
        XCTAssertEqual(transaction.tags, ["Work"])
    }

    // MARK: - Reports inclusion

    func testTogglesExclusionAndUndoRestoresPerTransactionValues() throws {
        let alreadyExcluded = makeTransaction()
        alreadyExcluded.excludeFromReports = true
        let included = makeTransaction()

        let mutation = try TransactionBulkEditingService.setExcludedFromReports(
            true,
            for: [alreadyExcluded, included],
            in: context
        )
        XCTAssertEqual(mutation.changedCount, 2)
        XCTAssertTrue(included.excludeFromReports)

        try mutation.revert(in: context)

        XCTAssertTrue(alreadyExcluded.excludeFromReports)
        XCTAssertFalse(included.excludeFromReports)
    }

    func testAllExcludedFromReportsIgnoresTombstones() throws {
        let excluded = makeTransaction()
        excluded.excludeFromReports = true
        let tombstoned = makeTransaction()
        tombstoned.deletedAt = Date()

        XCTAssertTrue(TransactionBulkEditingService.allExcludedFromReports([excluded, tombstoned]))
        XCTAssertFalse(TransactionBulkEditingService.allExcludedFromReports([]))
    }

    // MARK: - Wallet move

    func testMovesEligibleTransactionsAndSkipsTransfers() throws {
        let source = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#111111")
        let target = Wallet(name: "Bank", currencyCode: "USD", icon: "building.columns", colorHex: "#222222")
        context.insert(source)
        context.insert(target)

        let expense = makeTransaction()
        expense.sourceWallet = source
        let transfer = makeTransaction(type: .transfer)
        transfer.sourceWallet = source

        let mutation = try TransactionBulkEditingService.move(
            [expense, transfer],
            toWallet: target,
            in: context
        )

        XCTAssertEqual(mutation.changedCount, 1)
        XCTAssertEqual(mutation.skippedCount, 1)
        XCTAssertEqual(expense.sourceWallet?.id, target.id)
        XCTAssertEqual(transfer.sourceWallet?.id, source.id)

        try mutation.revert(in: context)
        XCTAssertEqual(expense.sourceWallet?.id, source.id)
    }

    func testCrossCurrencyMoveRestampsStoredRateAndUndoRestoresIt() throws {
        let source = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#111111")
        let target = Wallet(name: "Riel", currencyCode: "KHR", icon: "banknote", colorHex: "#222222")
        context.insert(source)
        context.insert(target)

        let expense = makeTransaction()
        expense.sourceWallet = source
        expense.storedRate = 1
        expense.exchangeRate = 1

        let mutation = try TransactionBulkEditingService.move([expense], toWallet: target, in: context)

        XCTAssertNotEqual(expense.storedRate, 1)
        XCTAssertEqual(expense.storedRate, expense.exchangeRate)
        XCTAssertEqual(expense.currencyCode, "USD", "the recorded amount must not be rewritten")

        try mutation.revert(in: context)

        XCTAssertEqual(expense.storedRate, 1)
        XCTAssertEqual(expense.exchangeRate, 1)
    }

    func testMoveThrowsWhenNothingIsEligible() throws {
        let target = Wallet(name: "Bank", currencyCode: "USD", icon: "building.columns", colorHex: "#222222")
        context.insert(target)
        let transfer = makeTransaction(type: .transfer)

        XCTAssertThrowsError(
            try TransactionBulkEditingService.move([transfer], toWallet: target, in: context)
        ) { error in
            XCTAssertEqual(error as? TransactionBulkEditingService.BulkEditError, .noEligibleTransactions)
        }
    }

    // MARK: - Location

    func testSetsLocationOnTransactionsWithoutOneAndUndoRemovesIt() throws {
        let transaction = makeTransaction()
        let selection = TransactionLocationSelection(
            displayName: "Central Market",
            latitude: 11.5694,
            longitude: 104.9211,
            source: .mapSearch
        )

        let mutation = try TransactionBulkEditingService.setLocation(
            selection,
            for: [transaction],
            in: context
        )

        XCTAssertEqual(transaction.location?.displayName, "Central Market")

        try mutation.revert(in: context)

        XCTAssertNil(transaction.location)
    }

    /// The relationship is `.cascade`, so an in-place update is what keeps the
    /// old row from being orphaned in the store.
    func testReusesExistingLocationRowInsteadOfReplacingIt() throws {
        let transaction = makeTransaction()
        let original = TransactionLocation(
            displayName: "Home",
            latitude: 11.5,
            longitude: 104.9,
            source: .manual
        )
        context.insert(original)
        transaction.location = original
        let originalID = original.id

        let mutation = try TransactionBulkEditingService.setLocation(
            TransactionLocationSelection(
                displayName: "Office",
                latitude: 11.6,
                longitude: 105.0,
                source: .mapTap
            ),
            for: [transaction],
            in: context
        )

        XCTAssertEqual(transaction.location?.id, originalID)
        XCTAssertEqual(transaction.location?.displayName, "Office")

        try mutation.revert(in: context)

        XCTAssertEqual(transaction.location?.id, originalID)
        XCTAssertEqual(transaction.location?.displayName, "Home")
    }

    func testClearingLocationTombstonesTheRowAndUndoRestoresIt() throws {
        let transaction = makeTransaction()
        let location = TransactionLocation(
            displayName: "Home",
            latitude: 11.5,
            longitude: 104.9,
            source: .manual
        )
        context.insert(location)
        transaction.location = location

        let mutation = try TransactionBulkEditingService.setLocation(nil, for: [transaction], in: context)

        XCTAssertNil(transaction.location)
        XCTAssertNotNil(location.deletedAt)

        try mutation.revert(in: context)

        XCTAssertEqual(transaction.location?.id, location.id)
        XCTAssertNil(location.deletedAt)
    }

    func testClearingLocationThrowsWhenNothingHasOne() throws {
        let transaction = makeTransaction()

        XCTAssertThrowsError(
            try TransactionBulkEditingService.setLocation(nil, for: [transaction], in: context)
        ) { error in
            XCTAssertEqual(error as? TransactionBulkEditingService.BulkEditError, .noEligibleTransactions)
        }
    }

    // MARK: - Delete

    func testDeletesSelectionAndUndoRestoresIt() throws {
        let first = makeTransaction()
        let second = makeTransaction()

        let mutation = try TransactionBulkEditingService.delete([first, second], in: context)

        XCTAssertEqual(mutation.changedCount, 2)
        XCTAssertNotNil(first.deletedAt)
        XCTAssertNotNil(second.deletedAt)

        try mutation.revert(in: context)

        XCTAssertNil(first.deletedAt)
        XCTAssertNil(second.deletedAt)
        XCTAssertTrue(first.needsSync)
    }

    func testDeleteSkipsDebtAnchorsRatherThanFailingTheBatch() throws {
        let debt = Debt(personName: "Sok", totalAmount: 100, currencyCode: "USD", type: .owedToMe)
        context.insert(debt)
        // `.owedToMe` advances are expenses, so this lone expense becomes the
        // debt's derived `principalTransaction` — i.e. its anchor.
        let anchor = makeTransaction()
        anchor.debt = debt
        let ordinary = makeTransaction()
        XCTAssertTrue(anchor.isDebtAnchor)

        let mutation = try TransactionBulkEditingService.delete([anchor, ordinary], in: context)

        XCTAssertEqual(mutation.changedCount, 1)
        XCTAssertEqual(mutation.skippedCount, 1)
        XCTAssertNil(anchor.deletedAt)
        XCTAssertNotNil(ordinary.deletedAt)
    }

    func testRejectsInvalidTagWithoutMutatingSelection() throws {
        let transaction = makeTransaction(note: "Lunch")

        XCTAssertThrowsError(
            try TransactionBulkEditingService.addTag("two words", to: [transaction], in: context)
        ) { error in
            XCTAssertEqual(error as? TransactionBulkEditingService.BulkEditError, .invalidTag)
        }
        XCTAssertEqual(transaction.note, "Lunch")
        XCTAssertTrue(transaction.tags.isEmpty)
        XCTAssertFalse(transaction.needsSync)
    }
}

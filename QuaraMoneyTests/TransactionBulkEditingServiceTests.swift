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

        try TransactionBulkEditingService.changeCategory(of: [first, second], to: newCategory, in: context)

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

        try TransactionBulkEditingService.addTag("#work", to: [first, second], in: context)

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

        try TransactionBulkEditingService.removeTag("FOOD", from: [first, second], in: context)

        XCTAssertEqual(first.note, "Coffee with #work")
        XCTAssertEqual(first.tags, ["work"])
        XCTAssertEqual(second.note, "Only")
        XCTAssertTrue(second.tags.isEmpty)
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

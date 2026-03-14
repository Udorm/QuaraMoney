import XCTest
@testable import QuaraMoney

final class ModelValidationTests: XCTestCase {

    // MARK: - Transaction

    func testTransactionValidAmountPasses() {
        let txn = Transaction(amount: 100, currencyCode: "USD", date: Date(), type: .expense)
        XCTAssertTrue(txn.validate().isEmpty)
    }

    func testTransactionZeroAmountFails() {
        let txn = Transaction(amount: 0, currencyCode: "USD", date: Date(), type: .expense)
        let errors = txn.validate()
        XCTAssertTrue(errors.contains(.negativeOrZeroAmount(field: "Amount")))
    }

    func testTransactionNegativeAmountFails() {
        let txn = Transaction(amount: -5, currencyCode: "USD", date: Date(), type: .income)
        XCTAssertTrue(txn.validate().contains(.negativeOrZeroAmount(field: "Amount")))
    }

    func testTransactionInvalidCurrencyFails() {
        let txn = Transaction(amount: 10, currencyCode: "US", date: Date(), type: .expense)
        XCTAssertTrue(txn.validate().contains(.invalidCurrencyCode))
    }

    func testTransactionInvalidExchangeRateFails() {
        let txn = Transaction(amount: 10, currencyCode: "USD", date: Date(), type: .expense, exchangeRate: 0)
        XCTAssertTrue(txn.validate().contains(.invalidExchangeRate))
    }

    // MARK: - Wallet

    func testWalletValidNamePasses() {
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "banknote", colorHex: "#00FF00")
        XCTAssertTrue(wallet.validate().isEmpty)
    }

    func testWalletEmptyNameFails() {
        let wallet = Wallet(name: "   ", currencyCode: "USD", icon: "banknote", colorHex: "#00FF00")
        XCTAssertTrue(wallet.validate().contains(.emptyName(field: "Wallet name")))
    }

    func testWalletInvalidCurrencyFails() {
        let wallet = Wallet(name: "Cash", currencyCode: "ABCD", icon: "banknote", colorHex: "#00FF00")
        XCTAssertTrue(wallet.validate().contains(.invalidCurrencyCode))
    }

    // MARK: - Debt

    func testDebtValidPasses() {
        let debt = Debt(personName: "Alice", totalAmount: 50, currencyCode: "USD", type: .iOwe)
        XCTAssertTrue(debt.validate().isEmpty)
    }

    func testDebtEmptyPersonNameFails() {
        let debt = Debt(personName: "", totalAmount: 50, currencyCode: "USD", type: .owedToMe)
        XCTAssertTrue(debt.validate().contains(.emptyName(field: "Person name")))
    }

    func testDebtZeroAmountFails() {
        let debt = Debt(personName: "Bob", totalAmount: 0, currencyCode: "USD", type: .iOwe)
        XCTAssertTrue(debt.validate().contains(.negativeOrZeroAmount(field: "Total amount")))
    }

    // MARK: - Budget

    func testBudgetValidPasses() {
        let budget = Budget(amountLimit: 500, currencyCode: "USD")
        XCTAssertTrue(budget.validate().isEmpty)
    }

    func testBudgetNegativeLimitFails() {
        let budget = Budget(amountLimit: -10, currencyCode: "USD")
        XCTAssertTrue(budget.validate().contains(.negativeOrZeroAmount(field: "Budget limit")))
    }

    func testBudgetInvalidCurrencyFails() {
        let budget = Budget(amountLimit: 100, currencyCode: "X")
        XCTAssertTrue(budget.validate().contains(.invalidCurrencyCode))
    }
}

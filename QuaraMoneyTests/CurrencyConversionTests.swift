import XCTest
@testable import QuaraMoney

final class CurrencyConversionTests: XCTestCase {

    private let rates: [String: Double] = [
        "USD": 1.0,
        "KHR": 4000.0,
        "EUR": 0.92,
        "JPY": 150.0,
        "THB": 35.0
    ]

    // MARK: - Same currency

    func testConvertSameCurrency() {
        let result = CurrencyManager.convert(amount: Decimal(100), from: "USD", to: "USD", rates: rates)
        XCTAssertEqual(result, Decimal(100))
    }

    // MARK: - USD to other

    func testConvertUSDtoKHR() {
        let result = CurrencyManager.convert(amount: Decimal(1), from: "USD", to: "KHR", rates: rates)
        XCTAssertEqual(result, Decimal(4000))
    }

    func testConvertUSDtoEUR() {
        let result = CurrencyManager.convert(amount: Decimal(100), from: "USD", to: "EUR", rates: rates)
        // Double(0.92) -> Decimal introduces minor precision difference
        let expected = Decimal(100) * Decimal(0.92)
        XCTAssertEqual(result, expected)
    }

    // MARK: - Other to USD

    func testConvertKHRtoUSD() {
        let result = CurrencyManager.convert(amount: Decimal(4000), from: "KHR", to: "USD", rates: rates)
        XCTAssertEqual(result, Decimal(1))
    }

    // MARK: - Cross-currency (non-USD)

    func testConvertKHRtoEUR() {
        // 4000 KHR → 1 USD → 0.92 EUR
        let result = CurrencyManager.convert(amount: Decimal(4000), from: "KHR", to: "EUR", rates: rates)
        // Allow small precision tolerance due to Double -> Decimal conversion
        let expected = Decimal(4000) / Decimal(4000.0) * Decimal(0.92)
        XCTAssertEqual(result, expected)
    }

    // MARK: - Zero amount

    func testConvertZeroAmount() {
        let result = CurrencyManager.convert(amount: Decimal(0), from: "USD", to: "KHR", rates: rates)
        XCTAssertEqual(result, Decimal(0))
    }

    // MARK: - Missing rates (fallback)

    func testFallbackUSDtoKHR() {
        let emptyRates: [String: Double] = [:]
        let result = CurrencyManager.convert(amount: Decimal(1), from: "USD", to: "KHR", rates: emptyRates)
        XCTAssertEqual(result, Decimal(4000))
    }

    func testFallbackKHRtoUSD() {
        let emptyRates: [String: Double] = [:]
        let result = CurrencyManager.convert(amount: Decimal(4000), from: "KHR", to: "USD", rates: emptyRates)
        XCTAssertEqual(result, Decimal(1))
    }

    func testFallbackUnknownCurrencyReturnsOriginal() {
        let emptyRates: [String: Double] = [:]
        let result = CurrencyManager.convert(amount: Decimal(100), from: "XYZ", to: "ABC", rates: emptyRates)
        XCTAssertEqual(result, Decimal(100))
    }
}

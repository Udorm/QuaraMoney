import XCTest
@testable import QuaraMoney

final class MoneyMinorUnitConverterTests: XCTestCase {

    // MARK: - fractionDigits

    func testFractionDigitsUSD() {
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "USD"), 2)
    }

    func testFractionDigitsKHR() {
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "KHR"), 2)
    }

    func testFractionDigitsJPY() {
        // JPY has 0 fraction digits
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "JPY"), 0)
    }

    func testFractionDigitsEUR() {
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "EUR"), 2)
    }

    // MARK: - toMinorUnits

    func testToMinorUnitsUSD() {
        let result = MoneyMinorUnitConverter.toMinorUnits(Decimal(string: "12.34")!, currencyCode: "USD")
        XCTAssertEqual(result, 1234)
    }

    func testToMinorUnitsWholeNumber() {
        let result = MoneyMinorUnitConverter.toMinorUnits(Decimal(100), currencyCode: "USD")
        XCTAssertEqual(result, 10000)
    }

    func testToMinorUnitsZero() {
        let result = MoneyMinorUnitConverter.toMinorUnits(Decimal(0), currencyCode: "USD")
        XCTAssertEqual(result, 0)
    }

    func testToMinorUnitsJPY() {
        // JPY has 0 fraction digits, so 100 JPY = 100 minor units
        let result = MoneyMinorUnitConverter.toMinorUnits(Decimal(100), currencyCode: "JPY")
        XCTAssertEqual(result, 100)
    }

    func testToMinorUnitsLargeAmount() {
        let result = MoneyMinorUnitConverter.toMinorUnits(Decimal(string: "999999.99")!, currencyCode: "USD")
        XCTAssertEqual(result, 99999999)
    }

    // MARK: - fromMinorUnits

    func testFromMinorUnitsUSD() {
        let result = MoneyMinorUnitConverter.fromMinorUnits(1234, currencyCode: "USD")
        XCTAssertEqual(result, Decimal(string: "12.34"))
    }

    func testFromMinorUnitsZero() {
        let result = MoneyMinorUnitConverter.fromMinorUnits(0, currencyCode: "USD")
        XCTAssertEqual(result, Decimal(0))
    }

    func testFromMinorUnitsJPY() {
        let result = MoneyMinorUnitConverter.fromMinorUnits(100, currencyCode: "JPY")
        XCTAssertEqual(result, Decimal(100))
    }

    // MARK: - Round-trip

    func testRoundTripUSD() {
        let original = Decimal(string: "42.50")!
        let minor = MoneyMinorUnitConverter.toMinorUnits(original, currencyCode: "USD")
        let back = MoneyMinorUnitConverter.fromMinorUnits(minor, currencyCode: "USD")
        XCTAssertEqual(original, back)
    }

    func testRoundTripJPY() {
        let original = Decimal(500)
        let minor = MoneyMinorUnitConverter.toMinorUnits(original, currencyCode: "JPY")
        let back = MoneyMinorUnitConverter.fromMinorUnits(minor, currencyCode: "JPY")
        XCTAssertEqual(original, back)
    }

    // MARK: - Non-2-digit currencies (regression guard for the format/ledger mismatch)

    func testFractionDigitsZeroDigitCurrencies() {
        // VND and CLP have 0 ISO minor-unit digits.
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "VND"), 0)
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "CLP"), 0)
    }

    func testFractionDigitsThreeDigitCurrencies() {
        // KWD and BHD have 3 ISO minor-unit digits.
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "KWD"), 3)
        XCTAssertEqual(MoneyMinorUnitConverter.fractionDigits(for: "BHD"), 3)
    }

    func testToMinorUnitsVND() {
        // 0 digits -> minor units equal the major amount.
        let result = MoneyMinorUnitConverter.toMinorUnits(Decimal(25000), currencyCode: "VND")
        XCTAssertEqual(result, 25000)
    }

    func testToMinorUnitsKWD() {
        // 3 digits -> 1.234 KWD = 1234 minor units.
        let result = MoneyMinorUnitConverter.toMinorUnits(Decimal(string: "1.234")!, currencyCode: "KWD")
        XCTAssertEqual(result, 1234)
    }

    func testRoundTripVND() {
        let original = Decimal(25000)
        let minor = MoneyMinorUnitConverter.toMinorUnits(original, currencyCode: "VND")
        XCTAssertEqual(MoneyMinorUnitConverter.fromMinorUnits(minor, currencyCode: "VND"), original)
    }

    func testRoundTripKWD() {
        let original = Decimal(string: "1.234")!
        let minor = MoneyMinorUnitConverter.toMinorUnits(original, currencyCode: "KWD")
        XCTAssertEqual(MoneyMinorUnitConverter.fromMinorUnits(minor, currencyCode: "KWD"), original)
    }

    // MARK: - Formatting matches ledger digits (D1)

    func testFormattedMinorAmountMatchesLedgerDigits() {
        // 1234 minor units in KWD (3 digits) must read as 1.234, not 12.34.
        let kwd = Int64(1234).formattedMinorAmount(for: "KWD")
        XCTAssertTrue(kwd.contains("1.234"), "KWD minor formatting drifted: \(kwd)")

        // 25000 minor units in VND (0 digits) must read as 25,000, not 250.00.
        let vnd = Int64(25000).formattedMinorAmount(for: "VND")
        XCTAssertTrue(vnd.contains("25,000") || vnd.contains("25000"), "VND minor formatting drifted: \(vnd)")
    }
}

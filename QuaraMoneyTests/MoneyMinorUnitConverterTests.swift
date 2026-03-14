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
}

import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class SplitExpenseServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

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

    // MARK: - URL Generation & Decoding Round Trip

    func testPayloadEncodingAndDecodingRoundTrip() {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let location = SharedExpenseLocation(
            displayName: "Brown Coffee BKK",
            fullAddress: "Street 51, Phnom Penh, Cambodia",
            shortAddress: "Street 51",
            latitude: 11.5564,
            longitude: 104.9282,
            locality: "Phnom Penh",
            countryCode: "KH"
        )
        let payload = SharedExpensePayload(
            version: 1,
            originalAmount: Decimal(string: "45.50")!,
            splitAmount: Decimal(string: "22.75")!,
            currencyCode: "USD",
            categoryKey: "food_drink",
            categoryName: "Food & Drink",
            note: "Brown Coffee with Bob",
            date: fixedDate,
            splitCount: 2,
            isCustomSplit: false,
            location: location
        )

        guard let url = SplitExpenseService.generateURL(for: payload) else {
            XCTFail("Failed to generate URL for payload")
            return
        }

        XCTAssertTrue(SplitExpenseService.canHandle(url))

        guard let decoded = SplitExpenseService.decodePayload(from: url) else {
            XCTFail("Failed to decode payload from URL: \(url)")
            return
        }

        XCTAssertEqual(decoded.originalAmount, Decimal(string: "45.50"))
        XCTAssertEqual(decoded.splitAmount, Decimal(string: "22.75"))
        XCTAssertEqual(decoded.currencyCode, "USD")
        XCTAssertEqual(decoded.categoryKey, "food_drink")
        XCTAssertEqual(decoded.categoryName, "Food & Drink")
        XCTAssertEqual(decoded.note, "Brown Coffee with Bob")
        XCTAssertEqual(decoded.splitCount, 2)
        XCTAssertFalse(decoded.isCustomSplit)
        XCTAssertNotNil(decoded.location)
        XCTAssertEqual(decoded.location?.displayName, "Brown Coffee BKK")
        XCTAssertEqual(decoded.location?.latitude, 11.5564)
        XCTAssertEqual(decoded.location?.longitude, 104.9282)
    }

    func testDecodeFallbackFromQueryParameters() {
        let urlString = "quaramoney://split?amount=15.00&orig=30.00&cur=USD&cat=food_drink&note=Dinner&count=2"
        guard let url = URL(string: urlString) else {
            XCTFail("Invalid test URL")
            return
        }

        XCTAssertTrue(SplitExpenseService.canHandle(url))

        guard let decoded = SplitExpenseService.decodePayload(from: url) else {
            XCTFail("Failed to decode payload from query params")
            return
        }

        XCTAssertEqual(decoded.splitAmount, Decimal(15))
        XCTAssertEqual(decoded.originalAmount, Decimal(30))
        XCTAssertEqual(decoded.currencyCode, "USD")
        XCTAssertEqual(decoded.categoryKey, "food_drink")
        XCTAssertEqual(decoded.note, "Dinner")
        XCTAssertEqual(decoded.splitCount, 2)
    }

    func testCannotHandleNonSplitURLs() {
        let authURL = URL(string: "quaramoney://auth-callback?code=xyz")!
        let webURL = URL(string: "https://example.com/split")!

        XCTAssertFalse(SplitExpenseService.canHandle(authURL))
        XCTAssertFalse(SplitExpenseService.canHandle(webURL))
        XCTAssertNil(SplitExpenseService.decodePayload(from: authURL))
        XCTAssertNil(SplitExpenseService.decodePayload(from: webURL))
    }

    // MARK: - Split Calculation

    func testCalculateEqualSplitUSD() {
        // $20 / 2 = $10.00
        let split2 = SplitExpenseService.calculateEqualSplit(
            totalAmount: Decimal(20),
            peopleCount: 2,
            currencyCode: "USD"
        )
        XCTAssertEqual(split2, Decimal(10))

        // $10 / 3 = $3.33
        let split3 = SplitExpenseService.calculateEqualSplit(
            totalAmount: Decimal(10),
            peopleCount: 3,
            currencyCode: "USD"
        )
        XCTAssertEqual(split3, Decimal(string: "3.33"))

        // $100 / 4 = $25.00
        let split4 = SplitExpenseService.calculateEqualSplit(
            totalAmount: Decimal(100),
            peopleCount: 4,
            currencyCode: "USD"
        )
        XCTAssertEqual(split4, Decimal(25))
    }

    func testCalculateEqualSplitKHR() {
        // 40,000 / 2 = 20,000
        let splitKHR = SplitExpenseService.calculateEqualSplit(
            totalAmount: Decimal(40000),
            peopleCount: 2,
            currencyCode: "KHR"
        )
        XCTAssertEqual(splitKHR, Decimal(20000))

        // 10,000 / 3 = 3333 (rounded to nearest integer for KHR)
        let splitKHR3 = SplitExpenseService.calculateEqualSplit(
            totalAmount: Decimal(10000),
            peopleCount: 3,
            currencyCode: "KHR"
        )
        XCTAssertEqual(splitKHR3, Decimal(3333))
    }

    func testCalculateEqualSplitEdgeCases() {
        let zero = SplitExpenseService.calculateEqualSplit(totalAmount: 0, peopleCount: 2, currencyCode: "USD")
        XCTAssertEqual(zero, 0)

        let invalidCount = SplitExpenseService.calculateEqualSplit(totalAmount: 50, peopleCount: 0, currencyCode: "USD")
        XCTAssertEqual(invalidCount, 50)
    }

    // MARK: - Category Resolution

    func testResolveCategoryWithCanonicalKey() {
        let payload = SharedExpensePayload(
            originalAmount: Decimal(20),
            splitAmount: Decimal(10),
            currencyCode: "USD",
            categoryKey: "food_drink",
            categoryName: "Food & Drink"
        )

        let category = SplitExpenseService.resolveCategory(for: payload, in: context)
        XCTAssertNotNil(category)
        XCTAssertEqual(category?.canonicalKey, "food_drink")
        XCTAssertEqual(category?.type, .expense)
    }

    func testResolveCategoryWithCustomName() {
        let customCat = Category(name: "Special Dining", icon: "fork.knife", colorHex: "#FF5722", type: .expense)
        context.insert(customCat)

        let payload = SharedExpensePayload(
            originalAmount: Decimal(20),
            splitAmount: Decimal(10),
            currencyCode: "USD",
            categoryKey: nil,
            categoryName: "Special Dining"
        )

        let category = SplitExpenseService.resolveCategory(for: payload, in: context)
        XCTAssertNotNil(category)
        XCTAssertEqual(category?.name, "Special Dining")
    }

    func testResolveCategoryFallback() {
        let payload = SharedExpensePayload(
            originalAmount: Decimal(20),
            splitAmount: Decimal(10),
            currencyCode: "USD",
            categoryKey: "non_existent_key_xyz",
            categoryName: "NonExistentName"
        )

        let category = SplitExpenseService.resolveCategory(for: payload, in: context)
        XCTAssertNotNil(category)
        XCTAssertEqual(category?.type, .expense)
    }

    // MARK: - Full Amount & Share Text Tests

    func testFullAmountPayloadEncodingAndDecodingRoundTrip() {
        let payload = SharedExpensePayload(
            version: 1,
            originalAmount: Decimal(50),
            splitAmount: Decimal(50),
            currencyCode: "USD",
            categoryKey: "food_drink",
            categoryName: "Dinner",
            note: "Paid for dinner",
            date: Date(timeIntervalSince1970: 1700000000),
            splitCount: 1,
            isCustomSplit: false
        )

        guard let url = SplitExpenseService.generateURL(for: payload) else {
            XCTFail("Failed to generate URL for full amount payload")
            return
        }

        guard let decoded = SplitExpenseService.decodePayload(from: url) else {
            XCTFail("Failed to decode payload from URL: \(url)")
            return
        }

        XCTAssertEqual(decoded.originalAmount, Decimal(50))
        XCTAssertEqual(decoded.splitAmount, Decimal(50))
        XCTAssertEqual(decoded.splitCount, 1)
        XCTAssertFalse(decoded.isCustomSplit)
    }

    func testShareTextFormattingSplitVsFullAmount() {
        let deepLink = URL(string: "quaramoney://split?data=abc")!

        // Split in half
        let splitPayload = SharedExpensePayload(
            originalAmount: Decimal(40),
            splitAmount: Decimal(20),
            currencyCode: "USD",
            note: "Coffee",
            splitCount: 2
        )
        let splitText = SplitExpenseService.generateShareText(for: splitPayload, deepLink: deepLink)
        XCTAssertTrue(splitText.contains("Coffee"))
        XCTAssertTrue(splitText.contains(deepLink.absoluteString))

        // Full amount (not split)
        let fullPayload = SharedExpensePayload(
            originalAmount: Decimal(40),
            splitAmount: Decimal(40),
            currencyCode: "USD",
            note: "Coffee",
            splitCount: 1
        )
        let fullText = SplitExpenseService.generateShareText(for: fullPayload, deepLink: deepLink)
        XCTAssertTrue(fullText.contains("Coffee"))
        XCTAssertTrue(fullText.contains(deepLink.absoluteString))
    }

    func testCalculateEqualSplitSinglePerson() {
        let split1 = SplitExpenseService.calculateEqualSplit(
            totalAmount: Decimal(100),
            peopleCount: 1,
            currencyCode: "USD"
        )
        XCTAssertEqual(split1, Decimal(100))
    }
}

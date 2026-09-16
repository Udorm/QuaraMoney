import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class TransactionProcessorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private let rates: [String: Double] = [
        "USD": 1.0,
        "KHR": 4000.0,
        "EUR": 0.92
    ]

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

    private func makeWallet(name: String = "Test Wallet", currency: String = "USD") -> Wallet {
        let wallet = Wallet(name: name, currencyCode: currency, icon: "wallet.pass", colorHex: "#007AFF")
        context.insert(wallet)
        return wallet
    }

    private func makeTransaction(
        amount: Decimal,
        currency: String = "USD",
        type: TransactionType = .expense,
        date: Date = Date(),
        wallet: Wallet? = nil,
        excludeFromReports: Bool = false
    ) -> Transaction {
        let txn = Transaction(amount: amount, currencyCode: currency, date: date, type: type)
        txn.sourceWallet = wallet
        txn.excludeFromReports = excludeFromReports
        context.insert(txn)
        return txn
    }

    // MARK: - calculateTotals

    func testCalculateTotalsIncomesAndExpenses() {
        let wallet = makeWallet()
        let income = makeTransaction(amount: 1000, type: .income, wallet: wallet)
        let expense = makeTransaction(amount: 300, type: .expense, wallet: wallet)

        let totals = TransactionProcessor.calculateTotals(
            [income, expense],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(totals.income, Decimal(1000))
        XCTAssertEqual(totals.expense, Decimal(300))
    }

    func testCalculateTotalsExcludesReports() {
        let wallet = makeWallet()
        let included = makeTransaction(amount: 500, type: .expense, wallet: wallet)
        let excluded = makeTransaction(amount: 200, type: .expense, wallet: wallet, excludeFromReports: true)

        let totals = TransactionProcessor.calculateTotals(
            [included, excluded],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(totals.expense, Decimal(500))
    }

    func testCalculateTotalsTransfersAreNeutral() {
        let wallet = makeWallet()
        let transfer = makeTransaction(amount: 1000, type: .transfer, wallet: wallet)

        let totals = TransactionProcessor.calculateTotals(
            [transfer],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(totals.income, Decimal(0))
        XCTAssertEqual(totals.expense, Decimal(0))
    }

    func testCalculateTotalsMultiCurrency() {
        let wallet = makeWallet()
        let usdExpense = makeTransaction(amount: 100, currency: "USD", type: .expense, wallet: wallet)
        let khrExpense = makeTransaction(amount: 400000, currency: "KHR", type: .expense, wallet: wallet)

        let totals = TransactionProcessor.calculateTotals(
            [usdExpense, khrExpense],
            rates: rates,
            targetCurrency: "USD"
        )

        // 100 USD + 400000 KHR (= 100 USD at rate 4000) = 200 USD
        XCTAssertEqual(totals.expense, Decimal(200))
    }

    // MARK: - groupByDayObjects

    func testGroupByDaySeparatesDays() {
        let wallet = makeWallet()
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let txn1 = makeTransaction(amount: 100, type: .expense, date: today, wallet: wallet)
        let txn2 = makeTransaction(amount: 200, type: .expense, date: yesterday, wallet: wallet)

        let sections = TransactionProcessor.groupByDayObjects(
            [txn1, txn2],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(sections.count, 2)
    }

    func testGroupByDaySameDayGrouped() {
        let wallet = makeWallet()
        let today = Date()

        let txn1 = makeTransaction(amount: 100, type: .expense, date: today, wallet: wallet)
        let txn2 = makeTransaction(amount: 200, type: .income, date: today, wallet: wallet)

        let sections = TransactionProcessor.groupByDayObjects(
            [txn1, txn2],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.transactions.count, 2)
    }

    func testGroupByDayEmptyTransactions() {
        let sections = TransactionProcessor.groupByDayObjects(
            [],
            rates: rates,
            targetCurrency: "USD"
        )

        XCTAssertTrue(sections.isEmpty)
    }

    func testCalculateTotalExcludesReports() {
        let wallet = makeWallet()
        let t1 = makeTransaction(amount: 100, type: .expense, wallet: wallet)
        let t2 = makeTransaction(amount: 50, type: .expense, wallet: wallet, excludeFromReports: true)
        let t3 = makeTransaction(amount: 200, type: .income, wallet: wallet)
        
        // Without type filter: sums all included transactions
        let totalAll = TransactionProcessor.calculateTotal(
            [t1, t2, t3],
            rates: rates,
            targetCurrency: "USD"
        )
        // 100 + 200 = 300 (t2 excluded)
        XCTAssertEqual(totalAll, Decimal(300))
    }

    func testCalculateTotalWithTypeFilters() {
        let wallet = makeWallet()
        let t1 = makeTransaction(amount: 100, type: .expense, wallet: wallet)
        let t2 = makeTransaction(amount: 50, type: .expense, wallet: wallet, excludeFromReports: true)
        let t3 = makeTransaction(amount: 200, type: .income, wallet: wallet)
        let t4 = makeTransaction(amount: 300, type: .income, wallet: wallet, excludeFromReports: true)
        
        let totalExpense = TransactionProcessor.calculateTotal(
            [t1, t2, t3, t4],
            rates: rates,
            targetCurrency: "USD",
            typeFilter: .expense
        )
        // Only t1 = 100 (t2 is excluded from reports)
        XCTAssertEqual(totalExpense, Decimal(100))
        
        let totalIncome = TransactionProcessor.calculateTotal(
            [t1, t2, t3, t4],
            rates: rates,
            targetCurrency: "USD",
            typeFilter: .income
        )
        // Only t3 = 200 (t4 is excluded from reports)
        XCTAssertEqual(totalIncome, Decimal(200))
    }

    func testCalculateTotalWithTransfersAndAdjustments() {
        let wallet = makeWallet()
        let transfer1 = makeTransaction(amount: 500, type: .transfer, wallet: wallet)
        let transfer2 = makeTransaction(amount: 250, type: .transfer, wallet: wallet, excludeFromReports: true)
        let adjustment1 = makeTransaction(amount: 150, type: .adjustment, wallet: wallet)
        let adjustment2 = makeTransaction(amount: 75, type: .adjustment, wallet: wallet, excludeFromReports: true)
        
        let totalTransfer = TransactionProcessor.calculateTotal(
            [transfer1, transfer2],
            rates: rates,
            targetCurrency: "USD",
            typeFilter: .transfer
        )
        XCTAssertEqual(totalTransfer, Decimal(500))
        
        let totalAdjustment = TransactionProcessor.calculateTotal(
            [adjustment1, adjustment2],
            rates: rates,
            targetCurrency: "USD",
            typeFilter: .adjustment
        )
        XCTAssertEqual(totalAdjustment, Decimal(150))
    }
    
    // MARK: - calculatePreviousPeriodCumulative

    func testCalculatePreviousPeriodCumulative_withFullMonth() {
        let wallet = makeWallet()
        let calendar = Calendar.current
        
        // Target range: May 2026 (May 1 to May 31)
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31))!
        
        // Previous period (April 2026): 30 days. Let's add $30 on April 15th
        let april15 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        _ = makeTransaction(amount: 30, type: .expense, date: april15, wallet: wallet)
        
        let refLine = TransactionProcessor.calculatePreviousPeriodCumulative(
            context: context,
            startDate: startDate,
            endDate: endDate,
            walletId: wallet.id,
            rates: rates,
            targetCurrency: "USD"
        )
        
        // Current month (May) has 31 days. So refLine count should be 31.
        XCTAssertEqual(refLine.count, 31)
        
        // Check cumulative values:
        // Day 1 to 14 in April (indices 0..13) has 0 expense, so cumulative amount is 0
        XCTAssertEqual(refLine[0], Decimal(0))
        XCTAssertEqual(refLine[13], Decimal(0))
        
        // Day 15 to 30 in April (indices 14..29) has $30 expense
        XCTAssertEqual(refLine[14], Decimal(30))
        XCTAssertEqual(refLine[29], Decimal(30))
        
        // Day 31 (index 30) should align/pad to the last index of the ref period (index 29) -> $30
        XCTAssertEqual(refLine[30], Decimal(30))
    }
    
    func testCalculatePreviousPeriodCumulative_withCustomDateRange() {
        let wallet = makeWallet()
        let calendar = Calendar.current
        
        // Target range: May 10 to May 20 (11 days)
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20))!
        
        // Previous period range: April 10 to April 20 (11 days).
        // Let's add $15 expense on April 12th, and $25 on April 18th.
        let april12 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 12))!
        let april18 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 18))!
        _ = makeTransaction(amount: 15, type: .expense, date: april12, wallet: wallet)
        _ = makeTransaction(amount: 25, type: .expense, date: april18, wallet: wallet)
        
        let refLine = TransactionProcessor.calculatePreviousPeriodCumulative(
            context: context,
            startDate: startDate,
            endDate: endDate,
            walletId: wallet.id,
            rates: rates,
            targetCurrency: "USD"
        )
        
        // Current range has 11 days.
        XCTAssertEqual(refLine.count, 11)
        
        // April 10..11 (indices 0..1): 0
        XCTAssertEqual(refLine[0], Decimal(0))
        XCTAssertEqual(refLine[1], Decimal(0))
        
        // April 12..17 (indices 2..7): 15
        XCTAssertEqual(refLine[2], Decimal(15))
        XCTAssertEqual(refLine[7], Decimal(15))
        
        // April 18..20 (indices 8..10): 40 (15 + 25)
        XCTAssertEqual(refLine[8], Decimal(40))
        XCTAssertEqual(refLine[10], Decimal(40))
    }
    
    func testCalculatePreviousPeriodCumulative_withNoPreviousData() {
        let wallet = makeWallet()
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31))!
        
        let refLine = TransactionProcessor.calculatePreviousPeriodCumulative(
            context: context,
            startDate: startDate,
            endDate: endDate,
            walletId: wallet.id,
            rates: rates,
            targetCurrency: "USD"
        )
        
        // May has 31 days. Even with no transactions, it returns 31 zeros (padded cumulative expense line)
        XCTAssertEqual(refLine.count, 31)
        XCTAssertEqual(refLine[0], Decimal(0))
        XCTAssertEqual(refLine[30], Decimal(0))
    }

    // MARK: - Type & category filters

    private func makeCategory(_ name: String, type: TransactionType) -> QuaraMoney.Category {
        let category = QuaraMoney.Category(name: name, icon: "tag", colorHex: "#FF5722", type: type)
        context.insert(category)
        return category
    }

    /// Mid-month in May 2026 so every row lands inside the fetched range.
    private var mayRange: (start: Date, end: Date, day: Date) {
        let calendar = Calendar.current
        return (
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!,
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!,
            calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        )
    }

    private func fetchMay(
        types: Set<TransactionType> = [],
        categoryIds: Set<UUID> = [],
        walletIds: Set<UUID> = []
    ) -> ProcessedTransactionDataID {
        TransactionProcessor.fetchAndProcess(
            context: context,
            startDate: mayRange.start,
            endDate: mayRange.end,
            walletIds: walletIds,
            transactionTypes: types,
            categoryIds: categoryIds,
            rates: rates,
            targetCurrency: "USD"
        )
    }

    func testFetchAndProcess_typeFilterKeepsOnlySelectedTypesAndScopesTotals() throws {
        let wallet = makeWallet()
        let day = mayRange.day
        let expense = makeTransaction(amount: 40, type: .expense, date: day, wallet: wallet)
        let income = makeTransaction(amount: 500, type: .income, date: day, wallet: wallet)
        _ = makeTransaction(amount: 100, type: .transfer, date: day, wallet: wallet)
        try context.save()

        let expenseOnly = fetchMay(types: [.expense])
        XCTAssertEqual(expenseOnly.sortedTransactionIds, [expense.persistentModelID])
        XCTAssertEqual(expenseOnly.expenseTotal, Decimal(40))
        XCTAssertEqual(expenseOnly.incomeTotal, Decimal(0))

        let incomeAndExpense = fetchMay(types: [.income, .expense])
        XCTAssertEqual(
            Set(incomeAndExpense.sortedTransactionIds),
            [expense.persistentModelID, income.persistentModelID]
        )

        XCTAssertEqual(fetchMay().sortedTransactionIds.count, 3, "Empty type set must not constrain")
    }

    func testFetchAndProcess_categoryFilterMatchesSelectedCategoriesAndDropsUncategorized() throws {
        let wallet = makeWallet()
        let day = mayRange.day
        let food = makeCategory("Food", type: .expense)
        let rent = makeCategory("Rent", type: .expense)
        let salary = makeCategory("Salary", type: .income)

        let lunch = makeTransaction(amount: 12, type: .expense, date: day, wallet: wallet)
        lunch.category = food
        let housing = makeTransaction(amount: 300, type: .expense, date: day, wallet: wallet)
        housing.category = rent
        let pay = makeTransaction(amount: 1000, type: .income, date: day, wallet: wallet)
        pay.category = salary
        _ = makeTransaction(amount: 50, type: .transfer, date: day, wallet: wallet)
        try context.save()

        let foodOnly = fetchMay(categoryIds: [food.id])
        XCTAssertEqual(foodOnly.sortedTransactionIds, [lunch.persistentModelID])
        XCTAssertEqual(foodOnly.expenseTotal, Decimal(12))

        // Categories across types are OR-ed within the dimension.
        let foodOrSalary = fetchMay(categoryIds: [food.id, salary.id])
        XCTAssertEqual(Set(foodOrSalary.sortedTransactionIds), [lunch.persistentModelID, pay.persistentModelID])
        XCTAssertEqual(foodOrSalary.incomeTotal, Decimal(1000))
        XCTAssertEqual(foodOrSalary.expenseTotal, Decimal(12))
    }

    func testFetchAndProcess_dimensionsAreAndedTogether() throws {
        let personal = makeWallet(name: "Personal")
        let business = makeWallet(name: "Business")
        let day = mayRange.day
        let food = makeCategory("Food", type: .expense)
        let salary = makeCategory("Salary", type: .income)

        let personalLunch = makeTransaction(amount: 10, type: .expense, date: day, wallet: personal)
        personalLunch.category = food
        let businessLunch = makeTransaction(amount: 25, type: .expense, date: day, wallet: business)
        businessLunch.category = food
        let pay = makeTransaction(amount: 900, type: .income, date: day, wallet: personal)
        pay.category = salary
        try context.save()

        let result = fetchMay(types: [.expense], categoryIds: [food.id, salary.id], walletIds: [personal.id])
        XCTAssertEqual(result.sortedTransactionIds, [personalLunch.persistentModelID])

        // A category constraint with only an uncategorized type selected matches nothing.
        XCTAssertTrue(fetchMay(types: [.transfer], categoryIds: [food.id]).sortedTransactionIds.isEmpty)
    }

    func testFetchAndProcess_filteredDailySectionsOnlyContainMatchingRows() throws {
        let wallet = makeWallet()
        let day = mayRange.day
        let food = makeCategory("Food", type: .expense)
        let lunch = makeTransaction(amount: 8, type: .expense, date: day, wallet: wallet)
        lunch.category = food
        _ = makeTransaction(amount: 200, type: .income, date: day, wallet: wallet)
        try context.save()

        let result = fetchMay(categoryIds: [food.id])
        XCTAssertEqual(result.dailySections.count, 1)
        XCTAssertEqual(result.dailySections.first?.transactionIds, [lunch.persistentModelID])
        XCTAssertEqual(result.dailySections.first?.dailyTotal, Decimal(-8))
    }

    func testCalculatePreviousPeriodCumulative_respectsCategoryAndTypeFilters() throws {
        let wallet = makeWallet()
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let endDate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 31))!
        let april10 = calendar.date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let food = makeCategory("Food", type: .expense)
        let rent = makeCategory("Rent", type: .expense)

        let lunch = makeTransaction(amount: 20, type: .expense, date: april10, wallet: wallet)
        lunch.category = food
        let housing = makeTransaction(amount: 400, type: .expense, date: april10, wallet: wallet)
        housing.category = rent
        try context.save()

        let foodLine = TransactionProcessor.calculatePreviousPeriodCumulative(
            context: context,
            startDate: startDate,
            endDate: endDate,
            walletId: wallet.id,
            categoryIds: [food.id],
            rates: rates,
            targetCurrency: "USD"
        )
        XCTAssertEqual(foodLine.last, Decimal(20))

        let incomeLine = TransactionProcessor.calculatePreviousPeriodCumulative(
            context: context,
            startDate: startDate,
            endDate: endDate,
            walletId: wallet.id,
            transactionTypes: [.income],
            rates: rates,
            targetCurrency: "USD"
        )
        XCTAssertEqual(incomeLine.last, Decimal(0), "An income-only filter has no expense to compare against")
    }

    // MARK: - HomeTransactionFilter

    func testHomeTransactionFilter_selectingEveryTypeCollapsesToAll() {
        var filter = HomeTransactionFilter()
        filter.setTypes(Set(HomeTransactionFilter.selectableTypes))
        XCTAssertTrue(filter.types.isEmpty)
        XCTAssertFalse(filter.isActive)

        filter.setTypes([.expense, .transfer])
        XCTAssertEqual(filter.types, [.expense, .transfer])
        XCTAssertTrue(filter.isActive)
    }

    func testHomeTransactionFilter_categoryTypesFollowSelectedTypes() {
        var filter = HomeTransactionFilter()
        XCTAssertEqual(filter.categoryTypes, [.income, .expense])

        filter.setTypes([.expense, .transfer])
        XCTAssertEqual(filter.categoryTypes, [.expense])

        filter.setTypes([.transfer, .adjustment])
        XCTAssertTrue(filter.categoryTypes.isEmpty)
    }

    func testHomeTransactionFilter_restrictedDropsIdsThatNoLongerResolve() {
        let keptWallet = UUID(), goneWallet = UUID()
        let keptCategory = UUID(), goneCategory = UUID()
        let filter = HomeTransactionFilter(
            walletIds: [keptWallet, goneWallet],
            types: [.expense],
            categoryIds: [keptCategory, goneCategory]
        )

        let restricted = filter.restricted(toWalletIds: [keptWallet], categoryIds: [keptCategory])
        XCTAssertEqual(restricted.walletIds, [keptWallet])
        XCTAssertEqual(restricted.categoryIds, [keptCategory])
        XCTAssertEqual(restricted.types, [.expense])
        XCTAssertEqual(filter.restricted(toWalletIds: [keptWallet, goneWallet], categoryIds: [keptCategory, goneCategory]), filter)
    }
}

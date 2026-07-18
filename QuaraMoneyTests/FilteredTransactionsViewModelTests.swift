import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class FilteredTransactionsViewModelTests: XCTestCase {
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

    func testFetchAndResolveTransactions() async throws {
        let wallet = Wallet(name: "Test Wallet", currencyCode: "USD", icon: "wallet.pass", colorHex: "#007AFF")
        context.insert(wallet)

        let today = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let txn1 = Transaction(amount: Decimal(100), currencyCode: "USD", date: today, type: .expense)
        txn1.sourceWallet = wallet
        context.insert(txn1)

        let txn2 = Transaction(amount: Decimal(200), currencyCode: "USD", date: today.addingTimeInterval(86400 * 2), type: .expense)
        txn2.sourceWallet = wallet
        context.insert(txn2)

        try context.save()

        let config = TransactionFilterConfig(
            title: "Test",
            startDate: start,
            endDate: end,
            walletId: wallet.id,
            walletName: wallet.name,
            dateRangeDescription: "Today"
        )

        let vm = FilteredTransactionsViewModel(config: config)
        vm.configure(modelContext: context)
        vm.setVisible(true)

        // Wait for task to finish loading
        for _ in 0..<100 {
            if !vm.isLoading { break }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.transactions.count, 1)
        XCTAssertEqual(vm.transactions.first?.amount, Decimal(100))
        // Verify they are resolved on the main context
        XCTAssertEqual(vm.transactions.first?.modelContext, context)
    }

    func testDeleteTransactionInvalidatesCaches() async throws {
        let wallet = Wallet(name: "Test Wallet", currencyCode: "USD", icon: "wallet.pass", colorHex: "#007AFF")
        context.insert(wallet)

        let today = Date()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let txn = Transaction(amount: Decimal(100), currencyCode: "USD", date: today, type: .expense)
        txn.sourceWallet = wallet
        context.insert(txn)

        try context.save()

        let config = TransactionFilterConfig(
            title: "Test",
            startDate: start,
            endDate: end,
            walletId: wallet.id,
            walletName: wallet.name,
            dateRangeDescription: "Today"
        )

        let vm = FilteredTransactionsViewModel(config: config)
        vm.configure(modelContext: context)
        vm.setVisible(true)

        // Wait for load
        for _ in 0..<100 {
            if !vm.isLoading { break }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        XCTAssertEqual(vm.transactions.count, 1)
        let txnToDelete = vm.transactions[0]

        // Delete it
        vm.deleteTransaction(txnToDelete)

        // Verify deleted from db
        let fetched = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertTrue(fetched.isEmpty)
    }

    func testDeleteTransactionWithSyncTracker() async throws {
        // Activate mutation tracker
        SyncMutationTracker.start(mainContext: context)
        
        let wallet = Wallet(name: "Test Wallet", currencyCode: "USD", icon: "wallet.pass", colorHex: "#007AFF")
        context.insert(wallet)
        
        let today = Date()
        let txn = Transaction(amount: Decimal(150), currencyCode: "USD", date: today, type: .expense)
        txn.sourceWallet = wallet
        context.insert(txn)
        
        try context.save()
        
        // Clear deletion queue before test delete
        SyncDeletionQueue.clear()
        
        // Act: Modify transaction (marking it changed) and then delete it
        txn.amount = Decimal(200)
        context.delete(txn)
        
        // Assert: Save should succeed without crashing
        XCTAssertNoThrow(try context.save())
        
        // Verify deletion is enqueued
        let queuedDeletions = SyncDeletionQueue.all()
        XCTAssertTrue(queuedDeletions.contains { $0.table == "transactions" && $0.id == txn.id })
    }
}

import SwiftData
import XCTest
@testable import QuaraMoney

@MainActor
final class SavingsWalletTests: XCTestCase {
    func testSavingsWalletRejectsIncomeAndExpenseButAllowsTransfersAndAdjustment() throws {
        let savings = makeSavingsWallet(target: 100)
        let normal = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#000000")

        XCTAssertThrowsError(try WalletLedgerRules.validate(
            type: .income, amount: 10, sourceWallet: savings, destinationWallet: nil
        ))
        XCTAssertThrowsError(try WalletLedgerRules.validate(
            type: .expense, amount: 10, sourceWallet: savings, destinationWallet: nil
        ))
        XCTAssertNoThrow(try WalletLedgerRules.validate(
            type: .transfer, amount: 10, sourceWallet: normal, destinationWallet: savings
        ))
        XCTAssertNoThrow(try WalletLedgerRules.validate(
            type: .transfer, amount: 10, sourceWallet: savings, destinationWallet: normal
        ))
        let secondSavings = makeSavingsWallet(target: 200)
        XCTAssertNoThrow(try WalletLedgerRules.validate(
            type: .transfer, amount: 10, sourceWallet: savings, destinationWallet: secondSavings
        ))
        XCTAssertNoThrow(try WalletLedgerRules.validate(
            type: .adjustment, amount: -10, sourceWallet: savings, destinationWallet: nil
        ))
    }

    func testComputedProgressIsClampedButRemainingAndBalanceStayHonest() {
        let savings = makeSavingsWallet(target: 100)
        let adjustment = makeAdjustment(amount: -25, wallet: savings, date: Date())
        savings.outgoingTransactions = [adjustment]
        savings.invalidateBalanceCache()

        XCTAssertEqual(savings.balance, -25)
        XCTAssertEqual(savings.savingsProgress, 0)
        XCTAssertEqual(savings.savingsRemaining, 125)
        XCTAssertFalse(savings.isSavingsReached)
    }

    func testSavingsLifecycleLocksKindCurrencyArchiveAndDelete() {
        let savings = makeSavingsWallet(target: 100)
        let adjustment = makeAdjustment(amount: 20, wallet: savings, date: Date())
        savings.outgoingTransactions = [adjustment]
        savings.invalidateBalanceCache()

        XCTAssertThrowsError(try WalletLedgerRules.validateWalletUpdate(
            wallet: savings,
            proposedKind: .normal,
            proposedCurrencyCode: "USD",
            proposedTargetAmount: 100,
            proposedArchived: false
        ))
        XCTAssertThrowsError(try WalletLedgerRules.validateWalletUpdate(
            wallet: savings,
            proposedKind: .savings,
            proposedCurrencyCode: "KHR",
            proposedTargetAmount: 100,
            proposedArchived: false
        ))
        XCTAssertThrowsError(try WalletLedgerRules.validateWalletUpdate(
            wallet: savings,
            proposedKind: .savings,
            proposedCurrencyCode: "USD",
            proposedTargetAmount: 100,
            proposedArchived: true
        ))
        XCTAssertThrowsError(try WalletLedgerRules.validateWalletDeletion(savings))
    }

    func testDeletingZeroBalanceSavingsWalletRetainsCounterpartHistory() throws {
        let source = Wallet(name: "Source", currencyCode: "USD", icon: "wallet.pass", colorHex: "#111111")
        let destination = Wallet(name: "Destination", currencyCode: "USD", icon: "wallet.pass", colorHex: "#222222")
        let savings = makeSavingsWallet(target: 100)
        let contribution = Transaction(amount: 25, currencyCode: "USD", date: Date(), type: .transfer)
        contribution.sourceWallet = source
        contribution.destinationWallet = savings
        contribution.storedRate = 1
        let withdrawal = Transaction(amount: 25, currencyCode: "USD", date: Date(), type: .transfer)
        withdrawal.sourceWallet = savings
        withdrawal.destinationWallet = destination
        withdrawal.storedRate = 1
        savings.incomingTransactions = [contribution]
        savings.outgoingTransactions = [withdrawal]
        savings.invalidateBalanceCache()

        XCTAssertEqual(savings.balance, 0)
        try SoftDeleteService.deleteWallet(savings, strategy: .deleteTransactions)

        XCTAssertNotNil(savings.deletedAt)
        XCTAssertNil(contribution.deletedAt)
        XCTAssertNil(withdrawal.deletedAt)
        XCTAssertEqual(contribution.destinationWallet?.id, savings.id)
        XCTAssertEqual(withdrawal.sourceWallet?.id, savings.id)
    }

    func testWalletBalanceStoreSubtotalsSumToNetWorth() async throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let spendable = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#111111")
        let savings = makeSavingsWallet(target: 100)
        context.insert(spendable)
        context.insert(savings)
        context.insert(makeAdjustment(amount: 80, wallet: spendable, date: Date()))
        context.insert(makeAdjustment(amount: 20, wallet: savings, date: Date()))
        try context.save()

        let store = WalletBalanceStore()
        store.configure(container: container)
        store.refresh()
        for _ in 0..<100 where !store.hasLoaded {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(store.hasLoaded)
        XCTAssertEqual(store.netWorthTotal, store.spendableTotal + store.savingsTotal)
        XCTAssertEqual(store.spendableTotal, 80)
        XCTAssertEqual(store.savingsTotal, 20)
    }

    func testCaseAFlipsDedicatedWalletWithoutChangingNetWorth() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let cash = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#111111")
        let dedicated = Wallet(name: "Goal account", currencyCode: "USD", icon: "target", colorHex: "#10B981")
        let goal = SavingsGoal(name: "Emergency", targetAmount: 200, currencyCode: "USD")
        goal.linkedWallet = dedicated
        let rule = RecurringRule(
            name: "Automatic deposit",
            amount: 10,
            currencyCode: "USD",
            frequency: .monthly,
            startDate: Date()
        )
        rule.wallet = dedicated
        let contribution = makeTransfer(amount: 75, source: cash, destination: dedicated, goal: goal)
        context.insert(cash)
        context.insert(dedicated)
        context.insert(goal)
        context.insert(rule)
        context.insert(contribution)
        try context.save()

        let result = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1],
            netWorthCurrency: "USD"
        )

        dedicated.invalidateBalanceCache()
        cash.invalidateBalanceCache()
        XCTAssertTrue(result.changed)
        XCTAssertEqual(dedicated.kind, .savings)
        XCTAssertEqual(dedicated.balance, 75)
        XCTAssertEqual(cash.balance + dedicated.balance, 0)
        XCTAssertNil(contribution.savingsGoal)
        XCTAssertNotNil(dedicated.legacyMigrationCompletedAt)
        XCTAssertNotNil(goal.deletedAt)
        XCTAssertFalse(rule.isActive)
        XCTAssertEqual(rule.pauseReason, .invalidSavingsWallet)
    }

    func testCaseBRelocatesMoneyWithDatedExcludedAdjustmentsAndIsIdempotent() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let cash = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#111111")
        let shared = Wallet(name: "Shared", currencyCode: "USD", icon: "wallet.pass", colorHex: "#222222")
        let income = Transaction(amount: 100, currencyCode: "USD", date: Date.distantPast, type: .income)
        income.sourceWallet = shared
        let goal = SavingsGoal(name: "Trip", targetAmount: 200, currencyCode: "USD")
        goal.currentAmount = 20
        goal.createdDate = Date(timeIntervalSince1970: 1_000)
        goal.linkedWallet = shared
        let contributionDate = Date(timeIntervalSince1970: 2_000)
        let contribution = makeTransfer(
            amount: 50,
            source: cash,
            destination: shared,
            goal: goal,
            date: contributionDate
        )
        [cash, shared].forEach(context.insert)
        context.insert(income)
        context.insert(goal)
        context.insert(contribution)
        try context.save()

        let result = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1],
            netWorthCurrency: "USD"
        )
        try context.save()

        let savings = try XCTUnwrap(try context.fetch(FetchDescriptor<Wallet>()).first {
            $0.legacySavingsGoalID == goal.id
        })
        [cash, shared, savings].forEach { $0.invalidateBalanceCache() }
        XCTAssertEqual(savings.balance, 70)
        XCTAssertEqual(shared.balance, 100)
        XCTAssertEqual(cash.balance, -50)
        XCTAssertEqual(cash.balance + shared.balance + savings.balance, 120)
        XCTAssertEqual(result.report?.netWorthDelta, 20)

        let migrationRows = try context.fetch(FetchDescriptor<Transaction>()).filter {
            SavingsWalletMigrationService.goalID(from: $0.migrationProvenance) == goal.id
                && $0.type == .adjustment
        }
        XCTAssertEqual(migrationRows.count, 3)
        XCTAssertTrue(migrationRows.allSatisfy(\.excludeFromReports))
        XCTAssertTrue(migrationRows.contains { $0.date == goal.createdDate && $0.sourceWallet?.id == savings.id })
        XCTAssertTrue(migrationRows.contains { $0.date == contributionDate && $0.sourceWallet?.id == savings.id })
        XCTAssertTrue(migrationRows.contains { $0.amount == -50 && $0.sourceWallet?.id == shared.id })

        let second = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1],
            netWorthCurrency: "USD"
        )
        XCTAssertFalse(second.changed)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Wallet>()).filter {
            $0.legacySavingsGoalID == goal.id
        }.count, 1)
    }

    func testCaseBWithdrawalCompensationKeepsNegativeRawBalance() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let cash = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#111111")
        let shared = Wallet(name: "Shared", currencyCode: "USD", icon: "wallet.pass", colorHex: "#222222")
        let goal = SavingsGoal(name: "Reserve", targetAmount: 100, currencyCode: "USD")
        goal.currentAmount = 10
        goal.linkedWallet = shared
        let withdrawal = makeTransfer(amount: 30, source: shared, destination: cash, goal: goal)
        withdrawal.savingsIsWithdrawal = true
        [cash, shared].forEach(context.insert)
        context.insert(goal)
        context.insert(withdrawal)
        try context.save()

        _ = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1],
            netWorthCurrency: "USD"
        )
        let savings = try XCTUnwrap(try context.fetch(FetchDescriptor<Wallet>()).first {
            $0.legacySavingsGoalID == goal.id
        })
        [cash, shared, savings].forEach { $0.invalidateBalanceCache() }
        XCTAssertEqual(savings.balance, -20)
        XCTAssertEqual(shared.balance, 0)
        XCTAssertEqual(cash.balance, 30)
        XCTAssertEqual(cash.balance + shared.balance + savings.balance, 10)
        let compensation = try context.fetch(FetchDescriptor<Transaction>()).first {
            $0.migrationProvenance?.contains(":compensation:") == true
        }
        XCTAssertEqual(compensation?.amount, 30)
    }

    func testIndeterminateGoalIsDeferredWithoutMutation() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let goal = SavingsGoal(name: "Euro", targetAmount: 100, currencyCode: "EUR")
        goal.currentAmount = 10
        goal.startingBalanceCurrencyCode = "XYZ"
        context.insert(goal)
        try context.save()

        let result = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1, "EUR": 1],
            netWorthCurrency: "USD"
        )

        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.report?.deferredGoalIDs, [goal.id])
        XCTAssertNil(goal.deletedAt)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Wallet>()).isEmpty)
    }

    func testMigratedCompletedGoalSeedsCelebrationLatch() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let goal = SavingsGoal(name: "Done", targetAmount: 50, currencyCode: "USD")
        goal.currentAmount = 50
        context.insert(goal)
        try context.save()

        _ = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1],
            netWorthCurrency: "USD"
        )
        let savings = try XCTUnwrap(try context.fetch(FetchDescriptor<Wallet>()).first {
            $0.legacySavingsGoalID == goal.id
        })
        savings.invalidateBalanceCache()
        XCTAssertTrue(savings.isSavingsReached)
        XCTAssertTrue(savings.hasCelebrated)
    }

    func testAdoptsCompletedReplacementWithoutCreatingAnotherWallet() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let goal = SavingsGoal(name: "Cloud goal", targetAmount: 100, currencyCode: "USD")
        let replacement = makeSavingsWallet(target: 100)
        replacement.legacySavingsGoalID = goal.id
        replacement.legacyMigrationCompletedAt = Date()
        context.insert(goal)
        context.insert(replacement)
        try context.save()

        let result = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1],
            netWorthCurrency: "USD"
        )

        XCTAssertTrue(result.changed)
        XCTAssertNotNil(goal.deletedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Wallet>()).filter {
            $0.legacySavingsGoalID == goal.id
        }.count, 1)
    }

    func testFileBackedLegacyFixtureReopensAndConverts() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            "SavingsUpgradeFixture-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        addTeardownBlock {
            let storeURL = configuration.url
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        var seedContainer: ModelContainer? = try ModelContainer(
            for: schema,
            migrationPlan: QuaraMoneySchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let goalID = UUID()
        if let seedContext = seedContainer?.mainContext {
            let goal = SavingsGoal(name: "Disk fixture", targetAmount: 100, currencyCode: "USD")
            goal.id = goalID
            goal.currentAmount = 35
            seedContext.insert(goal)
            try seedContext.save()
        }
        seedContainer = nil

        let reopened = try ModelContainer(
            for: schema,
            migrationPlan: QuaraMoneySchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = reopened.mainContext
        let result = try SavingsWalletMigrationService.run(
            in: context,
            ownerID: nil,
            rates: ["USD": 1],
            netWorthCurrency: "USD"
        )
        let identity = StartupMaintenanceIdentity(
            authUserID: nil,
            localOwnerID: nil,
            authGeneration: 0
        )
        let commit = try XCTUnwrap(StartupMaintenanceGuard.commit(
            context: context,
            expected: identity,
            currentIdentity: { identity }
        ))

        XCTAssertTrue(result.changed)
        XCTAssertTrue(commit.hadChanges)
        let wallet = try XCTUnwrap(try context.fetch(FetchDescriptor<Wallet>()).first {
            $0.legacySavingsGoalID == goalID
        })
        wallet.invalidateBalanceCache()
        XCTAssertEqual(wallet.kind, .savings)
        XCTAssertEqual(wallet.balance, 35)
        XCTAssertEqual(wallet.targetAmount, 100)
    }

    private func makeSavingsWallet(target: Decimal) -> Wallet {
        let wallet = Wallet(name: "Savings", currencyCode: "USD", icon: "target", colorHex: "#10B981")
        wallet.kind = .savings
        wallet.targetAmount = target
        return wallet
    }

    private func makeAdjustment(amount: Decimal, wallet: Wallet, date: Date) -> Transaction {
        let transaction = Transaction(amount: amount, currencyCode: wallet.currencyCode, date: date, type: .adjustment)
        transaction.sourceWallet = wallet
        return transaction
    }

    private func makeTransfer(
        amount: Decimal,
        source: Wallet,
        destination: Wallet,
        goal: SavingsGoal,
        date: Date = Date()
    ) -> Transaction {
        let transaction = Transaction(amount: amount, currencyCode: source.currencyCode, date: date, type: .transfer)
        transaction.sourceWallet = source
        transaction.destinationWallet = destination
        transaction.storedRate = 1
        transaction.savingsGoal = goal
        return transaction
    }
}

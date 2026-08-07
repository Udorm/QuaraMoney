import CryptoKit
import Foundation
import SwiftData

nonisolated struct SavingsWalletMigrationReport: Codable, Equatable, Sendable {
    let ownerID: UUID?
    let createdAt: Date
    var convertedGoalIDs: [UUID]
    var deferredGoalIDs: [UUID]
    var failedGoals: [UUID: String]
    var netWorthDelta: Decimal
    var newlyNegativeWalletIDs: [UUID]
    var acknowledgedAt: Date?
}

nonisolated enum SavingsMigrationReportStore {
    private static let latestKey = "savingsWalletMigration.latest.v1"

    static func reportKey(ownerID: UUID?) -> String {
        "savingsWalletMigration.report.v1.\(ownerID?.uuidString ?? "local")"
    }

    static func save(_ report: SavingsWalletMigrationReport, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        let key = reportKey(ownerID: report.ownerID)
        defaults.set(data, forKey: key)
        defaults.set(key, forKey: latestKey)
    }

    static func latest(defaults: UserDefaults = .standard) -> SavingsWalletMigrationReport? {
        guard let key = defaults.string(forKey: latestKey),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SavingsWalletMigrationReport.self, from: data)
    }

    static func acknowledgeLatest(defaults: UserDefaults = .standard, at date: Date = Date()) {
        guard var report = latest(defaults: defaults) else { return }
        report.acknowledgedAt = date
        save(report, defaults: defaults)
    }
}

struct SavingsWalletMigrationResult: Sendable, Equatable {
    let changed: Bool
    let report: SavingsWalletMigrationReport?
}

/// Converts the retained legacy model into first-class wallets. This runs only
/// from the settled startup-maintenance gate; it is deliberately not a schema
/// migration because conversion is account- and exchange-rate-dependent.
nonisolated enum SavingsWalletMigrationService {
    static func run(
        in context: ModelContext,
        ownerID: UUID?,
        rates: [String: Double],
        netWorthCurrency: String,
        now: Date = Date()
    ) throws -> SavingsWalletMigrationResult {
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>())
            .filter { $0.deletedAt == nil }
        guard !goals.isEmpty else {
            return SavingsWalletMigrationResult(changed: false, report: nil)
        }

        var report = SavingsWalletMigrationReport(
            ownerID: ownerID,
            createdAt: now,
            convertedGoalIDs: [],
            deferredGoalIDs: [],
            failedGoals: [:],
            netWorthDelta: 0,
            newlyNegativeWalletIDs: [],
            acknowledgedAt: nil
        )
        var changed = false

        for goal in goals.sorted(by: legacyGoalOrder) {
            do {
                let outcome = try migrate(
                    goal,
                    in: context,
                    ownerID: ownerID,
                    rates: rates,
                    netWorthCurrency: netWorthCurrency,
                    now: now
                )
                switch outcome {
                case .converted(let wallet, let netWorthDelta):
                    report.convertedGoalIDs.append(goal.id)
                    report.netWorthDelta += netWorthDelta
                    if wallet.balance < 0 { report.newlyNegativeWalletIDs.append(wallet.id) }
                    changed = true
                case .deferred:
                    report.deferredGoalIDs.append(goal.id)
                }
            } catch {
                report.failedGoals[goal.id] = error.localizedDescription
                // The caller owns one transaction for the full maintenance
                // batch. Throwing guarantees it rolls back every tentative
                // conversion instead of committing a partially failed goal.
                report.convertedGoalIDs = []
                report.netWorthDelta = 0
                report.newlyNegativeWalletIDs = []
                SavingsMigrationReportStore.save(report)
                throw SavingsWalletMigrationBatchError(report: report)
            }
        }

        SavingsMigrationReportStore.save(report)
        return SavingsWalletMigrationResult(changed: changed, report: report)
    }

    private enum GoalOutcome {
        case converted(Wallet, netWorthDelta: Decimal)
        case deferred
    }

    private static func migrate(
        _ goal: SavingsGoal,
        in context: ModelContext,
        ownerID: UUID?,
        rates: [String: Double],
        netWorthCurrency: String,
        now: Date
    ) throws -> GoalOutcome {
        let allWallets = try context.fetch(FetchDescriptor<Wallet>())
            .filter { $0.deletedAt == nil }
        let allTransactions = try context.fetch(FetchDescriptor<Transaction>())
        let tagged = allTransactions.filter { SavingsLedger.isEligible($0, for: goal) }
        let rows = tagged.compactMap { transaction -> SavingsLedgerEntrySnapshot? in
            guard let side = TransferSideAmountResolver.ledgerAmount(for: transaction) else { return nil }
            return SavingsLedgerEntrySnapshot(
                id: transaction.id,
                goalID: goal.id,
                date: transaction.date,
                amount: side.amount,
                currencyCode: side.currencyCode,
                isWithdrawal: transaction.savingsIsWithdrawal
            )
        }
        let ledger = SavingsLedgerCalculator.calculate(
            startingBalance: goal.currentAmount,
            startingCurrencyCode: goal.startingBalanceCurrencyCode ?? goal.currencyCode,
            goalCurrencyCode: goal.currencyCode,
            rows: rows,
            rates: rates
        )
        guard ledger.isDeterminate else { return .deferred }

        if let replacement = allWallets.first(where: { $0.legacySavingsGoalID == goal.id }),
           replacement.legacyMigrationCompletedAt != nil {
            clearLegacyLinks(tagged, goal: goal, now: now)
            softDelete(goal, at: now)
            return .converted(replacement, netWorthDelta: 0)
        }

        let beforeBalances = Dictionary(
            uniqueKeysWithValues: allWallets.map { wallet in
                wallet.invalidateBalanceCache()
                return (wallet.id, wallet.balance)
            }
        )
        let beforeNetWorth = try convertedNetWorth(
            wallets: allWallets,
            currencyCode: netWorthCurrency,
            rates: rates
        )

        let hasPhantomStartingBalance = goal.currentAmount != 0
        let canFlip = canFlipLinkedWallet(
            goal: goal,
            tagged: tagged,
            allTransactions: allTransactions,
            rawTotal: ledger.rawTotal,
            hasPhantomStartingBalance: hasPhantomStartingBalance
        )

        let replacement: Wallet
        var expectedBalanceDeltas: [UUID: Decimal] = [:]
        var disclosedNetWorthDelta: Decimal = 0

        if canFlip, let linked = goal.linkedWallet {
            replacement = linked
        } else {
            replacement = allWallets.first(where: { $0.legacySavingsGoalID == goal.id }) ?? {
                let wallet = Wallet(
                    name: goal.name,
                    currencyCode: goal.currencyCode,
                    icon: goal.iconName,
                    colorHex: goal.colorHex
                )
                wallet.createdAt = goal.createdDate
                wallet.syncUserID = ownerID
                context.insert(wallet)
                return wallet
            }()

            if let starting = SavingsLedgerCalculator.convertStrict(
                goal.currentAmount,
                from: goal.startingBalanceCurrencyCode ?? goal.currencyCode,
                to: goal.currencyCode,
                rates: rates
            ), starting != 0 {
                try upsertAdjustment(
                    id: deterministicID(goalID: goal.id, purpose: "starting", originalID: nil),
                    amount: starting,
                    currencyCode: goal.currencyCode,
                    date: goal.createdDate,
                    wallet: replacement,
                    provenance: provenance(goalID: goal.id, purpose: "starting", originalID: nil),
                    ownerID: ownerID,
                    now: now,
                    context: context,
                    allTransactions: allTransactions
                )
                disclosedNetWorthDelta = try convertStrict(
                    starting,
                    from: goal.currencyCode,
                    to: netWorthCurrency,
                    rates: rates
                )
            }

            for transaction in tagged {
                guard let side = TransferSideAmountResolver.ledgerAmount(for: transaction) else { continue }
                let converted = try convertStrict(
                    side.amount,
                    from: side.currencyCode,
                    to: goal.currencyCode,
                    rates: rates
                )
                let signedGoalDelta = transaction.savingsIsWithdrawal ? -converted : converted
                let purpose = transaction.savingsIsWithdrawal ? "withdrawal" : "contribution"
                try upsertAdjustment(
                    id: deterministicID(goalID: goal.id, purpose: purpose, originalID: transaction.id),
                    amount: signedGoalDelta,
                    currencyCode: goal.currencyCode,
                    date: transaction.date,
                    wallet: replacement,
                    provenance: provenance(goalID: goal.id, purpose: purpose, originalID: transaction.id),
                    ownerID: ownerID,
                    now: now,
                    context: context,
                    allTransactions: allTransactions
                )

                let physicalWallet = transaction.savingsIsWithdrawal
                    ? transaction.sourceWallet
                    : transaction.destinationWallet
                guard let physicalWallet else {
                    throw WalletLedgerRuleError.missingSourceWallet
                }
                let signedPhysicalDelta = transaction.savingsIsWithdrawal ? -side.amount : side.amount
                let compensation = -signedPhysicalDelta
                expectedBalanceDeltas[physicalWallet.id, default: 0] += compensation
                try upsertAdjustment(
                    id: deterministicID(goalID: goal.id, purpose: "compensation", originalID: transaction.id),
                    amount: compensation,
                    currencyCode: physicalWallet.currencyCode,
                    date: transaction.date,
                    wallet: physicalWallet,
                    provenance: provenance(goalID: goal.id, purpose: "compensation", originalID: transaction.id),
                    ownerID: ownerID,
                    now: now,
                    context: context,
                    allTransactions: allTransactions
                )
            }
        }

        replacement.kind = .savings
        replacement.targetAmount = goal.targetAmount
        replacement.targetDate = goal.targetDate
        replacement.priority = goal.priority
        replacement.hasCelebrated = goal.isCompleted || ledger.rawTotal >= goal.targetAmount
        replacement.legacySavingsGoalID = goal.id
        replacement.legacyMigrationCompletedAt = ownerID == nil ? now : nil
        replacement.updatedAt = now
        replacement.needsSync = true
        replacement.syncUserID = ownerID

        let recurringRules = try context.fetch(FetchDescriptor<RecurringRule>()).filter {
            $0.deletedAt == nil && $0.wallet?.id == replacement.id
        }
        for rule in recurringRules {
            rule.isActive = false
            rule.pauseReason = .invalidSavingsWallet
            rule.updatedAt = now
            rule.needsSync = true
        }

        clearLegacyLinks(tagged, goal: goal, now: now)
        softDelete(goal, at: now)

        let afterWallets = try context.fetch(FetchDescriptor<Wallet>())
            .filter { $0.deletedAt == nil }
        afterWallets.forEach { $0.invalidateBalanceCache() }

        if canFlip {
            guard replacement.balance == ledger.rawTotal else {
                throw SavingsWalletMigrationError.balanceInvariant(goal.id)
            }
        } else {
            guard replacement.balance == ledger.rawTotal else {
                throw SavingsWalletMigrationError.balanceInvariant(goal.id)
            }
            for (walletID, before) in beforeBalances {
                guard let wallet = afterWallets.first(where: { $0.id == walletID }) else { continue }
                let expected = before + (expectedBalanceDeltas[walletID] ?? 0)
                guard wallet.balance == expected else {
                    throw SavingsWalletMigrationError.walletInvariant(walletID)
                }
            }
        }

        let afterNetWorth = try convertedNetWorth(
            wallets: afterWallets,
            currencyCode: netWorthCurrency,
            rates: rates
        )
        guard afterNetWorth - beforeNetWorth == disclosedNetWorthDelta else {
            throw SavingsWalletMigrationError.netWorthInvariant(goal.id)
        }
        return .converted(replacement, netWorthDelta: disclosedNetWorthDelta)
    }

    private static func canFlipLinkedWallet(
        goal: SavingsGoal,
        tagged: [Transaction],
        allTransactions: [Transaction],
        rawTotal: Decimal,
        hasPhantomStartingBalance: Bool
    ) -> Bool {
        guard !hasPhantomStartingBalance,
              let wallet = goal.linkedWallet,
              wallet.deletedAt == nil,
              wallet.currencyCode == goal.currencyCode,
              wallet.balance == rawTotal else { return false }
        let taggedIDs = Set(tagged.map(\.id))
        let touching = allTransactions.filter {
            $0.deletedAt == nil && ($0.sourceWallet?.id == wallet.id || $0.destinationWallet?.id == wallet.id)
        }
        return !touching.isEmpty && touching.allSatisfy {
            $0.type == .transfer && taggedIDs.contains($0.id) && $0.savingsGoal?.id == goal.id
        }
    }

    private static func clearLegacyLinks(_ transactions: [Transaction], goal: SavingsGoal, now: Date) {
        for transaction in transactions {
            transaction.savingsGoal = nil
            transaction.savingsIsWithdrawal = false
            transaction.migrationProvenance = provenance(
                goalID: goal.id,
                purpose: "untag",
                originalID: transaction.id
            )
            transaction.updatedAt = now
            transaction.needsSync = true
        }
    }

    private static func upsertAdjustment(
        id: UUID,
        amount: Decimal,
        currencyCode: String,
        date: Date,
        wallet: Wallet,
        provenance: String,
        ownerID: UUID?,
        now: Date,
        context: ModelContext,
        allTransactions: [Transaction]
    ) throws {
        guard amount != 0 else { return }
        let transaction = allTransactions.first(where: { $0.id == id }) ?? {
            let created = Transaction(
                amount: amount,
                currencyCode: currencyCode,
                date: date,
                type: .adjustment
            )
            created.id = id
            context.insert(created)
            return created
        }()
        transaction.amount = amount
        transaction.currencyCode = currencyCode
        transaction.date = date
        transaction.type = .adjustment
        transaction.note = "Savings migration"
        transaction.tags = []
        transaction.excludeFromReports = true
        transaction.exchangeRate = 1
        transaction.storedRate = 1
        transaction.sourceWallet = wallet
        transaction.destinationWallet = nil
        transaction.savingsGoal = nil
        transaction.savingsIsWithdrawal = false
        transaction.migrationProvenance = provenance
        transaction.deletedAt = nil
        transaction.syncUserID = ownerID
        transaction.updatedAt = now
        transaction.needsSync = true
        try WalletLedgerRules.validate(transaction: transaction)
    }

    static func provenance(goalID: UUID, purpose: String, originalID: UUID?) -> String {
        "legacy-savings:\(goalID.uuidString):\(purpose):\(originalID?.uuidString ?? "goal")"
    }

    static func goalID(from provenance: String?) -> UUID? {
        guard let provenance else { return nil }
        let pieces = provenance.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count >= 2, pieces[0] == "legacy-savings" else { return nil }
        return UUID(uuidString: String(pieces[1]))
    }

    static func deterministicID(goalID: UUID, purpose: String, originalID: UUID?) -> UUID {
        let seed = provenance(goalID: goalID, purpose: purpose, originalID: originalID)
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func softDelete(_ goal: SavingsGoal, at date: Date) {
        goal.deletedAt = date
        goal.updatedAt = date
        goal.needsSync = true
    }

    private static func convertedNetWorth(
        wallets: [Wallet],
        currencyCode: String,
        rates: [String: Double]
    ) throws -> Decimal {
        try wallets.reduce(Decimal.zero) { total, wallet in
            total + (try convertStrict(wallet.balance, from: wallet.currencyCode, to: currencyCode, rates: rates))
        }
    }

    private static func convertStrict(
        _ amount: Decimal,
        from source: String,
        to target: String,
        rates: [String: Double]
    ) throws -> Decimal {
        guard let converted = SavingsLedgerCalculator.convertStrict(
            amount,
            from: source,
            to: target,
            rates: rates
        ) else { throw SavingsWalletMigrationError.indeterminateRate(source, target) }
        return converted
    }

    nonisolated private static func legacyGoalOrder(_ lhs: SavingsGoal, _ rhs: SavingsGoal) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        if lhs.createdDate != rhs.createdDate { return lhs.createdDate < rhs.createdDate }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct SavingsWalletMigrationBatchError: LocalizedError {
    let report: SavingsWalletMigrationReport

    var errorDescription: String? {
        "Savings-wallet migration stopped because an invariant failed."
    }
}

enum SavingsWalletMigrationError: LocalizedError {
    case indeterminateRate(String, String)
    case balanceInvariant(UUID)
    case walletInvariant(UUID)
    case netWorthInvariant(UUID)

    var errorDescription: String? {
        switch self {
        case .indeterminateRate(let source, let target):
            return "Missing exact \(source)→\(target) exchange rate."
        case .balanceInvariant(let id):
            return "Savings balance invariant failed for \(id.uuidString)."
        case .walletInvariant(let id):
            return "Wallet balance invariant failed for \(id.uuidString)."
        case .netWorthInvariant(let id):
            return "Net-worth invariant failed for goal \(id.uuidString)."
        }
    }
}

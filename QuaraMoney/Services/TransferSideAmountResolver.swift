import Foundation

nonisolated struct TransferSideAmount: Sendable, Equatable {
    let amount: Decimal
    let currencyCode: String
}

/// Single authority for transfer source/destination amounts used by wallet and savings math.
enum TransferSideAmountResolver {
    nonisolated static func sourceAmount(for transaction: Transaction) -> TransferSideAmount? {
        guard transaction.type == .transfer, let wallet = transaction.sourceWallet else { return nil }
        return TransferSideAmount(amount: resolve(transaction, in: wallet), currencyCode: wallet.currencyCode)
    }

    nonisolated static func destinationAmount(for transaction: Transaction) -> TransferSideAmount? {
        guard transaction.type == .transfer, let wallet = transaction.destinationWallet else { return nil }
        return TransferSideAmount(amount: resolve(transaction, in: wallet), currencyCode: wallet.currencyCode)
    }

    nonisolated static func ledgerAmount(for transaction: Transaction) -> TransferSideAmount? {
        transaction.savingsIsWithdrawal ? sourceAmount(for: transaction) : destinationAmount(for: transaction)
    }

    nonisolated static func resolve(_ transaction: Transaction, in wallet: Wallet) -> Decimal {
        if transaction.currencyCode == wallet.currencyCode { return transaction.amount }
        if let rate = transaction.storedRate, rate > 0 { return transaction.amount * rate }
        if transaction.exchangeRate > 0, transaction.exchangeRate != 1 { return transaction.amount * transaction.exchangeRate }
        guard let source = CurrencyManager.fallbackRates[transaction.currencyCode],
              let target = CurrencyManager.fallbackRates[wallet.currencyCode] else { return transaction.amount }
        return transaction.amount / Decimal(source) * Decimal(target)
    }
}

enum SavingsLedger {
    nonisolated static func isEligible(_ transaction: Transaction, for goal: SavingsGoal) -> Bool {
        transaction.deletedAt == nil && transaction.type == .transfer && transaction.savingsGoal?.id == goal.id
    }
}

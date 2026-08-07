import Foundation

enum WalletLedgerRuleError: LocalizedError, Equatable {
    case spendingAgainstSavingsWallet
    case missingSourceWallet
    case unexpectedDestinationWallet
    case missingDestinationWallet
    case sameTransferWallet
    case zeroAdjustment
    case savingsTargetRequired
    case savingsKindLocked
    case savingsCurrencyLocked
    case savingsWalletHasSpending
    case fundedSavingsCannotArchive
    case nonZeroSavingsCannotDelete
    case invalidWalletRehome

    var errorDescription: String? {
        switch self {
        case .spendingAgainstSavingsWallet:
            return "savings.error.spendingNotAllowed".localized
        case .missingSourceWallet:
            return "transaction.error.sourceWalletRequired".localized
        case .unexpectedDestinationWallet:
            return "transaction.error.destinationNotAllowed".localized
        case .missingDestinationWallet:
            return "transaction.error.destinationWalletRequired".localized
        case .sameTransferWallet:
            return "transaction.error.sameWallet".localized
        case .zeroAdjustment:
            return "transaction.error.zeroAdjustment".localized
        case .savingsTargetRequired:
            return "savings.error.targetRequired".localized
        case .savingsKindLocked:
            return "savings.error.kindLocked".localized
        case .savingsCurrencyLocked:
            return "savings.error.currencyLocked".localized
        case .savingsWalletHasSpending:
            return "savings.error.hasSpending".localized
        case .fundedSavingsCannotArchive:
            return "savings.error.fundedArchive".localized
        case .nonZeroSavingsCannotDelete:
            return "savings.error.nonZeroDelete".localized
        case .invalidWalletRehome:
            return "savings.error.invalidRehome".localized
        }
    }
}

/// One authority for the wallet/type matrix. Callers validate proposed values
/// before mutating an existing model so failed edits never enter autosave.
nonisolated enum WalletLedgerRules {
    static func validate(transaction: Transaction) throws {
        try validate(
            type: transaction.type,
            amount: transaction.amount,
            sourceWallet: transaction.sourceWallet,
            destinationWallet: transaction.destinationWallet
        )
    }

    static func validate(
        type: TransactionType,
        amount: Decimal,
        sourceWallet: Wallet?,
        destinationWallet: Wallet?
    ) throws {
        guard let sourceWallet else { throw WalletLedgerRuleError.missingSourceWallet }

        switch type {
        case .income, .expense:
            guard destinationWallet == nil else {
                throw WalletLedgerRuleError.unexpectedDestinationWallet
            }
            guard sourceWallet.canReceiveSpendingTransaction(of: type) else {
                throw WalletLedgerRuleError.spendingAgainstSavingsWallet
            }
        case .transfer:
            guard let destinationWallet else {
                throw WalletLedgerRuleError.missingDestinationWallet
            }
            guard destinationWallet.id != sourceWallet.id else {
                throw WalletLedgerRuleError.sameTransferWallet
            }
        case .adjustment:
            guard destinationWallet == nil else {
                throw WalletLedgerRuleError.unexpectedDestinationWallet
            }
            guard amount != 0 else { throw WalletLedgerRuleError.zeroAdjustment }
        }
    }

    static func validateSavingsConfiguration(
        kind: WalletKind,
        targetAmount: Decimal?
    ) throws {
        if kind == .savings, (targetAmount ?? 0) <= 0 {
            throw WalletLedgerRuleError.savingsTargetRequired
        }
    }

    static func validateWalletUpdate(
        wallet: Wallet,
        proposedKind: WalletKind,
        proposedCurrencyCode: String,
        proposedTargetAmount: Decimal?,
        proposedArchived: Bool
    ) throws {
        try validateSavingsConfiguration(kind: proposedKind, targetAmount: proposedTargetAmount)
        if wallet.isSavings, proposedKind != .savings {
            throw WalletLedgerRuleError.savingsKindLocked
        }
        if !wallet.isSavings, proposedKind == .savings {
            let hasSpending = (wallet.outgoingTransactions ?? []).contains {
                $0.deletedAt == nil && ($0.type == .income || $0.type == .expense)
            }
            if hasSpending { throw WalletLedgerRuleError.savingsWalletHasSpending }
        }
        if wallet.isSavings, wallet.hasAnyLedgerTransaction,
           proposedCurrencyCode != wallet.currencyCode {
            throw WalletLedgerRuleError.savingsCurrencyLocked
        }
        if proposedArchived, proposedKind == .savings, wallet.balance != 0 {
            throw WalletLedgerRuleError.fundedSavingsCannotArchive
        }
    }

    static func validateWalletDeletion(_ wallet: Wallet) throws {
        if wallet.isSavings, wallet.balance != 0 {
            throw WalletLedgerRuleError.nonZeroSavingsCannotDelete
        }
    }

    static func validateRehome(_ transaction: Transaction, to wallet: Wallet) throws {
        try validate(
            type: transaction.type,
            amount: transaction.amount,
            sourceWallet: wallet,
            destinationWallet: transaction.destinationWallet
        )
    }
}

import Foundation
import SwiftData

@Observable
@MainActor
class AdjustBalanceViewModel {
    private let dataService: DataService
    let wallet: Wallet

    // Calculator-keyboard state (mirrors AddTransactionViewModel): the raw
    // expression the user is typing plus its evaluated value. The evaluated
    // amount IS the new/target balance for the wallet.
    var expression: String = ""
    var evaluatedAmount: Decimal = 0
    var date: Date = Date()
    var note: String = ""
    var excludeFromReports: Bool = true

    init(wallet: Wallet, dataService: DataService) {
        self.wallet = wallet
        self.dataService = dataService
        // Start empty — the user must actively type the new balance, and can't
        // save until it differs from the current one.
    }

    /// Whether the user has typed anything into the amount field.
    var hasInput: Bool {
        !expression.isEmpty
    }

    /// The new balance the user is setting (the evaluated calculator value).
    var targetBalance: Decimal {
        evaluatedAmount
    }

    var currentBalance: Decimal {
        wallet.balance
    }

    var difference: Decimal {
        targetBalance - currentBalance
    }

    var isValid: Bool {
        // Requires actual input AND a target that differs from the current balance.
        hasInput && difference != 0
    }

    func save() {
        guard isValid else { return }

        // Difference is already signed correctly:
        // Target (100) - Current (50) = +50 (Income/Increase)
        // Target (0) - Current (50) = -50 (Expense/Decrease)
        let amount = difference

        let transaction = Transaction(
            amount: amount, // Transaction amount is signed for adjustments?
            // WAIT. Transaction.amount is usually absolute, and Type determines sign?
            // Let's check Wallet+Extensions.swift again.
            // computeBalance: case .adjustment: total += convertedAmount
            // So YES, adjustment amount MUST be signed.
            currencyCode: wallet.currencyCode,
            date: date,
            type: .adjustment
        )

        transaction.sourceWallet = wallet
        transaction.note = note.isEmpty ? nil : note
        transaction.excludeFromReports = excludeFromReports
        // Adjustment is denominated in the wallet's own currency.
        transaction.storedRate = 1

        dataService.insert(transaction)

        do {
            try dataService.save()
            wallet.invalidateBalanceCache()
        } catch {
            #if DEBUG
            print("Error saving adjustment: \(error)")
            #endif
        }
    }
}

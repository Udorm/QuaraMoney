import Foundation
import SwiftData

@Observable
@MainActor
class AdjustBalanceViewModel {
    private let dataService: DataService
    let wallet: Wallet

    // Input is now the TARGET balance
    var targetBalanceString: String = ""
    var date: Date = Date()
    var note: String = ""
    var excludeFromReports: Bool = true

    init(wallet: Wallet, dataService: DataService) {
        self.wallet = wallet
        self.dataService = dataService
        // Initialize with current balance so user can edit it
        self.targetBalanceString = format(decimal: wallet.balance)
    }

    private func format(decimal: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: decimal).doubleValue
        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", doubleValue)
        } else {
            return String(format: "%.2f", doubleValue)
        }
    }

    var targetBalance: Decimal? {
        Decimal(string: targetBalanceString)
    }

    var currentBalance: Decimal {
        wallet.balance
    }

    var difference: Decimal {
        (targetBalance ?? 0) - currentBalance
    }

    var isValid: Bool {
        guard targetBalance != nil else { return false }
        // Valid if target is different from current
        return difference != 0
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

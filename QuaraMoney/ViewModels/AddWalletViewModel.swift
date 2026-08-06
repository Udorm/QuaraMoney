import Foundation
import SwiftUI

@Observable
@MainActor
class AddWalletViewModel: BaseViewModel {
    var name: String = ""
    var currencyCode: String = "USD"
    var icon: String = "wallet.pass"
    var colorHex: String = "#007AFF" // Default iOS Blue
    var kind: WalletKind = .normal
    var targetAmountText: String = ""
    var hasTargetDate = false
    var targetDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var priority = 0
    private(set) var walletToEdit: Wallet?
    
    init(dataService: DataService, walletToEdit: Wallet? = nil) {
        super.init(dataService: dataService)
        self.walletToEdit = walletToEdit
        
        if let wallet = walletToEdit {
            self.name = wallet.name
            self.currencyCode = wallet.currencyCode
            self.icon = wallet.icon
            self.colorHex = wallet.colorHex
            self.kind = wallet.kind
            self.targetAmountText = wallet.targetAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            self.hasTargetDate = wallet.targetDate != nil
            self.targetDate = wallet.targetDate ?? self.targetDate
            self.priority = wallet.priority
        }
    }

    var targetAmount: Decimal? { Decimal(string: targetAmountText) }
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind == .normal || (targetAmount ?? 0) > 0)
    }
    
    var isEditing: Bool {
        walletToEdit != nil
    }
    
    var isArchived: Bool {
        walletToEdit?.isArchived ?? false
    }

    var canEditCurrency: Bool {
        guard let wallet = walletToEdit else { return true }
        return !wallet.isSavings || !wallet.hasAnyLedgerTransaction
    }
    
    @discardableResult
    func saveWallet() -> Bool {
        guard isValid else { return false }

        do {
            try WalletLedgerRules.validateSavingsConfiguration(kind: kind, targetAmount: targetAmount)
            let wallet: Wallet
            if let existing = walletToEdit {
                try WalletLedgerRules.validateWalletUpdate(
                    wallet: existing,
                    proposedKind: kind,
                    proposedCurrencyCode: currencyCode,
                    proposedTargetAmount: targetAmount,
                    proposedArchived: existing.isArchived
                )
                wallet = existing
            } else {
                wallet = Wallet(name: name, currencyCode: currencyCode, icon: icon, colorHex: colorHex)
                dataService.insert(wallet)
            }
            wallet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            wallet.currencyCode = currencyCode
            wallet.icon = icon
            wallet.colorHex = colorHex
            wallet.kind = kind
            wallet.targetAmount = kind == .savings ? targetAmount : nil
            wallet.targetDate = kind == .savings && hasTargetDate ? targetDate : nil
            wallet.priority = kind == .savings ? priority : 0
            wallet.updatedAt = Date()
            wallet.needsSync = true
            wallet.invalidateBalanceCache()
            try dataService.save()
            HapticManager.shared.success()
            return true
        } catch {
            dataService.rollback()
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
            return false
        }
    }

    @discardableResult
    func archiveWallet() -> Bool {
        guard let wallet = walletToEdit else { return false }
        do {
            try WalletLedgerRules.validateWalletUpdate(
                wallet: wallet,
                proposedKind: wallet.kind,
                proposedCurrencyCode: wallet.currencyCode,
                proposedTargetAmount: wallet.targetAmount,
                proposedArchived: true
            )
            wallet.isArchived = true
            wallet.updatedAt = Date(); wallet.needsSync = true
            try dataService.save()
            return true
        } catch {
            dataService.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
    
    func unarchiveWallet() {
        guard let wallet = walletToEdit else { return }
        wallet.isArchived = false
        wallet.updatedAt = Date(); wallet.needsSync = true
        do { try dataService.save() } catch {
            dataService.rollback()
            errorMessage = error.localizedDescription
        }
    }
    
    @discardableResult
    func deleteWallet() -> Bool {
        guard let wallet = walletToEdit else { return false }
        // Soft-delete (tombstone) so the deletion replicates to other devices.
        do {
            try SoftDeleteService.deleteWallet(wallet, strategy: .deleteTransactions)
            try dataService.save()
            return true
        } catch {
            dataService.rollback()
            errorMessage = error.localizedDescription
            return false
        }
    }
}

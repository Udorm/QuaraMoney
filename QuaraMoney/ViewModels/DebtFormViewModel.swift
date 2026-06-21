import Foundation
import SwiftData

@Observable
@MainActor
final class DebtFormViewModel {
    var personName = ""
    var expression = ""
    var evaluatedAmount: Decimal = 0
    var currencyCode: String = CurrencyManager.shared.preferredCurrencyCode
    var type: DebtType = .iOwe
    var date: Date = Date()
    var dueDate: Date = Date()
    var hasDueDate = false
    var note = ""
    var selectedWallet: Wallet?

    private let originalDate: Date

    var errorMessage: String?
    var showError = false
    var showSuccess = false
    var isSaving = false

    let debtToEdit: Debt?
    private let originalAmount: Decimal

    var isEditing: Bool { debtToEdit != nil }

    /// On edit, the principal amount can only be changed when there is a single
    /// advance and no repayments have split it. New debts are always editable.
    var canEditAmount: Bool {
        guard let debtToEdit else { return true }
        return debtToEdit.canEditPrincipalAmount
    }

    var amount: Decimal? {
        evaluatedAmount > 0 ? evaluatedAmount : nil
    }

    var isValid: Bool {
        !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        evaluatedAmount > 0 &&
        // A wallet is required when creating (track-only removed); not editable on edit.
        (isEditing || selectedWallet != nil)
    }

    init(debt: Debt? = nil) {
        self.debtToEdit = debt

        guard let debt else {
            self.originalAmount = 0
            self.originalDate = Date()
            return
        }
        personName = debt.personName
        evaluatedAmount = debt.totalAmount
        expression = DebtFormViewModel.formatExpression(debt.totalAmount)
        originalAmount = debt.totalAmount
        currencyCode = debt.currencyCode
        type = debt.type
        // The debt's date is its initial advance transaction's date, falling
        // back to the stored creation date.
        let resolvedDate = debt.principalTransaction?.date ?? debt.dateCreated
        date = resolvedDate
        originalDate = resolvedDate
        dueDate = debt.dueDate ?? Date()
        hasDueDate = debt.dueDate != nil
        note = debt.note ?? ""
    }

    func save(context: ModelContext) -> Bool {
        guard let amount, isValid else { return false }

        showError = false
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let service = DebtService(modelContext: context)
            let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let noteValue = normalizedNote.isEmpty ? nil : normalizedNote

            if let debtToEdit {
                let newAmount: Decimal? = (canEditAmount && amount != originalAmount) ? amount : nil
                let newDate: Date? = (date != originalDate) ? date : nil
                try service.updateDebt(
                    debtToEdit,
                    person: personName,
                    dueDate: hasDueDate ? dueDate : nil,
                    note: noteValue,
                    newPrincipalAmount: newAmount,
                    date: newDate
                )
                return true
            }

            if type == .owedToMe {
                _ = try service.createDebt(
                    person: personName,
                    amount: amount,
                    currency: currencyCode,
                    dueDate: hasDueDate ? dueDate : nil,
                    note: noteValue,
                    sourceWallet: selectedWallet,
                    date: date
                )
            } else {
                _ = try service.createLoan(
                    person: personName,
                    amount: amount,
                    currency: currencyCode,
                    dueDate: hasDueDate ? dueDate : nil,
                    note: noteValue,
                    destinationWallet: selectedWallet,
                    date: date
                )
            }

            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showError = true
            return false
        }
    }

    private static func formatExpression(_ value: Decimal) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        return doubleValue.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", doubleValue)
            : String(format: "%.2f", doubleValue)
    }
}

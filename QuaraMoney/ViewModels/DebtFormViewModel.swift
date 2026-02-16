import Foundation
import SwiftData
import Combine

@MainActor
final class DebtFormViewModel: ObservableObject {
    @Published var personName = ""
    @Published var amountText = ""
    @Published var currencyCode: String = CurrencyManager.shared.preferredCurrencyCode
    @Published var type: DebtType = .iOwe
    @Published var dueDate: Date = Date()
    @Published var hasDueDate = false
    @Published var note = ""
    @Published var selectedWallet: Wallet?

    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSuccess = false
    @Published var isSaving = false

    let debtToEdit: Debt?

    var isEditing: Bool {
        debtToEdit != nil
    }

    var amount: Decimal? {
        parseAmount(amountText)
    }

    var isValid: Bool {
        !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (amount ?? 0) > 0
    }

    init(debt: Debt? = nil) {
        self.debtToEdit = debt

        guard let debt else { return }
        personName = debt.personName
        amountText = debt.totalAmount.formatted(.number)
        currencyCode = debt.currencyCode
        type = debt.type
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
                try service.updateDebt(
                    debtToEdit,
                    person: personName,
                    dueDate: hasDueDate ? dueDate : nil,
                    note: noteValue
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
                    sourceWallet: selectedWallet
                )
            } else {
                _ = try service.createLoan(
                    person: personName,
                    amount: amount,
                    currency: currencyCode,
                    dueDate: hasDueDate ? dueDate : nil,
                    note: noteValue,
                    destinationWallet: selectedWallet
                )
            }

            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showError = true
            return false
        }
    }

    private func parseAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.decimalValue
        }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}

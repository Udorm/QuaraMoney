
import SwiftData
import Foundation

enum DebtType: String, Codable, CaseIterable, Identifiable {
    case owedToMe = "Owed To Me"
    case iOwe = "I Owe"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .owedToMe: return "Owed To Me" // L10n later
        case .iOwe: return "I Owe"
        }
    }
}

@Model
final class Debt {
    var id: UUID
    var personName: String
    var totalAmount: Decimal
    var currencyCode: String
    var dueDate: Date?
    var type: DebtType
    var note: String?
    var dateCreated: Date
    var isCompleted: Bool = false

    // Timestamps (for future sync readiness)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // Relationship to linked transactions
    @Relationship(deleteRule: .cascade, inverse: \Transaction.debt)
    var transactions: [Transaction]?
    
    init(personName: String, totalAmount: Decimal, currencyCode: String, type: DebtType, dueDate: Date? = nil, note: String? = nil) {
        self.id = UUID()
        self.personName = personName
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.type = type
        self.dueDate = dueDate
        self.note = note
        self.dateCreated = Date()
    }
    
    // Logic:
    // owedToMe (I lent money):
    // - Total = Sum of Expense transactions linked to this Debt (Initial loan + any additions)
    // - Paid = Sum of Income transactions linked to this Debt (Repayments)
    //
    // iOwe (I borrowed money):
    // - Total = Sum of Income transactions linked to this Debt (Initial borrow + any additions)
    // - Paid = Sum of Expense transactions linked to this Debt (Repayments)
    
    /// Converts a linked transaction's amount into this debt's currency so the
    /// ledger stays correct even when a transaction is recorded (or edited) in a
    /// different currency. Same-currency is identity; cross-currency uses the
    /// app's current daily rates (cached) via a nonisolated accessor, falling
    /// back to the static reference table when no rates have been fetched.
    private func amountInDebtCurrency(_ transaction: Transaction) -> Decimal {
        guard transaction.currencyCode != currencyCode else { return transaction.amount }
        return CurrencyManager.convert(
            amount: transaction.amount,
            from: transaction.currencyCode,
            to: currencyCode,
            rates: CurrencyManager.currentRates
        )
    }

    /// Transaction type that represents a repayment for this debt.
    private var repaymentType: TransactionType {
        type == .owedToMe ? .income : .expense
    }

    /// Transaction type that represents an advance (principal) for this debt.
    private var advanceType: TransactionType {
        type == .owedToMe ? .expense : .income
    }

    var amountPaid: Decimal {
        guard let transactions = transactions else { return 0 }
        return transactions
            .filter { $0.type == repaymentType }
            .reduce(0) { $0 + amountInDebtCurrency($1) }
    }
    
    // We might want to dynamically calculate totalAmount too if we allow "topping up" the loan/debt
    // But for now, let's keep totalAmount as the "Target" or "Initial" amount, 
    // OR we should update it to be dynamic. 
    // The requirement says: "Debt is a collection of transactions... Debt1 have 1 expense (initial) and 2 income (repayments)"
    // So distincting "Initial" vs "Repayment" only by Type is good.
    // But what if I lend MORE? That would be another Expense.
    // So Total Debt = Sum of all Expenses (if owedToMe).
    
    var currentTotalAmount: Decimal {
        guard let transactions = transactions else { return totalAmount } // Fallback

        let totalAdvanced = transactions
            .filter { $0.type == advanceType }
            .reduce(0) { $0 + amountInDebtCurrency($1) }
        // If no advance transactions yet (e.g. just created), fall back to the
        // stored initial amount.
        return totalAdvanced > 0 ? totalAdvanced : totalAmount
    }
    
    // Use currentTotalAmount for remaining calculation
    var remainingAmount: Decimal {
        return currentTotalAmount - amountPaid
    }

    /// Remaining balance for display and aggregation — never negative, so an
    /// over-payment reads as fully settled (0 owed) rather than a negative due.
    var displayRemaining: Decimal {
        max(Decimal(0), remainingAmount)
    }
    
    var progress: Double {
        let total = currentTotalAmount
        guard total > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: amountPaid).doubleValue / NSDecimalNumber(decimal: total).doubleValue
        return min(max(ratio, 0), 1)
    }

    /// The single initial-advance transaction, if the debt has exactly one
    /// (no top-ups). Used to decide whether the principal amount is editable.
    var principalTransaction: Transaction? {
        let advances = (transactions ?? []).filter { $0.type == advanceType }
        return advances.count == 1 ? advances.first : nil
    }

    /// True when the principal amount can be safely edited (exactly one advance).
    var canEditPrincipalAmount: Bool {
        principalTransaction != nil
    }

    /// True when the due date is in the past and the debt is still outstanding.
    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    /// Re-derives the cached stored fields from the current set of linked
    /// transactions. Call after a linked transaction's amount/currency/wallet is
    /// edited elsewhere (e.g. the main transaction editor) so `totalAmount`
    /// (the fallback) and `isCompleted` stay consistent with the live ledger.
    func reconcile() {
        let tolerance: Decimal = 0.000001
        // Keep the stored principal in sync (in this debt's currency).
        if (transactions ?? []).contains(where: { $0.type == advanceType }) {
            totalAmount = currentTotalAmount
        }
        isCompleted = remainingAmount <= tolerance
        updatedAt = Date()
    }

    // MARK: - Validation

    func validate() -> [ModelValidationError] {
        var errors: [ModelValidationError] = []
        if personName.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.emptyName(field: "Person name"))
        }
        if totalAmount <= 0 { errors.append(.negativeOrZeroAmount(field: "Total amount")) }
        if currencyCode.count != 3 { errors.append(.invalidCurrencyCode) }
        return errors
    }
}

extension Transaction {
    /// True when this transaction is the sole remaining advance that anchors a
    /// linked debt. Deleting it would orphan the debt (its total silently falls
    /// back to the stored `totalAmount`), so general transaction lists block the
    /// deletion and redirect the user to the Debts & Loans screen, where the
    /// whole debt can be removed cleanly via cascade.
    var isDebtAnchor: Bool {
        guard let debt else { return false }
        return debt.principalTransaction?.id == id
    }
}

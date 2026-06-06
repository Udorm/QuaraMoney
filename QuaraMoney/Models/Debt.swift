
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
    
    var amountPaid: Decimal {
        guard let transactions = transactions else { return 0 }
        
        switch type {
        case .owedToMe:
            // I lent money. Repayments are Income.
            return transactions
                .filter { $0.type == .income }
                .reduce(0) { $0 + $1.amount }
        case .iOwe:
            // I borrowed money. Repayments are Expense.
            return transactions
                .filter { $0.type == .expense }
                .reduce(0) { $0 + $1.amount }
        }
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
        
        switch type {
        case .owedToMe:
            let totalLent = transactions
                .filter { $0.type == .expense }
                .reduce(0) { $0 + $1.amount }
            // If no transactions yet (e.g. just created), fallback to totalAmount
            return totalLent > 0 ? totalLent : totalAmount
            
        case .iOwe:
             let totalBorrowed = transactions
                .filter { $0.type == .income }
                .reduce(0) { $0 + $1.amount }
            return totalBorrowed > 0 ? totalBorrowed : totalAmount
        }
    }
    
    // Use currentTotalAmount for remaining calculation
    var remainingAmount: Decimal {
        return currentTotalAmount - amountPaid
    }
    
    var progress: Double {
        let total = currentTotalAmount
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: amountPaid).doubleValue / NSDecimalNumber(decimal: total).doubleValue
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

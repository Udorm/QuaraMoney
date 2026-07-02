
import Foundation
import SwiftData

enum DebtServiceError: LocalizedError {
    case invalidPersonName
    case invalidAmount
    case repaymentExceedsRemaining
    case cannotMarkCompletedWithRemainingBalance
    case cannotMarkActiveWhenPaidOff
    case amountNotEditable
    case amountBelowPaid

    var errorDescription: String? {
        switch self {
        case .invalidPersonName:
            return "Person name is required."
        case .invalidAmount:
            return "Amount must be greater than zero."
        case .repaymentExceedsRemaining:
            return "Repayment amount cannot exceed the remaining balance."
        case .cannotMarkCompletedWithRemainingBalance:
            return "Cannot mark completed while a remaining balance exists."
        case .cannotMarkActiveWhenPaidOff:
            return "Cannot mark active when the debt is already paid off."
        case .amountNotEditable:
            return "debt.editAmountLocked".localized
        case .amountBelowPaid:
            return "debt.amountBelowPaid".localized
        }
    }
}

@MainActor
final class DebtService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func createDebt(
        person: String,
        amount: Decimal,
        currency: String,
        dueDate: Date?,
        note: String?,
        sourceWallet: Wallet?,
        date: Date = Date()
    ) throws -> Debt {
        try validatePerson(person)
        try validateAmount(amount)
        let trimmedPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let category = try CategoryCatalog.fetchOrCreate(key: "sys_debt", in: modelContext)

            let debt = Debt(
                personName: trimmedPerson,
                totalAmount: amount,
                currencyCode: currency,
                type: .owedToMe,
                dueDate: dueDate,
                note: note
            )
            debt.dateCreated = date

            let transaction = Transaction(
                amount: amount,
                currencyCode: currency,
                date: date,
                type: .expense
            )
            transaction.note = "Lent to \(trimmedPerson)"
            transaction.category = category
            transaction.sourceWallet = sourceWallet
            transaction.debt = debt

            modelContext.insert(debt)
            modelContext.insert(transaction)

            try persistChanges(affectedWallet: sourceWallet)
            return debt
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func createLoan(
        person: String,
        amount: Decimal,
        currency: String,
        dueDate: Date?,
        note: String?,
        destinationWallet: Wallet?,
        date: Date = Date()
    ) throws -> Debt {
        try validatePerson(person)
        try validateAmount(amount)
        let trimmedPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let category = try CategoryCatalog.fetchOrCreate(key: "sys_loan", in: modelContext)

            let debt = Debt(
                personName: trimmedPerson,
                totalAmount: amount,
                currencyCode: currency,
                type: .iOwe,
                dueDate: dueDate,
                note: note
            )
            debt.dateCreated = date

            let transaction = Transaction(
                amount: amount,
                currencyCode: currency,
                date: date,
                type: .income
            )
            transaction.note = "Borrowed from \(trimmedPerson)"
            transaction.category = category
            transaction.sourceWallet = destinationWallet
            transaction.debt = debt

            modelContext.insert(debt)
            modelContext.insert(transaction)

            try persistChanges(affectedWallet: destinationWallet)
            return debt
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func recordRepayment(
        for debt: Debt,
        amount: Decimal,
        sourceWallet: Wallet?,
        date: Date = Date(),
        note: String? = nil
    ) throws {
        try validateAmount(amount)
        let tolerance: Decimal = 0.000001
        guard amount <= (debt.remainingAmount + tolerance) else {
            throw DebtServiceError.repaymentExceedsRemaining
        }

        do {
            let transactionType: TransactionType
            let categoryKey: String

            switch debt.type {
            case .owedToMe:
                transactionType = .income
                categoryKey = "sys_debt_collection"
            case .iOwe:
                transactionType = .expense
                categoryKey = "sys_loan_repayment"
            }

            let category = try CategoryCatalog.fetchOrCreate(key: categoryKey, in: modelContext)

            let transaction = Transaction(
                amount: amount,
                currencyCode: debt.currencyCode,
                date: date,
                type: transactionType
            )
            let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.note = (trimmedNote?.isEmpty == false) ? trimmedNote : "Repayment: \(debt.personName)"
            transaction.category = category
            transaction.sourceWallet = sourceWallet
            transaction.debt = debt
            modelContext.insert(transaction)

            debt.isCompleted = debt.remainingAmount <= tolerance
            try persistChanges(affectedWallet: sourceWallet)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func updateDebt(
        _ debt: Debt,
        person: String,
        dueDate: Date?,
        note: String?,
        newPrincipalAmount: Decimal? = nil,
        date: Date? = nil
    ) throws {
        try validatePerson(person)
        let trimmedPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            debt.personName = trimmedPerson
            debt.dueDate = dueDate
            debt.note = note

            var affectedWallet: Wallet?
            if let newAmount = newPrincipalAmount {
                affectedWallet = try applyPrincipalAmount(newAmount, to: debt)
            }

            // The debt's date maps to its initial advance transaction's date
            // (plus the sort key) so it stays consistent in the ledger timeline.
            if let date {
                debt.dateCreated = date
                debt.principalTransaction?.date = date
            }

            debt.updatedAt = Date()
            try persistChanges(affectedWallet: affectedWallet)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// The system category used for repayments on this debt, fetched or created.
    /// Exposed so the shared transaction editor can tag a repayment correctly.
    func repaymentCategory(for debt: Debt) throws -> Category {
        switch debt.type {
        case .owedToMe:
            return try CategoryCatalog.fetchOrCreate(key: "sys_debt_collection", in: modelContext)
        case .iOwe:
            return try CategoryCatalog.fetchOrCreate(key: "sys_loan_repayment", in: modelContext)
        }
    }

    /// Adjusts the single principal (initial advance) transaction of a debt.
    /// Only safe when exactly one principal transaction exists; multiple
    /// advances or recorded repayments lock the amount to preserve ledger
    /// integrity. Returns the wallet whose balance cache must be invalidated.
    @discardableResult
    private func applyPrincipalAmount(_ newAmount: Decimal, to debt: Debt) throws -> Wallet? {
        try validateAmount(newAmount)

        guard let principal = debt.principalTransaction else {
            throw DebtServiceError.amountNotEditable
        }

        let tolerance: Decimal = 0.000001
        guard newAmount + tolerance >= debt.amountPaid else {
            throw DebtServiceError.amountBelowPaid
        }

        guard newAmount != principal.amount else { return nil }

        principal.amount = newAmount
        debt.totalAmount = newAmount
        debt.isCompleted = (newAmount - debt.amountPaid) <= tolerance
        return principal.sourceWallet
    }


    func syncCompletionStatus(for debt: Debt) throws {
        let tolerance: Decimal = 0.000001
        let shouldBeCompleted = debt.remainingAmount <= tolerance
        if debt.isCompleted != shouldBeCompleted {
            debt.isCompleted = shouldBeCompleted
            try persistChanges(affectedWallet: nil)
        }
    }

    func setCompletion(for debt: Debt, isCompleted: Bool) throws {
        let tolerance: Decimal = 0.000001

        if isCompleted && debt.remainingAmount > tolerance {
            throw DebtServiceError.cannotMarkCompletedWithRemainingBalance
        }
        if !isCompleted && debt.remainingAmount <= tolerance {
            throw DebtServiceError.cannotMarkActiveWhenPaidOff
        }

        if debt.isCompleted != isCompleted {
            debt.isCompleted = isCompleted
            try persistChanges(affectedWallet: nil)
        }
    }

    private func persistChanges(affectedWallet: Wallet?) throws {
        affectedWallet?.invalidateBalanceCache()
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }

    private func validatePerson(_ person: String) throws {
        if person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DebtServiceError.invalidPersonName
        }
    }

    private func validateAmount(_ amount: Decimal) throws {
        if amount <= 0 {
            throw DebtServiceError.invalidAmount
        }
    }
}

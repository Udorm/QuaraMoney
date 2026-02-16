
import Foundation
import SwiftData

enum DebtServiceError: LocalizedError {
    case invalidPersonName
    case invalidAmount
    case repaymentExceedsRemaining
    case cannotMarkCompletedWithRemainingBalance
    case cannotMarkActiveWhenPaidOff

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
        sourceWallet: Wallet?
    ) throws -> Debt {
        try validatePerson(person)
        try validateAmount(amount)
        let trimmedPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let category = try fetchOrCreateSystemCategory(
                name: "Debt",
                type: .expense,
                icon: "arrow.up.right",
                color: "#FF3B30"
            )

            let debt = Debt(
                personName: trimmedPerson,
                totalAmount: amount,
                currencyCode: currency,
                type: .owedToMe,
                dueDate: dueDate,
                note: note
            )

            let transaction = Transaction(
                amount: amount,
                currencyCode: currency,
                date: Date(),
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
        destinationWallet: Wallet?
    ) throws -> Debt {
        try validatePerson(person)
        try validateAmount(amount)
        let trimmedPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let category = try fetchOrCreateSystemCategory(
                name: "Loan",
                type: .income,
                icon: "arrow.down.left",
                color: "#34C759"
            )

            let debt = Debt(
                personName: trimmedPerson,
                totalAmount: amount,
                currencyCode: currency,
                type: .iOwe,
                dueDate: dueDate,
                note: note
            )

            let transaction = Transaction(
                amount: amount,
                currencyCode: currency,
                date: Date(),
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
        date: Date = Date()
    ) throws {
        try validateAmount(amount)
        let tolerance: Decimal = 0.000001
        guard amount <= (debt.remainingAmount + tolerance) else {
            throw DebtServiceError.repaymentExceedsRemaining
        }

        do {
            let transactionType: TransactionType
            let categoryName: String
            let defaultIcon: String
            let defaultColor: String

            switch debt.type {
            case .owedToMe:
                transactionType = .income
                categoryName = "Debt Collection"
                defaultIcon = "tray.and.arrow.down.fill"
                defaultColor = "#34C759"
            case .iOwe:
                transactionType = .expense
                categoryName = "Loan Repayment"
                defaultIcon = "tray.and.arrow.up.fill"
                defaultColor = "#007AFF"
            }

            let category = try fetchOrCreateSystemCategory(
                name: categoryName,
                type: transactionType,
                icon: defaultIcon,
                color: defaultColor
            )

            let transaction = Transaction(
                amount: amount,
                currencyCode: debt.currencyCode,
                date: date,
                type: transactionType
            )
            transaction.note = "Repayment: \(debt.personName)"
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
        note: String?
    ) throws {
        try validatePerson(person)
        let trimmedPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            debt.personName = trimmedPerson
            debt.dueDate = dueDate
            debt.note = note
            try persistChanges(affectedWallet: nil)
        } catch {
            modelContext.rollback()
            throw error
        }
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

    private func fetchOrCreateSystemCategory(
        name: String,
        type: TransactionType,
        icon: String,
        color: String
    ) throws -> Category {
        let allCategories = try modelContext.fetch(FetchDescriptor<Category>())

        if let existing = allCategories.first(where: { $0.name == name && $0.type == type && $0.isSystem }) {
            return existing
        }

        if let existingLoose = allCategories.first(where: { $0.name == name && $0.type == type }) {
            existingLoose.isSystem = true
            return existingLoose
        }

        let newCategory = Category(name: name, icon: icon, colorHex: color, type: type, isSystem: true)
        modelContext.insert(newCategory)
        return newCategory
    }
}

import Foundation
import SwiftData
import Combine

@Observable
@MainActor
class FilteredTransactionsViewModel {
    let config: TransactionFilterConfig

    var transactions: [Transaction] = []
    var totalAmount: Decimal = 0
    var isLoading = false

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    init(config: TransactionFilterConfig) {
        self.config = config

        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchTransactions()
            }
            .store(in: &cancellables)
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        fetchTransactions()
    }

    func fetchTransactions() {
        guard let container = modelContext?.container else { return }

        let start = config.startDate
        let end = config.endDate
        let walletId = config.walletId
        let categoryId = config.categoryId
        let categoryIds = config.categoryIds
        let transactionType = config.transactionType
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates

        isLoading = true

        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let descriptor = TransactionProcessor.makeDescriptor(
                startDate: start,
                endDate: end,
                walletId: walletId
            )

            do {
                var fetched = try context.fetch(descriptor)

                // Filter by categories (multi-category for budgets, single for analytics)
                if let categoryIds, !categoryIds.isEmpty {
                    let idSet = Set(categoryIds)
                    fetched = fetched.filter { txn in
                        guard let txnCatId = txn.category?.id else { return false }
                        return idSet.contains(txnCatId)
                    }
                } else if let categoryId {
                    fetched = fetched.filter { $0.category?.id == categoryId }
                }

                // Filter by transaction type
                if let transactionType {
                    let targetType: TransactionType = transactionType == .expense ? .expense : .income
                    fetched = fetched.filter { $0.type == targetType }
                }

                // Calculate total in preferred currency
                let total = fetched.reduce(Decimal.zero) { sum, txn in
                    let converted = Self.convert(
                        amount: txn.amount,
                        from: txn.currencyCode,
                        to: preferredCurrency,
                        rates: rates
                    )
                    return sum + converted
                }

                await MainActor.run { [fetched, total] in
                    self.transactions = fetched
                    self.totalAmount = total
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    nonisolated private static func convert(amount: Decimal, from source: String, to target: String, rates: [String: Double]) -> Decimal {
        guard source != target else { return amount }
        guard let sourceRate = rates[source], let targetRate = rates[target] else {
            if source == "USD" && target == "KHR" { return amount * 4000 }
            if source == "KHR" && target == "USD" { return amount / 4000 }
            return amount
        }
        let amountUSD = amount / Decimal(sourceRate)
        return amountUSD * Decimal(targetRate)
    }

    func deleteTransaction(_ transaction: Transaction) {
        modelContext?.delete(transaction)
        do {
            try modelContext?.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "FilteredTransactionsVM.deleteTransaction")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

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
    var searchText: String = "" {
        didSet {
            searchSubject.send(searchText)
        }
    }
    var sortOption: TransactionSortOption {
        didSet {
            fetchTransactions()
        }
    }

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private let searchSubject = PassthroughSubject<String, Never>()

    /// In-flight fetch; cancelled + generation-checked so rapid search/sort
    /// changes can't apply stale results out of order.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    init(config: TransactionFilterConfig) {
        self.config = config
        self.sortOption = config.defaultSortOption

        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchTransactions()
            }
            .store(in: &cancellables)

        searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
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
        let savingsGoalId = config.savingsGoalId
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates
        let currentSearchText = searchText
        let currentSortOption = sortOption

        isLoading = true

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .userInitiated) {
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

                // Filter by savingsGoalId
                if let savingsGoalId {
                    fetched = fetched.filter { $0.savingsGoal?.id == savingsGoalId }
                }

                // Filter by search text
                let cleanSearch = currentSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanSearch.isEmpty {
                    fetched = fetched.filter { txn in
                        let noteMatch = txn.note?.localizedCaseInsensitiveContains(cleanSearch) ?? false
                        let categoryMatch = txn.category?.name.localizedCaseInsensitiveContains(cleanSearch) ?? false
                        return noteMatch || categoryMatch
                    }
                }

                // Sort based on sortOption
                switch currentSortOption {
                case .newestFirst:
                    fetched.sort { $0.date > $1.date }
                case .oldestFirst:
                    fetched.sort { $0.date < $1.date }
                case .highestAmount:
                    fetched.sort { t1, t2 in
                        let a1 = Self.convert(amount: t1.amount, from: t1.currencyCode, to: preferredCurrency, rates: rates)
                        let a2 = Self.convert(amount: t2.amount, from: t2.currencyCode, to: preferredCurrency, rates: rates)
                        if a1 == a2 {
                            return t1.date > t2.date
                        }
                        return a1 > a2
                    }
                case .lowestAmount:
                    fetched.sort { t1, t2 in
                        let a1 = Self.convert(amount: t1.amount, from: t1.currencyCode, to: preferredCurrency, rates: rates)
                        let a2 = Self.convert(amount: t2.amount, from: t2.currencyCode, to: preferredCurrency, rates: rates)
                        if a1 == a2 {
                            return t1.date > t2.date
                        }
                        return a1 < a2
                    }
                }

                // Calculate total in preferred currency using the shared helper
                let total = TransactionProcessor.calculateTotal(
                    fetched,
                    rates: rates,
                    targetCurrency: preferredCurrency,
                    typeFilter: transactionType == .expense ? .expense : (transactionType == .income ? .income : nil)
                )

                let ids = fetched.map { $0.persistentModelID }

                guard !Task.isCancelled else { return }
                await MainActor.run { [ids, total] in
                    // A newer fetch superseded this one while it was in flight.
                    guard generation == self.refreshGeneration else { return }
                    if let context = self.modelContext {
                        self.transactions = ids.compactMap { context.model(for: $0) as? Transaction }
                    } else {
                        self.transactions = []
                    }
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
        CurrencyManager.convert(amount: amount, from: source, to: target, rates: rates)
    }

    /// Set when a debt-anchor deletion is blocked; drives a redirect alert.
    var blockedDeletionMessage: String?

    func deleteTransaction(_ transaction: Transaction) {
        // A debt's sole advance can't be deleted here — it would orphan the
        // debt. Send the user to the Debts screen to delete the whole record.
        if transaction.isDebtAnchor {
            blockedDeletionMessage = "debt.cannotDeleteAnchor".localized(with: transaction.debt?.personName ?? "")
            HapticManager.shared.warning()
            return
        }

        // Invalidate wallet caches before deleting
        transaction.sourceWallet?.invalidateBalanceCache()
        transaction.destinationWallet?.invalidateBalanceCache()

        modelContext?.delete(transaction)
        do {
            try modelContext?.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "FilteredTransactionsVM.deleteTransaction")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

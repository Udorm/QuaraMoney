import Foundation
import SwiftData
import Combine

@Observable
@MainActor
class FilteredTransactionsViewModel {
    let config: TransactionFilterConfig

    var transactions: [Transaction] = []
    var totalAmount: Decimal = 0
    var totalIsDeterminate = true
    var unconvertedTransactionIDs = Set<UUID>()
    var isLoading = false
    var hasLoadedOnce = false
    var searchText: String = "" {
        didSet {
            searchSubject.send(searchText)
        }
    }
    var sortOption: TransactionSortOption {
        didSet {
            requestRefresh()
        }
    }

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private let searchSubject = PassthroughSubject<String, Never>()

    /// In-flight fetch; cancelled + generation-checked so rapid search/sort
    /// changes can't apply stale results out of order.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var needsRefresh = true

    init(config: TransactionFilterConfig) {
        self.config = config
        self.sortOption = config.defaultSortOption

        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestRefresh()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .currencyRatesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestRefresh()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .preferredCurrencyDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestRefresh()
            }
            .store(in: &cancellables)

        searchSubject
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestRefresh()
            }
            .store(in: &cancellables)
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible && needsRefresh {
            needsRefresh = false
            fetchTransactions()
        }
    }

    private func requestRefresh() {
        if isVisible {
            fetchTransactions()
        } else {
            needsRefresh = true
        }
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
        let summaryCurrency = config.summaryCurrencyCode ?? preferredCurrency
        let reportExclusionPolicy = config.reportExclusionPolicy
        let archivedWalletPolicy = config.archivedWalletPolicy
        let conversionPolicy = config.conversionPolicy
        let budgetRelevancePolicy = config.budgetRelevancePolicy
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
                walletId: walletId,
                excludeArchivedWallets: archivedWalletPolicy == .exclude
            )

            do {
                var fetched = try context.fetch(descriptor)

                if reportExclusionPolicy == .exclude {
                    fetched = fetched.filter { !$0.excludeFromReports }
                }

                if budgetRelevancePolicy == .sharedPredicate {
                    let budgetCategoryIDs = Set(categoryIds ?? categoryId.map { [$0] } ?? [])
                    let targetKind: BudgetTargetKind = budgetCategoryIDs.isEmpty ? .total : .categories
                    let range = PlanDateRange(start: start, end: end)
                    fetched = fetched.filter { transaction in
                        let kind: PlanTransactionKind = switch transaction.type {
                        case .income: .income
                        case .expense: .expense
                        case .transfer: .transfer
                        case .adjustment: .adjustment
                        }
                        let snapshot = PlanTransactionSnapshot(
                            id: transaction.id,
                            date: transaction.date,
                            kind: kind,
                            amount: transaction.amount,
                            currencyCode: transaction.currencyCode,
                            categoryID: transaction.category?.id,
                            isDeleted: transaction.deletedAt != nil,
                            isEventLinked: transaction.event != nil,
                            isExcludedFromReports: transaction.excludeFromReports,
                            sourceWalletIsArchived: transaction.sourceWallet?.isArchived == true
                        )
                        return BudgetTransactionRelevance.isRelevant(
                            snapshot,
                            targetKind: targetKind,
                            categoryIDs: budgetCategoryIDs,
                            in: range
                        )
                    }
                }

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
                        Self.amountSort(
                            t1, t2, ascending: false, currency: summaryCurrency,
                            rates: rates, policy: conversionPolicy
                        )
                    }
                case .lowestAmount:
                    fetched.sort { t1, t2 in
                        Self.amountSort(
                            t1, t2, ascending: true, currency: summaryCurrency,
                            rates: rates, policy: conversionPolicy
                        )
                    }
                }

                let totalResult = Self.total(
                    transactions: fetched,
                    rates: rates,
                    targetCurrency: summaryCurrency,
                    typeFilter: transactionType,
                    policy: conversionPolicy
                )
                let unconvertedIDs = Set(fetched.compactMap { transaction in
                    conversionPolicy.convert(
                        amount: transaction.amount,
                        from: transaction.currencyCode,
                        to: summaryCurrency,
                        rates: rates
                    ) == nil ? transaction.id : nil
                })

                let ids = fetched.map { $0.persistentModelID }

                guard !Task.isCancelled else { return }
                await MainActor.run { [ids, totalResult, unconvertedIDs] in
                    // A newer fetch superseded this one while it was in flight.
                    guard generation == self.refreshGeneration else { return }
                    if let context = self.modelContext {
                        self.transactions = ids.compactMap { context.model(for: $0) as? Transaction }
                    } else {
                        self.transactions = []
                    }
                    self.totalAmount = totalResult.total
                    self.totalIsDeterminate = totalResult.isDeterminate
                    self.unconvertedTransactionIDs = unconvertedIDs
                    self.isLoading = false
                    self.hasLoadedOnce = true
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    nonisolated static func amountSort(
        _ lhs: Transaction,
        _ rhs: Transaction,
        ascending: Bool,
        currency: String,
        rates: [String: Double],
        policy: TransactionConversionPolicy
    ) -> Bool {
        let left = policy.convert(amount: lhs.amount, from: lhs.currencyCode, to: currency, rates: rates)
        let right = policy.convert(amount: rhs.amount, from: rhs.currencyCode, to: currency, rates: rates)
        switch (left, right) {
        case let (left?, right?):
            if left != right { return ascending ? left < right : left > right }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated static func total(
        transactions: [Transaction],
        rates: [String: Double],
        targetCurrency: String,
        typeFilter: TransactionTypeFilter?,
        policy: TransactionConversionPolicy
    ) -> (total: Decimal, isDeterminate: Bool) {
        if policy == .legacyFallback {
            return (
                TransactionProcessor.calculateTotal(
                    transactions,
                    rates: rates,
                    targetCurrency: targetCurrency,
                    typeFilter: typeFilter == .expense ? .expense : (typeFilter == .income ? .income : nil)
                ),
                true
            )
        }

        var total: Decimal = 0
        var isDeterminate = true
        for transaction in transactions where !transaction.excludeFromReports {
            if typeFilter == .expense, transaction.type != .expense { continue }
            if typeFilter == .income, transaction.type != .income { continue }
            guard let converted = policy.convert(
                amount: transaction.amount,
                from: transaction.currencyCode,
                to: targetCurrency,
                rates: rates
            ) else {
                isDeterminate = false
                continue
            }
            switch transaction.type {
            case .income: total += converted
            case .expense: total += typeFilter == nil ? -converted : converted
            case .transfer: if typeFilter == nil { total += converted }
            case .adjustment: total += converted
            }
        }
        return (total, isDeterminate)
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

        SoftDeleteService.deleteTransaction(transaction)
        do {
            try modelContext?.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "FilteredTransactionsVM.deleteTransaction")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

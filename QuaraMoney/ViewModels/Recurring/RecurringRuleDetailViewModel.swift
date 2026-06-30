import Foundation
import SwiftData
import SwiftUI
import Combine

@Observable
@MainActor
class RecurringRuleDetailViewModel {
    @ObservationIgnored private var modelContext: ModelContext
    let rule: RecurringRule

    var sortOption: TransactionSortOption = .newestFirst {
        didSet { fetchTransactions() }
    }

    var transactions: [Transaction] = []

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    init(modelContext: ModelContext, rule: RecurringRule) {
        self.modelContext = modelContext
        self.rule = rule

        // Listen for data updates
        NotificationCenter.default.publisher(for: .dataDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchTransactions()
            }
            .store(in: &cancellables)
    }

    func fetchTransactions() {
        let currentSortOption = sortOption
        
        // Use relationship directly to avoid SwiftData predicate relationship-chaining bugs
        let fetched = (rule.generatedTransactions ?? []).filter { $0.deletedAt == nil }
        
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates
        
        var sorted = fetched
        switch currentSortOption {
        case .newestFirst:
            sorted.sort { $0.date > $1.date }
        case .oldestFirst:
            sorted.sort { $0.date < $1.date }
        case .highestAmount:
            sorted.sort { t1, t2 in
                let a1 = CurrencyManager.convert(amount: t1.amount, from: t1.currencyCode, to: targetCurrency, rates: rates)
                let a2 = CurrencyManager.convert(amount: t2.amount, from: t2.currencyCode, to: targetCurrency, rates: rates)
                if a1 == a2 { return t1.date > t2.date }
                return a1 > a2
            }
        case .lowestAmount:
            sorted.sort { t1, t2 in
                let a1 = CurrencyManager.convert(amount: t1.amount, from: t1.currencyCode, to: targetCurrency, rates: rates)
                let a2 = CurrencyManager.convert(amount: t2.amount, from: t2.currencyCode, to: targetCurrency, rates: rates)
                if a1 == a2 { return t1.date > t2.date }
                return a1 < a2
            }
        }
        
        self.transactions = sorted
    }
    
    func deleteTransaction(_ transaction: Transaction) {
        SoftDeleteService.deleteTransaction(transaction)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            fetchTransactions()
        } catch {
            #if DEBUG
            print("Error deleting transaction: \(error)")
            #endif
        }
    }
}

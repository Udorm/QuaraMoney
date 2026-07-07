import SwiftUI
import SwiftData

struct AddTransactionContainer: View {
    @Environment(\.modelContext) private var modelContext
    /// Experimental one-screen entry form (More → Settings). The classic view
    /// remains the default; both versions share the same view model.
    @AppStorage("useCompactTransactionEntry") private var useCompactTransactionEntry = false
    let transaction: Transaction?
    let isNewTransaction: Bool
    let initialDate: Date?
    let initialWallet: Wallet?
    let initialDebt: Debt?
    let initialCategory: Category?
    let initialAmount: Decimal?
    let initialType: TransactionType?

    init(
        transaction: Transaction? = nil,
        isNewTransaction: Bool = true,
        initialDate: Date? = nil,
        initialWallet: Wallet? = nil,
        initialDebt: Debt? = nil,
        initialCategory: Category? = nil,
        initialAmount: Decimal? = nil,
        initialType: TransactionType? = nil
    ) {
        self.transaction = transaction
        self.isNewTransaction = isNewTransaction
        self.initialDate = initialDate
        self.initialWallet = initialWallet
        self.initialDebt = initialDebt
        self.initialCategory = initialCategory
        self.initialAmount = initialAmount
        self.initialType = initialType
    }

    /// Debt-linked and balance-adjustment entries render locked, special-cased
    /// UI that only the classic screen implements — they always fall back.
    private var usesCompactEntry: Bool {
        guard useCompactTransactionEntry else { return false }
        if initialDebt != nil || transaction?.debt != nil { return false }
        if transaction?.type == .adjustment || initialType == .adjustment { return false }
        return true
    }

    var body: some View {
        let viewModel = AddTransactionViewModel(
            dataService: SwiftDataService(modelContext: modelContext),
            initialWallet: initialWallet,
            transaction: transaction,
            initialDate: initialDate,
            initialDebt: initialDebt,
            initialCategory: initialCategory,
            initialAmount: initialAmount,
            initialType: initialType
        )

        if usesCompactEntry {
            CompactAddTransactionView(viewModel: viewModel, isNewTransaction: isNewTransaction)
        } else {
            AddTransactionView(viewModel: viewModel, isNewTransaction: isNewTransaction)
        }
    }
}

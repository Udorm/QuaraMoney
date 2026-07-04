import SwiftUI
import SwiftData

struct AddTransactionContainer: View {
    @Environment(\.modelContext) private var modelContext
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

    var body: some View {
        AddTransactionView(
            viewModel: AddTransactionViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                initialWallet: initialWallet,
                transaction: transaction,
                initialDate: initialDate,
                initialDebt: initialDebt,
                initialCategory: initialCategory,
                initialAmount: initialAmount,
                initialType: initialType
            ),
            isNewTransaction: isNewTransaction
        )
    }
}

import SwiftUI
import SwiftData

struct AddTransactionContainer: View {
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction?
    let isNewTransaction: Bool
    let startWithScanner: Bool
    let initialDate: Date?
    let initialWallet: Wallet?
    let initialDebt: Debt?
    let initialCategory: Category?

    init(
        transaction: Transaction? = nil,
        isNewTransaction: Bool = true,
        startWithScanner: Bool = false,
        initialDate: Date? = nil,
        initialWallet: Wallet? = nil,
        initialDebt: Debt? = nil,
        initialCategory: Category? = nil
    ) {
        self.transaction = transaction
        self.isNewTransaction = isNewTransaction
        self.startWithScanner = startWithScanner
        self.initialDate = initialDate
        self.initialWallet = initialWallet
        self.initialDebt = initialDebt
        self.initialCategory = initialCategory
    }

    var body: some View {
        AddTransactionView(
            viewModel: AddTransactionViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                initialWallet: initialWallet,
                transaction: transaction,
                initialDate: initialDate,
                initialDebt: initialDebt,
                initialCategory: initialCategory
            ),
            isNewTransaction: isNewTransaction,
            startWithScanner: startWithScanner
        )
    }
}

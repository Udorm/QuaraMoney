import SwiftUI
import SwiftData

struct AddTransactionContainer: View {
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction?
    let isNewTransaction: Bool
    let startWithScanner: Bool
    let initialDate: Date?
    let initialWallet: Wallet?

    init(
        transaction: Transaction? = nil,
        isNewTransaction: Bool = true,
        startWithScanner: Bool = false,
        initialDate: Date? = nil,
        initialWallet: Wallet? = nil
    ) {
        self.transaction = transaction
        self.isNewTransaction = isNewTransaction
        self.startWithScanner = startWithScanner
        self.initialDate = initialDate
        self.initialWallet = initialWallet
    }

    var body: some View {
        AddTransactionView(
            viewModel: AddTransactionViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                initialWallet: initialWallet,
                transaction: transaction,
                initialDate: initialDate
            ),
            isNewTransaction: isNewTransaction,
            startWithScanner: startWithScanner
        )
    }
}

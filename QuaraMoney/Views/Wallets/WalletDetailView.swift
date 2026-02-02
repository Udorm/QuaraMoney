import SwiftUI
import SwiftData

struct WalletDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: WalletDetailViewModel
    
    @State private var showingAddTransaction = false
    @State private var showingCustomDateSheet = false
    
    @State private var transactionToEdit: Transaction?
    
    init(wallet: Wallet, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: WalletDetailViewModel(modelContext: modelContext, wallet: wallet))
    }
    
    var body: some View {
        List {
            // Header Section (Balance)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Balance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(viewModel.wallet.balance.formatted(.currency(code: viewModel.wallet.currencyCode)))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            
            // Transactions List (grouped by date using reusable component)
            if viewModel.transactions.isEmpty {
                Section(header: Text(viewModel.filterDescription).font(.subheadline).textCase(nil)) {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "list.bullet.clipboard",
                        description: Text("No transactions in this period.")
                    )
                }
            } else {
                TransactionListView(
                    transactions: viewModel.transactions,
                    onEdit: { txn in
                        transactionToEdit = txn
                    },
                    onDelete: { txn in
                        viewModel.deleteTransaction(txn)
                    }
                )
            }
        }
        .navigationTitle(viewModel.wallet.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddTransaction = true }) {
                    Label("Add Transaction", systemImage: "plus")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                FilterMenuView(
                    selectedPeriod: $viewModel.selectedPeriod,
                    selectedWallet: .constant(nil),
                    wallets: [],
                    showWalletFilter: false,
                    onCustomPeriodSelect: {
                        showingCustomDateSheet = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    initialWallet: viewModel.wallet
                ),
                isNewTransaction: true
            )
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    initialWallet: viewModel.wallet,
                    transaction: txn
                ),
                isNewTransaction: false
            )
        }
        .sheet(isPresented: $showingCustomDateSheet) {
            NavigationStack {
                Form {
                    DatePicker("Start Date", selection: $viewModel.customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $viewModel.customEndDate, displayedComponents: .date)
                }
                .navigationTitle("Custom Range")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            viewModel.selectedPeriod = .custom
                            showingCustomDateSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            viewModel.fetchTransactions()
        }
        .onChange(of: showingAddTransaction) { oldValue, newValue in
            if !newValue {
                viewModel.fetchTransactions()
                // Wallet balance might have changed, need to refresh context or wallet object?
                // The wallet object passed in generic init might be stale?
                // Often better to fetch wallet by ID or rely on SwiftData observability if Wallet is Observable.
                // Wallet is @Model, so it's Observable. changes should reflect.
            }
        }
        .onChange(of: transactionToEdit) { oldValue, newValue in
            if newValue == nil {
                 viewModel.fetchTransactions()
            }
        }
    }
}


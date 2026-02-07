import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: HomeViewModel
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var isSearchPresented = false
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Summary Section
                Section(header: Text(viewModel.filterDescription).font(.app(.subheadline)).textCase(nil)) {
                    FinancialSummaryCards(income: viewModel.incomeTotal, expense: viewModel.expenseTotal)
                }

                
                // Daily Transactions
                ForEach(viewModel.dailySections) { section in
                    Section(header: DailyHeader(section: section)) {
                        ForEach(section.transactions) { txn in
                            Button {
                                transactionToEdit = txn
                            } label: {
                                TransactionRowView(transaction: txn)
                            }
                            .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.deleteTransaction(txn)
                                    } label: {
                                        Label(L10n.Common.delete, systemImage: "trash")
                                    }
                                    
                                    Button {
                                        transactionToEdit = txn
                                    } label: {
                                        Label(L10n.Common.edit, systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                                .contextMenu {
                                    Button {
                                        transactionToEdit = txn
                                    } label: {
                                        Label(L10n.Common.edit, systemImage: "pencil")
                                            .font(.app(.body))
                                    }
                                    Button(role: .destructive) {
                                        viewModel.deleteTransaction(txn)
                                    } label: {
                                        Label(L10n.Common.delete, systemImage: "trash")
                                            .font(.app(.body))
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Home.title)
            .searchable(text: $viewModel.searchText, isPresented: $isSearchPresented)
            .onAppear {
                viewModel.refreshData()
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionContainer(transaction: nil, isNewTransaction: true)
            }
            .sheet(item: $transactionToEdit) { txn in
                AddTransactionContainer(transaction: txn, isNewTransaction: false)
            }
            .onChange(of: showingAddTransaction) { oldValue, newValue in
                if !newValue {
                    viewModel.refreshData()
                }
            }
            .onChange(of: transactionToEdit) { oldValue, newValue in
                if newValue == nil {
                     viewModel.refreshData()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Search Button
                    Button {
                        isSearchPresented = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }

                    FilterSheetButton(
                        selectedPeriod: $viewModel.selectedPeriod,
                        selectedWallet: $viewModel.selectedWallet,
                        customStartDate: $viewModel.customStartDate,
                        customEndDate: $viewModel.customEndDate,
                        wallets: wallets,
                        defaultPeriod: .thisMonth
                    )
                    
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }
}




// Wrapper to handle ViewModel creation
struct AddTransactionContainer: View {
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction?
    let isNewTransaction: Bool
    
    init(transaction: Transaction? = nil, isNewTransaction: Bool = true) {
        self.transaction = transaction
        self.isNewTransaction = isNewTransaction
    }
    
    var body: some View {
        AddTransactionView(
            viewModel: AddTransactionViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                initialWallet: nil,
                transaction: transaction
            ),
            isNewTransaction: isNewTransaction
        )
    }
}
struct DailyHeader: View {
    let section: DailyTransactionSection
    
    var body: some View {
        HStack {
            Text(section.date.formatted(date: .long, time: .omitted))
                .font(.app(.headline))
            Spacer()
            // Here we want to see the daily total in the DASHBOARD currency, likely.
            // The view model already calculated dailyTotal in the preferred currency.
            Text(section.dailyTotal.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                .font(.app(.subheadline))
                .foregroundStyle(section.dailyTotal >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
        }
        .padding(.vertical, 4)
    }
}
// Reusing TransactionRow if it exists, otherwise defining a simple one.
// I think we defined TransactionRow in WalletDetailView?
// I should likely move it to a shared file or redefine it here.
// I will verify if I can import or redefine.
// Let's use a simple one here for now.





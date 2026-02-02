import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: HomeViewModel
    @State private var showingAddTransaction = false
    @State private var showingCustomDateSheet = false
    @State private var transactionToEdit: Transaction?
    @Query private var wallets: [Wallet]
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                // Main Content
                List {
                    // Summary Section
                    Section(header: Text(viewModel.filterDescription).font(.subheadline).textCase(nil)) {
                        FinancialSummaryCards(income: viewModel.incomeTotal, expense: viewModel.expenseTotal)
                            .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    
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
                                            Label("Delete", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            transactionToEdit = txn
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                                    .contextMenu {
                                        Button {
                                            transactionToEdit = txn
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            viewModel.deleteTransaction(txn)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                
                // FAB
                Button(action: { showingAddTransaction = true }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(radius: 4, y: 4)
                }
                .padding()
            }
            .navigationTitle("Home")
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
                ToolbarItem(placement: .topBarTrailing) {
                    FilterMenuView(
                        selectedPeriod: $viewModel.selectedPeriod,
                        selectedWallet: $viewModel.selectedWallet,
                        wallets: wallets,
                        onCustomPeriodSelect: {
                            showingCustomDateSheet = true
                        }
                    )
                }
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
            Text(section.date, style: .date)
                .font(.headline)
            Spacer()
            // Here we want to see the daily total in the DASHBOARD currency, likely.
            // The view model already calculated dailyTotal in the preferred currency.
            Text(section.dailyTotal.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                .font(.subheadline)
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



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
                        VStack(spacing: 16) {
                            HStack(spacing: 20) {
                                SummaryCard(title: "Income", amount: viewModel.incomeTotal, color: .green, icon: "arrow.down.left")
                                SummaryCard(title: "Expense", amount: viewModel.expenseTotal, color: .red, icon: "arrow.up.right")
                            }
                            
                            HStack {
                                Text("Net:")
                                    .foregroundStyle(.secondary)
                                Text((viewModel.incomeTotal - viewModel.expenseTotal).formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                                    .fontWeight(.bold)
                                    .foregroundStyle((viewModel.incomeTotal - viewModel.expenseTotal) >= 0 ? Color.primary : Color.red)
                            }
                        }
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
                    Menu {
                        Section("Period") {
                            ForEach(HomeViewModel.Period.allCases) { period in
                                Button {
                                    if period == .custom {
                                        showingCustomDateSheet = true
                                    } else {
                                        viewModel.selectedPeriod = period
                                    }
                                } label: {
                                    if viewModel.selectedPeriod == period {
                                        Label(period.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(period.rawValue)
                                    }
                                }
                            }
                        }
                        
                        Section("Wallet") {
                            Button {
                                viewModel.selectedWallet = nil
                            } label: {
                                if viewModel.selectedWallet == nil {
                                    Label("All Wallets", systemImage: "checkmark")
                                } else {
                                    Text("All Wallets")
                                }
                            }
                            
                            ForEach(wallets) { wallet in
                                Button {
                                    viewModel.selectedWallet = wallet
                                } label: {
                                    if viewModel.selectedWallet?.id == wallet.id {
                                        Label(wallet.name, systemImage: "checkmark")
                                    } else {
                                        Text(wallet.name)
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundStyle(viewModel.isFilterActive ? .blue : .primary)
                    }
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

struct SummaryCard: View {
    let title: String
    let amount: Decimal
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .padding(6)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(amount.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))
                .font(.headline)
                .fontWeight(.bold)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
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
                .foregroundStyle(section.dailyTotal >= 0 ? .green : .red)
        }
        .padding(.vertical, 4)
    }
}

// Reusing TransactionRow if it exists, otherwise defining a simple one.
// I think we defined TransactionRow in WalletDetailView?
// I should likely move it to a shared file or redefine it here.
// I will verify if I can import or redefine.
// Let's use a simple one here for now.



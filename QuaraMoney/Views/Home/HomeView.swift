import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: HomeViewModel
    @State private var showingAddTransaction = false
    @State private var showingScanner = false
    @State private var transactionToEdit: Transaction?
    @State private var isSearchPresented = false
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month Selection Tab Bar
                MonthSelectionView(
                    selectedDate: $viewModel.selectedMonth,
                    months: viewModel.availableMonths
                )
                .padding(.bottom, 8)
                .background(Color(uiColor: .systemBackground))
                
                List {
                    // Summary Section
                    if viewModel.selectedWallet != nil {
                        Section(header: Text(viewModel.filterDescription).font(.app(.subheadline)).textCase(nil)) {
                            FinancialSummaryCards(income: viewModel.incomeTotal, expense: viewModel.expenseTotal)
                        }
                    } else {
                        Section {
                             FinancialSummaryCards(income: viewModel.incomeTotal, expense: viewModel.expenseTotal)
                        }
                    }

                    // Quick Actions Section
                    Section {
                        QuickActionsView(
                            onAdd: { showingAddTransaction = true },
                            onScan: { showingScanner = true }
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    
                    // Daily Transactions
                    ForEach(viewModel.dailySections) { section in
                        Section(header: DailyHeader(section: section)) {
                            ForEach(section.transactions) { txn in
                                HomeTransactionRow(
                                    transaction: txn,
                                    onEdit: { transactionToEdit = txn },
                                    onDelete: { viewModel.deleteTransaction(txn) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(L10n.Home.title)
            .searchable(text: $viewModel.searchText)
            .searchToolbarBehavior(.minimize)
            .onAppear {
                viewModel.refreshData()
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionContainer(transaction: nil, isNewTransaction: true, showScanner: false)
            }
            .sheet(isPresented: $showingScanner) {
                AddTransactionContainer(transaction: nil, isNewTransaction: true, showScanner: true)
            }
            .sheet(item: $transactionToEdit) { txn in
                AddTransactionContainer(transaction: txn, isNewTransaction: false, showScanner: false)
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
                    Button {
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "plus")
                    }

                    FilterSheetButton(
                        selectedPeriod: $viewModel.selectedPeriod,
                        selectedWallet: $viewModel.selectedWallet,
                        customStartDate: $viewModel.customStartDate,
                        customEndDate: $viewModel.customEndDate,
                        wallets: wallets,
                        defaultPeriod: .thisMonth,
                        showPeriodFilter: false
                    )
                }
                
            }
        }
    }
}

// Subview for Transaction Row to reduce complexity
struct HomeTransactionRow: View {
    let transaction: Transaction
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onEdit) {
            TransactionRowView(transaction: transaction)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label(L10n.Common.delete, systemImage: "trash")
            }
            
            Button(action: onEdit) {
                Label(L10n.Common.edit, systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(action: onEdit) {
                Label(L10n.Common.edit, systemImage: "pencil")
                    .font(.app(.body))
            }
            Button(role: .destructive, action: onDelete) {
                Label(L10n.Common.delete, systemImage: "trash")
                    .font(.app(.body))
            }
        }
    }
}

// Wrapper to handle ViewModel creation
struct AddTransactionContainer: View {
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction?
    let isNewTransaction: Bool
    let showScanner: Bool
    
    init(transaction: Transaction? = nil, isNewTransaction: Bool = true, showScanner: Bool = false) {
        self.transaction = transaction
        self.isNewTransaction = isNewTransaction
        self.showScanner = showScanner
    }
    
    var body: some View {
        AddTransactionView(
            viewModel: AddTransactionViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                initialWallet: nil,
                transaction: transaction
            ),
            isNewTransaction: isNewTransaction,
            initialShowScanner: showScanner
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
            Text(section.dailyTotal.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode).presentation(.narrow)))
                .font(.app(.subheadline))
                .foregroundStyle(section.dailyTotal >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
        }
        .padding(.vertical, 4)
    }
}

struct QuickActionsView: View {
    let onAdd: () -> Void
    let onScan: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            QuickActionButton(
                title: L10n.Common.add,
                icon: "plus",
                color: ThemeManager.shared.incomeColor,
                action: onAdd
            )
            
            QuickActionButton(
                title: L10n.Transaction.scanReceipt,
                icon: "doc.text.viewfinder",
                color: .blue,
                action: onScan
            )
            
            // Placeholder for potential future "Transfer" button
            QuickActionButton(
                title: "Report",
                icon: "chart.pie.fill",
                color: .orange,
                action: { } // Navigate to analysis?
            )
            .opacity(0.6) // Not implemented yet
        }
        .padding(.horizontal)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.app(.title3))
                    .frame(width: 50, height: 50)
                    .background(color.opacity(0.1))
                    .foregroundStyle(color)
                    .clipShape(Circle())
                
                Text(title)
                    .font(.app(.caption))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .shadow(color: Color.primary.opacity(0.05), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
// Reusing TransactionRow if it exists, otherwise defining a simple one.
// I think we defined TransactionRow in WalletDetailView?
// I should likely move it to a shared file or redefine it here.
// I will verify if I can import or redefine.
// Let's use a simple one here for now.





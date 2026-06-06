import SwiftUI
import SwiftData

private struct BackdateTarget: Identifiable, Equatable {
    let id = UUID()
    let date: Date
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HomeViewModel
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var isSearchPresented = false
    @State private var shouldScan = false
    @State private var backdateTarget: BackdateTarget?
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    
    init(modelContext: ModelContext) {
        _viewModel = State(wrappedValue: HomeViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transactionList
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                Button {
                    shouldScan = false
                    showingAddTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
                .modifier(AddTransactionFABStyle())
                .controlSize(.large)
                .padding(.trailing)
                .padding(.bottom, 8)
            }
            .navigationTitle(L10n.Home.title)
            .searchable(text: $viewModel.searchText)
            .searchToolbarBehavior(.minimize)
            .task {
                // Yield briefly to let the first frame render before querying DB
                try? await Task.sleep(for: .milliseconds(100))
                viewModel.refreshData()
            }
            .sheet(isPresented: $showingAddTransaction, onDismiss: { shouldScan = false }) {
                AddTransactionContainer(transaction: nil, isNewTransaction: true, startWithScanner: shouldScan)
            }
            .sheet(item: $transactionToEdit) { txn in
                AddTransactionContainer(transaction: txn, isNewTransaction: false)
            }
            .sheet(item: $backdateTarget) { target in
                AddTransactionContainer(transaction: nil, isNewTransaction: true, initialDate: target.date)
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
            .onChange(of: backdateTarget) { oldValue, newValue in
                if newValue == nil {
                    viewModel.refreshData()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        shouldScan = true
                        showingAddTransaction = true
                    } label: {
                        Image(systemName: "doc.text.viewfinder")
                    }
                    .accessibilityLabel("Scan receipt")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker(selection: $viewModel.sortOption, label: Text(L10n.Sort.title)) {
                            ForEach(TransactionSortOption.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort transactions")

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

    private var currentPeriodText: String {
        switch viewModel.selectedTab {
        case .month(let date):
            let calendar = Calendar.current
            if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
                return L10n.Filter.thisMonth
            } else if let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()),
                      calendar.isDate(date, equalTo: lastMonth, toGranularity: .month) {
                return L10n.Filter.lastMonth
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: date)
            }
        case .custom:
            let start = viewModel.customStartDate.formatted(.dateTime.month(.abbreviated).day())
            let end = viewModel.customEndDate.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(start) – \(end)"
        }
    }

    private var summaryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            if viewModel.selectedWallet != nil {
                Text(viewModel.filterDescription)
                    .font(.app(.subheadline))
            }
            Spacer()
            Text(currentPeriodText)
                .font(.app(.subheadline))
                .foregroundStyle(viewModel.selectedWallet != nil ? .secondary : .primary)
        }
        .textCase(nil)
        .padding(.top, -8)  // Tighten the gap between the picker section and the summary card
    }

    private var transactionList: some View {
        List {
            Section {
                MonthSelectionView(
                    selectedTab: $viewModel.selectedTab,
                    months: Array(viewModel.availableMonths.suffix(3))
                )

                if case .custom = viewModel.selectedTab {
                    HStack {
                        Spacer()
                        DatePicker("Start", selection: $viewModel.customStartDate, displayedComponents: .date)
                            .labelsHidden()
                            .font(.app(.headline))
                        Text("-")
                            .foregroundStyle(.secondary)
                            .font(.app(.headline))
                        DatePicker("End", selection: $viewModel.customEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .font(.app(.headline))
                        Spacer()
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            // Summary Section
            Section(header: summaryHeader) {
                FinancialSummaryCards(
                    income: viewModel.incomeTotal,
                    expense: viewModel.expenseTotal,
                    dailySections: viewModel.dailySections,
                    startDate: viewModel.currentStartDate,
                    endDate: viewModel.currentEndDate,
                    previousPeriodCumulative: viewModel.previousPeriodCumulative
                )
            }

            // Daily Transactions or sorted flat list
            if viewModel.sortOption == .highestAmount || viewModel.sortOption == .lowestAmount {
                ForEach(viewModel.sortedTransactions) { txn in
                    HomeTransactionRow(
                        transaction: txn,
                        onEdit: { transactionToEdit = txn },
                        onDelete: { viewModel.deleteTransaction(txn) }
                    )
                }
            } else {
                ForEach(viewModel.dailySections) { section in
                    Section(header: DailyHeader(section: section, onAddTapped: {
                        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: section.date) ?? section.date
                        backdateTarget = BackdateTarget(date: noon)
                    })) {
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
        }
        .listStyle(.insetGrouped)
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
struct DailyHeader: View {
    let section: DailyTransactionSection
    var onAddTapped: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(section.date.formatted(date: .long, time: .omitted))
                .font(.app(.headline))
            Spacer()
            Text(section.dailyTotal.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                .font(.app(.subheadline))
                .foregroundStyle(section.dailyTotal >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
            if let onAddTapped {
                Button(action: onAddTapped) {
                    Image(systemName: "plus.circle")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .accessibilityLabel("Add transaction on \(section.date.formatted(date: .long, time: .omitted))")
            }
        }
        .padding(.vertical, 4)
    }
}


// Reusing TransactionRow if it exists, otherwise defining a simple one.
// I think we defined TransactionRow in WalletDetailView?
// I should likely move it to a shared file or redefine it here.
// I will verify if I can import or redefine.
// Let's use a simple one here for now.


private struct AddTransactionFABStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glassProminent)
                .clipShape(.circle)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .clipShape(.circle)
        }
    }
}

#Preview("HomeView") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Wallet.self, Transaction.self, TransactionLocation.self, Category.self, configurations: configuration)
    let context = container.mainContext

    // Seed minimal preview data if empty
    if try! context.fetch(FetchDescriptor<Wallet>()).isEmpty {
        let wallet = Wallet(name: "Personal", currencyCode: "USD", icon: "wallet.pass", colorHex: "#4F46E5")
        let groceries = Category(name: "Groceries", icon: "cart", colorHex: "#EF4444", type: .expense)
        let salary = Category(name: "Salary", icon: "banknote", colorHex: "#10B981", type: .income)

        context.insert(wallet)
        context.insert(groceries)
        context.insert(salary)
        let now = Date()
        let t1 = Transaction(amount: 24.99, currencyCode: "USD", date: now, type: .expense)
        t1.note = "Market run"
        t1.sourceWallet = wallet
        t1.category = groceries
        
        let t2 = Transaction(amount: 1500.00, currencyCode: "USD", date: Calendar.current.date(byAdding: .day, value: -1, to: now)!, type: .income)
        t2.note = "Monthly salary"
        t2.sourceWallet = wallet
        t2.category = salary
        
        context.insert(t1)
        context.insert(t2)

        try? context.save()
    }

    return HomeView(modelContext: context)
        .modelContainer(container)
}

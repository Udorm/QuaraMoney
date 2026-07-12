import SwiftUI
import SwiftData

private struct BackdateTarget: Identifiable, Equatable {
    let id = UUID()
    let date: Date
}

/// Thin wrapper that creates the view model lazily on first appearance.
/// `State(wrappedValue:)` evaluates its argument on *every* init of the view,
/// so building the VM there meant a throwaway `HomeViewModel` (months array +
/// two Combine subscriptions) was constructed each time ContentView's body
/// re-evaluated. The optional-@State + onAppear idiom constructs it exactly once.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: HomeViewModel?

    var body: some View {
        Group {
            if let viewModel {
                HomeContentView(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HomeViewModel(modelContext: modelContext)
            }
        }
    }
}

struct HomeContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: HomeViewModel
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var isSearchPresented = false
    @State private var backdateTarget: BackdateTarget?
    @State private var isVisible = false
    private var router = AppRouter.shared
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transactionList
                    .refreshable {
                        await SyncEngine.shared.syncIfOperational(context: modelContext)
                    }
            }
            .undoToast($viewModel.recentlyDeleted, message: { _ in
                "transaction.deletedToast".localized
            }, onUndo: { token in
                viewModel.undoDelete(token)
            })
            .safeAreaInset(edge: .bottom, alignment: .trailing) {
                Button {
                    showingAddTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
                .modifier(CircularFABStyle())
                .controlSize(.large)
                .padding(.trailing)
                .padding(.bottom, 8)
            }
            .navigationTitle("QuaraMoney")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchText)
            .searchToolbarBehavior(.minimize)
            // Visibility gating: the VM refreshes on .dataDidUpdate only while
            // this tab is on screen; changes that arrive while hidden are
            // applied on the next appearance. The first onAppear also performs
            // the initial load (the fetch itself runs off-main, so it doesn't
            // block the first frame).
            .onAppear {
                isVisible = true
                viewModel.setVisible(true)
                consumePendingAddTransaction()
            }
            .onDisappear {
                isVisible = false
                viewModel.setVisible(false)
            }
            .sheet(isPresented: $showingAddTransaction) {
                AddTransactionContainer(transaction: nil, isNewTransaction: true)
            }
            .sheet(item: $transactionToEdit) { txn in
                AddTransactionContainer(transaction: txn, isNewTransaction: false)
            }
            .debtDeletionBlockedAlert($viewModel.blockedDeletionMessage)
            .sheet(item: $backdateTarget) { target in
                AddTransactionContainer(transaction: nil, isNewTransaction: true, initialDate: target.date)
            }
            // NOTE: no onChange(sheet-dismissed) refreshes here — saves post
            // .dataDidUpdate, which is the single refresh channel. The old
            // dismissal hooks triple-fetched the same data during the dismiss
            // animation.
            // Quick-action deep link (warm or cold launch): ContentView/the App
            // stage the intent on the router; we consume it only while actually
            // visible, so the presentation can never be swallowed by a
            // mid-animation tab switch — and never waits on an arbitrary timer.
            .onChange(of: router.pendingAddTransaction) { _, _ in
                consumePendingAddTransaction()
            }
            .toolbar {
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
                    .accessibilityLabel("a11y.sortTransactions".localized)

                    FilterSheetButton(
                        selectedPeriod: $viewModel.selectedPeriod,
                        selectedWalletIds: $viewModel.selectedWalletIds,
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

    /// Presents the Add Transaction sheet for a staged quick-action intent,
    /// but only while this tab is actually on screen.
    private func consumePendingAddTransaction() {
        guard isVisible, router.pendingAddTransaction else { return }
        router.pendingAddTransaction = false
        showingAddTransaction = true
    }

    private var summaryHeader: some View {
        HStack {
            Text(walletFilterDescription)
                .appFont(.subheadline)
            Spacer()
        }
        .textCase(nil)
    }

    private var walletFilterDescription: String {
        let ids = viewModel.selectedWalletIds
        if ids.count == 1, let wallet = wallets.first(where: { ids.contains($0.id) }) {
            return wallet.name
        }
        return "analysis.pro.filter.nSelected".localized(with: ids.count)
    }

    /// Brand-new user (or fresh install): nothing recorded at all, ever.
    private var isFirstRunEmpty: Bool {
        viewModel.hasLoadedOnce && !viewModel.hasAnyTransactions && viewModel.searchText.isEmpty
    }

    /// The current period/search yielded no rows (but data exists elsewhere).
    private var isResultEmpty: Bool {
        viewModel.hasLoadedOnce && viewModel.dailySections.isEmpty && viewModel.sortedTransactions.isEmpty
    }

    private var transactionList: some View {
        List {
            if isFirstRunEmpty {
                Section {
                    AppEmptyStateView(
                        "home.empty.title".localized,
                        systemImage: "list.bullet.rectangle.portrait",
                        description: "home.empty.message".localized
                    ) {
                        Button {
                            showingAddTransaction = true
                        } label: {
                            Text("transaction.add".localized)
                                .appFont(.body, weight: .semibold)
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .padding(.vertical, 32)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    VStack(spacing: 16) {
                        FinancialSummaryCards(
                            income: viewModel.incomeTotal,
                            expense: viewModel.expenseTotal,
                            dailySections: viewModel.dailySections,
                            startDate: viewModel.currentStartDate,
                            endDate: viewModel.currentEndDate,
                            previousPeriodCumulative: viewModel.previousPeriodCumulative,
                            compact: true,
                            tintedBackground: true,
                            onNavigateToPro: {
                                NotificationCenter.default.post(name: .openProAnalytics, object: nil)
                            }
                        )
                        .padding(18)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        GlassPeriodSelector(
                            selectedTab: $viewModel.selectedTab,
                            months: Array(viewModel.availableMonths.suffix(3))
                        )
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(Capsule())

                        if case .custom = viewModel.selectedTab {
                            HStack {
                                Spacer()
                                DatePicker("filter.startDate".localized, selection: $viewModel.customStartDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .appFont(.headline)
                                Text("-")
                                    .foregroundStyle(.secondary)
                                    .appFont(.headline)
                                DatePicker("filter.endDate".localized, selection: $viewModel.customEndDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .appFont(.headline)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if isResultEmpty {
                    Section {
                        if !viewModel.searchText.isEmpty {
                            ContentUnavailableView.search(text: viewModel.searchText)
                                .padding(.vertical, 16)
                        } else {
                            AppEmptyStateView(
                                "home.emptyPeriod.title".localized,
                                systemImage: "calendar.badge.exclamationmark",
                                description: "home.noTransactions".localized
                            )
                        }
                    }
                    .listRowSeparator(.hidden)
                } else if viewModel.sortOption == .highestAmount || viewModel.sortOption == .lowestAmount {
                    // Sorted flat list
                    ForEach(viewModel.sortedTransactions) { txn in
                        HomeTransactionRow(
                            transaction: txn,
                            onEdit: { transactionToEdit = txn },
                            onDelete: { viewModel.deleteTransaction(txn) }
                        )
                    }
                } else {
                    // Daily Transactions
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
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(4) // Reduce section spacing and top padding
        .environment(\.defaultMinListHeaderHeight, 0)
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
                    .appFont(.body)
            }
            Button(role: .destructive, action: onDelete) {
                Label(L10n.Common.delete, systemImage: "trash")
                    .appFont(.body)
            }
        }
    }
}
struct DailyHeader: View {
    let section: DailyTransactionSection
    var onAddTapped: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(section.date.appFormatted(date: .long, time: .omitted))
                .appFont(.headline)
            Spacer()
            Text(section.dailyTotal.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                .appFont(.subheadline)
                .foregroundStyle(section.dailyTotal >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
            if let onAddTapped {
                // Icon-sized tap target, flush with the row's trailing edge
                // (matches the amount alignment below) with a little leading
                // padding for a comfortable target. A wide invisible frame
                // here previously centered the icon away from the edge —
                // inconsistent alignment and a too-large gap from the total.
                Button(action: onAddTapped) {
                    Image(systemName: "plus.circle")
                        .font(.subheadline)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.addTransactionOn".localized(with: section.date.appFormatted(date: .long, time: .omitted)))
            }
        }
        .padding(.vertical, 4)
    }
}


/// Circular glass FAB used for floating primary actions (Home's add button, the
/// Add Transaction sheet's scan button). Deployment target is iOS 26, so the
/// Liquid Glass style needs no availability guard.
struct CircularFABStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .clipShape(.circle)
    }
}

#Preview("HomeView") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Wallet.self, Transaction.self, TransactionLocation.self, Category.self, configurations: configuration)
    let context = container.mainContext

    // Seed minimal preview data if empty
    if try! context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate { $0.deletedAt == nil })).isEmpty {
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

    return HomeView()
        .modelContainer(container)
}

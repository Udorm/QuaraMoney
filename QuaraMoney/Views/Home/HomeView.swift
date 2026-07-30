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
    @State private var backdateTarget: BackdateTarget?
    @State private var isVisible = false
    @State private var isSelectingTransactions = false
    @State private var selectedTransactionIDs = Set<UUID>()
    @State private var showingBulkCategoryPicker = false
    @State private var bulkTagOperation: TransactionBulkTagOperation?
    @State private var bulkEditErrorMessage: String?
    @State private var showingSortOptions = false
    private var router = AppRouter.shared
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var categories: [Category]

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transactionList
                    .refreshable {
                        SyncEngine.shared.configureSyncContext(modelContext)
                        _ = await SyncEngine.shared.requestSyncAndWait(reason: .manualRefresh)
                    }
            }
            .undoToast($viewModel.recentlyDeleted, message: { _ in
                "transaction.deletedToast".localized
            }, onUndo: { token in
                viewModel.undoDelete(token)
            })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectingTransactions {
                    bulkActionBar
                } else {
                    HStack {
                        Spacer()
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
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .navigationTitle("QuaraMoney")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $viewModel.searchText,
                prompt: "common.search".localized
            )
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
            .sheet(isPresented: $showingBulkCategoryPicker) {
                if let type = bulkEditableCategoryType {
                    TransactionCategoryPickerSheet(
                        allCategories: categories.filter { $0.type == type },
                        rankedSuggestions: [],
                        selectedCategoryID: commonSelectedCategoryID,
                        transactionType: type,
                        onSelect: { category in
                            applyBulkCategory(category)
                            showingBulkCategoryPicker = false
                        },
                        onDismiss: { showingBulkCategoryPicker = false }
                    )
                }
            }
            .sheet(item: $bulkTagOperation) { operation in
                TransactionBulkTagSheet(
                    operation: operation,
                    availableTags: selectedAvailableTags,
                    onApply: { tag in applyBulkTag(tag, operation: operation) }
                )
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
            .onChange(of: Set(displayedTransactions.map(\.id))) { _, validIDs in
                selectedTransactionIDs.formIntersection(validIDs)
                if validIDs.isEmpty { endTransactionSelection() }
            }
            .alert(L10n.Common.error, isPresented: Binding(
                get: { bulkEditErrorMessage != nil },
                set: { if !$0 { bulkEditErrorMessage = nil } }
            )) {
                Button(L10n.Common.ok, role: .cancel) { bulkEditErrorMessage = nil }
            } message: {
                Text(bulkEditErrorMessage ?? "")
            }
            .confirmationDialog(
                L10n.Sort.title,
                isPresented: $showingSortOptions,
                titleVisibility: .visible
            ) {
                ForEach(TransactionSortOption.allCases) { option in
                    Button {
                        viewModel.sortOption = option
                        HapticManager.shared.selection()
                    } label: {
                        if viewModel.sortOption == option {
                            Label(option.displayName, systemImage: "checkmark")
                        } else {
                            Text(option.displayName)
                        }
                    }
                }
            }
            .toolbar {
                if isSelectingTransactions {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.Common.done) { endTransactionSelection() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selectionCoversAllDisplayedTransactions
                               ? "common.deselectAll".localized
                               : "common.selectAll".localized) {
                            if selectionCoversAllDisplayedTransactions {
                                selectedTransactionIDs.removeAll()
                            } else {
                                selectedTransactionIDs = Set(displayedTransactions.map(\.id))
                            }
                        }
                    }
                } else {
                    if !displayedTransactions.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isSelectingTransactions = true
                                HapticManager.shared.selection()
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .accessibilityLabel("common.select".localized)
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        homeFilterButton
                        homeSortButton
                    }
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                }
            }
        }
    }

    /// Wallet filtering is a normal browsing action and intentionally disappears
    /// while transaction multi-selection is active.
    private var homeFilterButton: some View {
        FilterSheetButton(
            selectedPeriod: $viewModel.selectedPeriod,
            selectedWalletIds: $viewModel.selectedWalletIds,
            customStartDate: $viewModel.customStartDate,
            customEndDate: $viewModel.customEndDate,
            wallets: wallets,
            defaultPeriod: .thisMonth,
            showPeriodFilter: false
        )
        .accessibilityLabel(L10n.Filter.title)
    }

    /// Explicit toolbar button used beside Filter. A Button is intentional here:
    /// `Menu` can be represented as an ellipsis when grouped in a compact toolbar.
    private var homeSortButton: some View {
        Button {
            showingSortOptions = true
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("a11y.sortTransactions".localized)
    }

    /// Presents the Add Transaction sheet for a staged quick-action intent,
    /// but only while this tab is actually on screen.
    private func consumePendingAddTransaction() {
        guard isVisible, router.pendingAddTransaction else { return }
        router.pendingAddTransaction = false
        showingAddTransaction = true
    }

    /// Transactions currently visible in Home's custom flat/day-grouped list.
    /// Selection is intentionally scoped to the active period, wallet filter,
    /// search, and sort result rather than every transaction in the database.
    private var displayedTransactions: [Transaction] {
        if viewModel.sortOption == .highestAmount || viewModel.sortOption == .lowestAmount {
            return viewModel.sortedTransactions
        }
        return viewModel.dailySections.flatMap(\.transactions)
    }

    private var selectedTransactions: [Transaction] {
        displayedTransactions.filter { selectedTransactionIDs.contains($0.id) }
    }

    /// Home owns this inset instead of using a navigation `.bottomBar` toolbar.
    /// The root `TabView` consumes the device's bottom safe area, so an inset on
    /// Home's content naturally stacks above the persistent tab bar.
    private var bulkActionBar: some View {
        HStack(spacing: 12) {
            Text("transaction.bulk.selectedCount".localized(with: selectedTransactionIDs.count))
                .appFont(.footnote, weight: .semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Button {
                guard bulkEditableCategoryType != nil else {
                    bulkEditErrorMessage = "transaction.bulk.error.incompatibleCategory".localized
                    return
                }
                showingBulkCategoryPicker = true
            } label: {
                Label("transaction.bulk.changeCategory".localized, systemImage: "folder")
                    .appFont(.footnote, weight: .semibold)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .disabled(selectedTransactionIDs.isEmpty)

            Menu {
                Button {
                    bulkTagOperation = .add
                } label: {
                    Label("transaction.bulk.addTag".localized, systemImage: "tag")
                }
                Button {
                    bulkTagOperation = .remove
                } label: {
                    Label("transaction.bulk.removeTag".localized, systemImage: "tag.slash")
                }
                .disabled(selectedAvailableTags.isEmpty)
            } label: {
                Label("transaction.bulk.tags".localized, systemImage: "tag")
                    .appFont(.footnote, weight: .semibold)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .disabled(selectedTransactionIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var selectionCoversAllDisplayedTransactions: Bool {
        !displayedTransactions.isEmpty
            && selectedTransactionIDs == Set(displayedTransactions.map(\.id))
    }

    private var bulkEditableCategoryType: TransactionType? {
        guard let first = selectedTransactions.first,
              first.type == .income || first.type == .expense,
              first.debt == nil,
              selectedTransactions.allSatisfy({ $0.type == first.type && $0.debt == nil }) else {
            return nil
        }
        return first.type
    }

    private var commonSelectedCategoryID: UUID? {
        let ids = Set(selectedTransactions.compactMap { $0.category?.id })
        return ids.count == 1 && selectedTransactions.allSatisfy({ $0.category != nil }) ? ids.first : nil
    }

    private var selectedAvailableTags: [String] {
        var spellings: [String: String] = [:]
        for transaction in selectedTransactions {
            let tags = transaction.tags.isEmpty
                ? TransactionTagParser.tags(in: transaction.note)
                : transaction.tags
            for tag in tags where spellings[tag.lowercased()] == nil {
                spellings[tag.lowercased()] = tag
            }
        }
        return spellings.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func toggleTransactionSelection(_ transaction: Transaction) {
        if selectedTransactionIDs.contains(transaction.id) {
            selectedTransactionIDs.remove(transaction.id)
        } else {
            selectedTransactionIDs.insert(transaction.id)
        }
        HapticManager.shared.selection()
    }

    private func beginTransactionSelection(with transaction: Transaction) {
        isSelectingTransactions = true
        selectedTransactionIDs = [transaction.id]
        HapticManager.shared.selection()
    }

    private func endTransactionSelection() {
        isSelectingTransactions = false
        selectedTransactionIDs.removeAll()
    }

    private func applyBulkCategory(_ category: Category) {
        do {
            try TransactionBulkEditingService.changeCategory(
                of: selectedTransactions,
                to: category,
                in: modelContext
            )
            HapticManager.shared.notification(type: .success)
            endTransactionSelection()
        } catch {
            HapticManager.shared.notification(type: .error)
            bulkEditErrorMessage = bulkEditMessage(for: error)
        }
    }

    private func applyBulkTag(_ tag: String, operation: TransactionBulkTagOperation) {
        do {
            switch operation {
            case .add:
                try TransactionBulkEditingService.addTag(tag, to: selectedTransactions, in: modelContext)
            case .remove:
                try TransactionBulkEditingService.removeTag(tag, from: selectedTransactions, in: modelContext)
            }
            HapticManager.shared.notification(type: .success)
            endTransactionSelection()
        } catch {
            HapticManager.shared.notification(type: .error)
            bulkEditErrorMessage = bulkEditMessage(for: error)
        }
    }

    private func bulkEditMessage(for error: Error) -> String {
        (error as? TransactionBulkEditingService.BulkEditError)?.localizedMessage
            ?? error.localizedDescription
    }

    /// The hero card's surface.
    ///
    /// This was a solid `Color.accentColor` fill, which made the card the
    /// loudest thing on a screen whose actual content is the list below it, and
    /// forced every figure on top to white — costing the card its semantic
    /// income/expense color. It is now a standard grouped-background card with
    /// the accent surviving only as a soft wash off the top-trailing corner
    /// (and as the sparkline stroke inside).
    private var heroCardBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0)],
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 280
                        )
                    )
            }
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
                            onNavigateToPro: {
                                NotificationCenter.default.post(name: .openProAnalytics, object: nil)
                            }
                        )
                        .redacted(reason: viewModel.hasLoadedOnce ? [] : .placeholder)
                        .padding(18)
                        .background(heroCardBackground)

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
                            isSelecting: isSelectingTransactions,
                            isSelected: selectedTransactionIDs.contains(txn.id),
                            onSelectionToggle: { toggleTransactionSelection(txn) },
                            onBeginSelection: { beginTransactionSelection(with: txn) },
                            onEdit: { transactionToEdit = txn },
                            onDelete: { viewModel.deleteTransaction(txn) }
                        )
                    }
                } else {
                    // Daily Transactions
                    ForEach(viewModel.dailySections) { section in
                        Section(header: DailyHeader(
                            section: section,
                            onAddTapped: isSelectingTransactions ? nil : {
                                let noon = Calendar.current.date(
                                    bySettingHour: 12,
                                    minute: 0,
                                    second: 0,
                                    of: section.date
                                ) ?? section.date
                                backdateTarget = BackdateTarget(date: noon)
                            }
                        )) {
                            ForEach(section.transactions) { txn in
                                HomeTransactionRow(
                                    transaction: txn,
                                    isSelecting: isSelectingTransactions,
                                    isSelected: selectedTransactionIDs.contains(txn.id),
                                    onSelectionToggle: { toggleTransactionSelection(txn) },
                                    onBeginSelection: { beginTransactionSelection(with: txn) },
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
    let isSelecting: Bool
    let isSelected: Bool
    let onSelectionToggle: () -> Void
    let onBeginSelection: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: isSelecting ? onSelectionToggle : onEdit) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .appFont(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                }
                TransactionRowView(transaction: transaction)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelecting {
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.Common.delete, systemImage: "trash")
                }

                Button(action: onEdit) {
                    Label(L10n.Common.edit, systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if isSelecting {
                Button(action: onSelectionToggle) {
                    Label(
                        isSelected ? "transaction.bulk.deselect".localized : "common.select".localized,
                        systemImage: isSelected ? "circle" : "checkmark.circle"
                    )
                }
            } else {
                Button(action: onBeginSelection) {
                    Label("common.select".localized, systemImage: "checkmark.circle")
                }
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
                Button(action: onAddTapped) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 26)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        // The visible capsule's trailing edge stays aligned to
                        // the list header's standard right margin.
                        .frame(width: 44, height: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                // Preserve a full native touch target while reporting only the
                // icon's compact height to the section header layout.
                .padding(.vertical, -14)
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

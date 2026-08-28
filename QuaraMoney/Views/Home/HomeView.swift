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
    /// Drives SwiftUI's native multi-selection. Owning the `EditMode` here (and
    /// injecting it into the list's environment) is what buys the system
    /// behaviours a hand-rolled checkmark column can't: two-finger drag-select,
    /// the standard row inset animation, and free `List(selection:)` plumbing.
    @State private var editMode: EditMode = .inactive
    @State private var selectedTransactionIDs = Set<UUID>()
    @State private var showingBulkCategoryPicker = false
    @State private var bulkTagOperation: TransactionBulkTagOperation?
    @State private var showingBulkLocationPicker = false
    @State private var bulkLocationSelection: TransactionLocationSelection?
    @State private var showingBulkDeleteConfirmation = false
    @State private var bulkEditErrorMessage: String?
    @State private var bulkMutation: TransactionBulkMutation?
    @State private var transactionToSplit: Transaction?
    @State private var incomingSharedPayload: SharedExpensePayload?
    private var router = AppRouter.shared

    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var categories: [Category]

    init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationStack {
            searchableContent
            .undoToast($viewModel.recentlyDeleted, message: { _ in
                "transaction.deletedToast".localized
            }, onUndo: { token in
                viewModel.undoDelete(token)
            })
            .undoToast($bulkMutation, message: bulkUndoMessage, onUndo: revertBulkMutation)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isSelectingTransactions {
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
            // Photos' model: select mode *replaces* the tab bar with the action
            // bar rather than stacking one above the other. Hiding it is also
            // what makes a real `.bottomBar` toolbar viable — an earlier attempt
            // rendered its items as ghosts *underneath* the floating tab bar,
            // which is why the bar had to be a hand-built inset until now.
            .toolbarVisibility(isSelectingTransactions ? .hidden : .automatic, for: .tabBar)
            // Mail/Photos retitle the bar to the live selection count and drop to
            // the inline metric while editing; the subtitle carries the running
            // total, which is the number that actually matters here.
            .navigationTitle(isSelectingTransactions ? selectionTitle : "QuaraMoney")
            .navigationSubtitle(isSelectingTransactions ? selectionTotalDescription : "")
            .navigationBarTitleDisplayMode(isSelectingTransactions ? .inline : .large)
            // Visibility gating: the VM refreshes on .dataDidUpdate only while
            // this tab is on screen; changes that arrive while hidden are
            // applied on the next appearance. The first onAppear also performs
            // the initial load (the fetch itself runs off-main, so it doesn't
            // block the first frame).
            .onAppear {
                isVisible = true
                viewModel.setVisible(true)
                consumePendingAddTransaction()
                consumePendingSharedExpense()
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
            .sheet(item: $transactionToSplit) { txn in
                SplitExpenseSheetView(transaction: txn)
            }
            .sheet(item: $incomingSharedPayload) { payload in
                ImportSharedExpenseView(payload: payload)
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
            .sheet(isPresented: $showingBulkLocationPicker) {
                TransactionLocationPickerView(selection: $bulkLocationSelection)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            // The picker writes its binding only on Done, so a non-nil value here
            // is an explicit confirmation — Cancel leaves the reset nil in place.
            .onChange(of: bulkLocationSelection) { _, selection in
                guard let selection else { return }
                applyBulkLocation(selection)
                bulkLocationSelection = nil
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
            .onChange(of: router.pendingSharedExpense) { _, _ in
                consumePendingSharedExpense()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSharedExpense)) { _ in
                consumePendingSharedExpense()
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
            .toolbar {
                // The leading slot is one control that swaps role — Select while
                // browsing, Done while selecting — instead of a Done appearing
                // opposite it. Filtering stays reachable in both modes, so the
                // trailing group survives the switch and only drops Sort, which
                // is meaningless against a selection.
                if isSelectingTransactions {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L10n.Common.done) { endTransactionSelection() }
                            .fontWeight(.semibold)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(selectionCoversAllDisplayedTransactions
                               ? "common.deselectAll".localized
                               : "common.selectAll".localized) {
                            if selectionCoversAllDisplayedTransactions {
                                selectedTransactionIDs.removeAll()
                            } else {
                                selectedTransactionIDs = Set(displayedTransactions.map(\.id))
                            }
                            HapticManager.shared.selection()
                        }
                        homeFilterButton
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        bulkCategoryButton
                        Spacer()
                        bulkTagsMenu
                        Spacer()
                        bulkWalletMenu
                        Spacer()
                        bulkMoreMenu
                        Spacer()
                        bulkDeleteButton
                    }
                } else {
                    if !displayedTransactions.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                beginTransactionSelection()
                            } label: {
                                Image(systemName: "checkmark")
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

    /// Search is a browsing affordance, so it leaves the bar while editing —
    /// the same thing Mail and Files do. `.searchable` has no "disabled" form,
    /// so the modifier has to be applied conditionally; the branch is kept as
    /// tight as possible around the list, and `searchText` lives on the view
    /// model rather than in `@State`, so nothing is lost across the swap.
    @ViewBuilder
    private var searchableContent: some View {
        if isSelectingTransactions {
            refreshableList
        } else {
            refreshableList
                .searchable(
                    text: $viewModel.searchText,
                    prompt: "common.search".localized
                )
                .searchToolbarBehavior(.minimize)
        }
    }

    private var refreshableList: some View {
        VStack(spacing: 0) {
            transactionList
                .refreshable {
                    SyncEngine.shared.configureSyncContext(modelContext)
                    _ = await SyncEngine.shared.requestSyncAndWait(reason: .manualRefresh)
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

    /// Photos' sort affordance: a `Menu`, so iOS 26 morphs the toolbar button
    /// itself into the Liquid Glass options panel anchored right under it —
    /// where the old `confirmationDialog` threw a full-width sheet up from the
    /// bottom of the screen instead. An inline `Picker` supplies the checkmark
    /// and single-selection semantics for free.
    ///
    /// (The earlier note here warned a grouped `Menu` can collapse to an
    /// ellipsis; with only Filter beside it this bar renders the real glyph.)
    private var homeSortButton: some View {
        Menu {
            Picker(selection: $viewModel.sortOption, label: Text(L10n.Sort.title)) {
                ForEach(TransactionSortOption.allCases) { option in
                    Label(option.displayName, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .onChange(of: viewModel.sortOption) { _, _ in
            HapticManager.shared.selection()
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

    /// Consumes a staged incoming shared expense payload and presents the dedicated preview screen.
    private func consumePendingSharedExpense() {
        guard isVisible, let payload = router.pendingSharedExpense else { return }
        router.pendingSharedExpense = nil
        incomingSharedPayload = payload
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

    // MARK: - Bulk action bar
    //
    // Icon-only items in a real `.bottomBar` toolbar, the way Photos presents
    // batch actions: the frequent edits sit on the surface, the rest collapse
    // into a single overflow menu, and the destructive action is isolated at the
    // trailing edge. Sizing, spacing and the glass background all come from the
    // system now that the tab bar yields the space. Every item carries an
    // accessibility label because the glyph is the only visible affordance.

    private var bulkCategoryButton: some View {
        Button {
            guard bulkEditableCategoryType != nil else {
                HapticManager.shared.notification(type: .error)
                bulkEditErrorMessage = "transaction.bulk.error.incompatibleCategory".localized
                return
            }
            showingBulkCategoryPicker = true
        } label: {
            // `tag` is already the app's category glyph — More → Categories,
            // the Pro Analytics category chips and the largest-transaction rows
            // all fall back to it.
            Image(systemName: "tag")
        }
        .disabled(selectedTransactionIDs.isEmpty)
        .accessibilityLabel("transaction.bulk.changeCategory".localized)
    }

    /// `number` (the `#` glyph) for the hashtag feature, since `tag` belongs to
    /// categories above and the tag chips elsewhere render as literal `#name`.
    private var bulkTagsMenu: some View {
        Menu {
            Button {
                bulkTagOperation = .add
            } label: {
                Label("transaction.bulk.addTag".localized, systemImage: "plus")
            }
            Button {
                bulkTagOperation = .remove
            } label: {
                Label("transaction.bulk.removeTag".localized, systemImage: "minus")
            }
            .disabled(selectedAvailableTags.isEmpty)
        } label: {
            Image(systemName: "number")
        }
        .disabled(selectedTransactionIDs.isEmpty)
        .accessibilityLabel("transaction.bulk.tags".localized)
    }

    /// Wallets are listed inline rather than behind a sheet — the list is short
    /// and a menu keeps the whole move to two taps. Ineligible selections
    /// disable the control instead of failing after the fact.
    private var bulkWalletMenu: some View {
        Menu {
            ForEach(wallets) { wallet in
                Button {
                    applyBulkWallet(wallet)
                } label: {
                    Label {
                        Text(verbatim: wallet.name)
                    } icon: {
                        Image(systemName: wallet.icon)
                    }
                }
            }
        } label: {
            Image(systemName: "wallet.bifold")
        }
        .disabled(bulkWalletMoveCount == 0)
        .accessibilityLabel("transaction.bulk.moveToWallet".localized)
    }

    private var bulkMoreMenu: some View {
        Menu {
            Section {
                Button {
                    bulkLocationSelection = nil
                    showingBulkLocationPicker = true
                } label: {
                    Label("transaction.bulk.setLocation".localized, systemImage: "mappin.and.ellipse")
                }
                Button(role: .destructive) {
                    applyBulkLocation(nil)
                } label: {
                    Label("transaction.bulk.clearLocation".localized, systemImage: "mappin.slash")
                }
                .disabled(!selectionHasAnyLocation)
            }

            Section {
                if selectionIsAllExcluded {
                    Button {
                        applyBulkExclusion(false)
                    } label: {
                        Label("transaction.bulk.includeInReports".localized, systemImage: "eye")
                    }
                } else {
                    Button {
                        applyBulkExclusion(true)
                    } label: {
                        Label("transaction.bulk.excludeFromReports".localized, systemImage: "eye.slash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(selectedTransactionIDs.isEmpty)
        .accessibilityLabel("common.more".localized)
    }

    private var bulkDeleteButton: some View {
        Button(role: .destructive) {
            showingBulkDeleteConfirmation = true
        } label: {
            Image(systemName: "trash")
        }
        .tint(.red)
        .disabled(bulkDeletableTransactions.isEmpty)
        .accessibilityLabel(L10n.Common.delete)
        // Attached to the button, not the navigation root: SwiftUI anchors the
        // confirmation popover to the view carrying the modifier, so it grows
        // out of the trash glyph the way iOS 26's own destructive bar actions
        // do. Hosting it at the root left it stranded at the top of the screen.
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: $showingBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.Common.delete, role: .destructive) { applyBulkDelete() }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            if bulkDeletableTransactions.count < selectedTransactions.count {
                Text("transaction.bulk.deleteSkipsAnchors".localized)
            }
        }
    }

    // MARK: - Selection state

    private var isSelectingTransactions: Bool { editMode.isEditing }

    private var selectionTitle: String {
        selectedTransactionIDs.isEmpty
            ? "transaction.bulk.selectPrompt".localized
            : "transaction.bulk.selectedCount".localized(with: selectedTransactionIDs.count)
    }

    /// Net value of the selection in the user's preferred currency. Income adds,
    /// expense subtracts; transfers and adjustments net to zero across wallets
    /// and are left out rather than double-counted.
    private var selectionTotalDescription: String {
        guard !selectedTransactions.isEmpty else { return "" }
        let preferred = CurrencyManager.shared.preferredCurrencyCode
        let total = selectedTransactions.reduce(Decimal.zero) { running, transaction in
            guard transaction.type == .income || transaction.type == .expense else { return running }
            let converted = CurrencyManager.shared.convert(
                amount: transaction.amount,
                from: transaction.currencyCode,
                to: preferred
            )
            return running + (transaction.type == .income ? converted : -converted)
        }
        return total.formattedAmount(for: preferred)
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

    private var bulkWalletMoveCount: Int {
        selectedTransactions.filter(TransactionBulkEditingService.isWalletMoveEligible).count
    }

    private var bulkDeletableTransactions: [Transaction] {
        selectedTransactions.filter { !$0.isDebtAnchor }
    }

    private var selectionHasAnyLocation: Bool {
        selectedTransactions.contains { $0.location != nil }
    }

    private var selectionIsAllExcluded: Bool {
        TransactionBulkEditingService.allExcludedFromReports(selectedTransactions)
    }

    private var deleteConfirmationTitle: String {
        "transaction.bulk.deleteConfirm".localized(with: bulkDeletableTransactions.count)
    }

    private func beginTransactionSelection() {
        withAnimation { editMode = .active }
        HapticManager.shared.selection()
    }

    private func beginTransactionSelection(with transaction: Transaction) {
        withAnimation { editMode = .active }
        selectedTransactionIDs = [transaction.id]
        HapticManager.shared.selection()
    }

    private func endTransactionSelection() {
        withAnimation { editMode = .inactive }
        selectedTransactionIDs.removeAll()
    }

    // MARK: - Bulk mutations

    private func applyBulkCategory(_ category: Category) {
        performBulkEdit {
            try TransactionBulkEditingService.changeCategory(
                of: selectedTransactions,
                to: category,
                in: modelContext
            )
        }
    }

    private func applyBulkTag(_ tag: String, operation: TransactionBulkTagOperation) {
        performBulkEdit {
            switch operation {
            case .add:
                try TransactionBulkEditingService.addTag(tag, to: selectedTransactions, in: modelContext)
            case .remove:
                try TransactionBulkEditingService.removeTag(tag, from: selectedTransactions, in: modelContext)
            }
        }
    }

    private func applyBulkWallet(_ wallet: Wallet) {
        performBulkEdit {
            try TransactionBulkEditingService.move(selectedTransactions, toWallet: wallet, in: modelContext)
        }
    }

    private func applyBulkLocation(_ selection: TransactionLocationSelection?) {
        performBulkEdit {
            try TransactionBulkEditingService.setLocation(selection, for: selectedTransactions, in: modelContext)
        }
    }

    private func applyBulkExclusion(_ excluded: Bool) {
        performBulkEdit {
            try TransactionBulkEditingService.setExcludedFromReports(
                excluded,
                for: selectedTransactions,
                in: modelContext
            )
        }
    }

    private func applyBulkDelete() {
        performBulkEdit {
            try TransactionBulkEditingService.delete(selectedTransactions, in: modelContext)
        }
    }

    /// Runs one mutation, then surfaces it as an Undo toast and leaves selection
    /// mode. The single-delete toast is cleared first so the two snackbars can
    /// never stack on top of each other.
    private func performBulkEdit(_ mutate: () throws -> TransactionBulkMutation) {
        do {
            let mutation = try mutate()
            viewModel.recentlyDeleted = nil
            bulkMutation = mutation
            HapticManager.shared.notification(type: .success)
            endTransactionSelection()
        } catch {
            HapticManager.shared.notification(type: .error)
            bulkEditErrorMessage = bulkEditMessage(for: error)
        }
    }

    private func revertBulkMutation(_ mutation: TransactionBulkMutation) {
        do {
            try mutation.revert(in: modelContext)
            HapticManager.shared.selection()
        } catch {
            HapticManager.shared.notification(type: .error)
            bulkEditErrorMessage = bulkEditMessage(for: error)
        }
    }

    /// Partial application is reported in the toast rather than an alert: the
    /// edit did succeed for most rows, so an error dialog would overstate it.
    private func bulkUndoMessage(_ mutation: TransactionBulkMutation) -> String {
        guard mutation.skippedCount > 0 else { return mutation.summary }
        return mutation.summary + " · " + "transaction.bulk.skipped".localized(with: mutation.skippedCount)
    }

    private func bulkEditMessage(for error: Error) -> String {
        (error as? TransactionBulkEditingService.BulkEditError)?.localizedMessage
            ?? error.localizedDescription
    }

    /// The summary hero. Content-layer only — no custom surface, matching the
    /// wallet screen's `NetWorthCard`: it's a plain row in a plain section, so
    /// the inset-grouped `List` draws the card itself. That's what keeps it
    /// identical to a native grouped card, radius included, at every size class
    /// and accessibility setting.
    ///
    /// Successive hand-rolled surfaces here — a solid `Color.accentColor` fill,
    /// then a grouped fill with a top-trailing accent wash, then `PlanCard`'s
    /// tinted glass — were all attempts to approximate this.
    private var heroCard: some View {
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
        .padding(.vertical, 6)
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
        List(selection: $selectedTransactionIDs) {
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
                .selectionDisabled()
            } else {
                // Its own section, with the row background left alone so the
                // *system* draws the card — the same treatment as the wallet
                // screen's net-worth hero.
                Section {
                    heroCard
                }
                .listRowSeparator(.hidden)
                // The hero card, period selector and empty states are chrome —
                // `List(selection:)` would otherwise offer selection circles
                // beside them the moment edit mode turns on.
                .selectionDisabled()

                Section {
                    VStack(spacing: 16) {
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
                    // Top inset + the list's 4pt section spacing reproduces the
                    // 16pt gap this had when it shared a row with the hero.
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .selectionDisabled()

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
                    .selectionDisabled()
                } else if viewModel.sortOption == .highestAmount || viewModel.sortOption == .lowestAmount {
                    // Sorted flat list
                    ForEach(viewModel.sortedTransactions) { txn in
                        HomeTransactionRow(
                            transaction: txn,
                            onBeginSelection: { beginTransactionSelection(with: txn) },
                            onEdit: { transactionToEdit = txn },
                            onSplit: { transactionToSplit = txn },
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
                                    onBeginSelection: { beginTransactionSelection(with: txn) },
                                    onEdit: { transactionToEdit = txn },
                                    onSplit: { transactionToSplit = txn },
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
        .environment(\.editMode, $editMode)
    }
}

// Subview for Transaction Row to reduce complexity
struct HomeTransactionRow: View {
    let transaction: Transaction
    let onBeginSelection: () -> Void
    let onEdit: () -> Void
    let onSplit: () -> Void
    let onDelete: () -> Void

    @Environment(\.editMode) private var editMode

    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

    var body: some View {
        rowContent
            // Swipe actions and the context menu both compete with edit mode's
            // drag-to-select, which is why the system suppresses them there too.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if !isEditing {
                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.Common.delete, systemImage: "trash")
                    }

                    Button(action: onEdit) {
                        Label(L10n.Common.edit, systemImage: "pencil")
                    }
                    .tint(.blue)

                    if transaction.type == .expense {
                        Button(action: onSplit) {
                            Label("transaction.splitBill".localized, systemImage: "person.2.slash")
                        }
                        .tint(.purple)
                    }
                }
            }
            .contextMenu {
                if !isEditing {
                    Button(action: onBeginSelection) {
                        Label("common.select".localized, systemImage: "checkmark.circle")
                    }
                    Button(action: onEdit) {
                        Label(L10n.Common.edit, systemImage: "pencil")
                            .appFont(.body)
                    }
                    if transaction.type == .expense {
                        Button(action: onSplit) {
                            Label("transaction.splitBill".localized, systemImage: "person.2.slash")
                                .appFont(.body)
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.Common.delete, systemImage: "trash")
                            .appFont(.body)
                    }
                }
            }
    }

    /// A `Button` would swallow the tap that `List(selection:)` needs to toggle
    /// the row, so edit mode renders the bare content and lets the list own the
    /// gesture — including the two-finger drag across many rows.
    @ViewBuilder
    private var rowContent: some View {
        if isEditing {
            TransactionRowView(transaction: transaction)
                .contentShape(Rectangle())
        } else {
            Button(action: onEdit) {
                TransactionRowView(transaction: transaction)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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

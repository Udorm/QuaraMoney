import SwiftUI
import SwiftData

/// Quick actions reachable from a wallet row without opening the detail screen.
private enum WalletQuickAction: Identifiable {
    case addExpense(Wallet)
    case addIncome(Wallet)
    case transfer(Wallet)
    case adjustBalance(Wallet)

    var wallet: Wallet {
        switch self {
        case .addExpense(let w), .addIncome(let w), .transfer(let w), .adjustBalance(let w):
            return w
        }
    }

    var id: String {
        switch self {
        case .addExpense(let w): return "expense-\(w.id)"
        case .addIncome(let w): return "income-\(w.id)"
        case .transfer(let w): return "transfer-\(w.id)"
        case .adjustBalance(let w): return "adjust-\(w.id)"
        }
    }
}

struct WalletListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddWallet = false
    @State private var walletToEdit: Wallet?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            WalletListContent(walletToEdit: $walletToEdit, searchText: searchText)
                .navigationTitle(L10n.Wallet.title)
                .searchable(text: $searchText)
                .searchToolbarBehavior(.minimize)
                .sheet(isPresented: $showingAddWallet) {
                    AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
                }
                .sheet(item: $walletToEdit) { wallet in
                    AddWalletView(viewModel: AddWalletViewModel(
                        dataService: SwiftDataService(modelContext: modelContext),
                        walletToEdit: wallet
                    ))
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingAddWallet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(L10n.Wallet.add)
                    }
                }
        }
    }
}

private struct WalletListContent: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @Binding var walletToEdit: Wallet?
    let searchText: String

    @State private var isArchivedExpanded = false
    @State private var quickAction: WalletQuickAction?
    @State private var walletToDelete: Wallet?
    @State private var showingDeleteAlert = false
    @State private var walletToReassign: Wallet?
    @State private var refreshToken = 0

    init(walletToEdit: Binding<Wallet?>, searchText: String) {
        self._walletToEdit = walletToEdit
        self.searchText = searchText

        let filter = #Predicate<Wallet> { wallet in
            wallet.deletedAt == nil &&
            (searchText.isEmpty || wallet.name.localizedStandardContains(searchText))
        }
        _wallets = Query(filter: filter, sort: \Wallet.name)
    }

    private var activeWallets: [Wallet] { wallets.filter { !$0.isArchived } }
    private var archivedWallets: [Wallet] { wallets.filter { $0.isArchived } }

    var body: some View {
        List {
            if searchText.isEmpty {
                Section {
                    NetWorthCard(wallets: activeWallets, refreshToken: refreshToken)
                }
            }

            if !activeWallets.isEmpty {
                Section(header: Text(L10n.Wallet.Status.activeWallets)) {
                    ForEach(activeWallets) { wallet in
                        walletRow(wallet, isArchived: false)
                    }
                }
            }

            if !archivedWallets.isEmpty {
                archivedSection
            }
        }
        .overlay {
            if wallets.isEmpty {
                AppEmptyStateView(
                    searchText.isEmpty ? "wallet.noWallets".localized : "common.noResults".localized,
                    systemImage: searchText.isEmpty ? "wallet.pass" : "magnifyingglass",
                    description: searchText.isEmpty ? L10n.Wallet.emptyState : nil
                )
            }
        }
        .syncPullToRefresh(modelContext)
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            // Balances are @Transient-cached and not observed by @Query; invalidate
            // them and bump the token so rows recompute after any data change.
            for wallet in wallets { wallet.invalidateBalanceCache() }
            refreshToken &+= 1
        }
        .sheet(item: $quickAction) { action in
            quickActionSheet(action)
        }
        .alert(L10n.Common.delete, isPresented: $showingDeleteAlert, presenting: walletToDelete) { wallet in
            Button(L10n.Common.cancel, role: .cancel) {}
            if !wallet.isArchived {
                Button(L10n.Wallet.archiveInstead) {
                    archiveWallet(wallet)
                }
            }
            // Offer to move transactions when the wallet has any and another
            // active wallet exists to receive them.
            if (wallet.outgoingTransactions?.contains(where: { $0.deletedAt == nil }) ?? false),
               activeWallets.contains(where: { $0.id != wallet.id }) {
                Button("wallet.moveTransactions".localized) {
                    walletToReassign = wallet
                }
            }
            Button(L10n.Wallet.deleteAnyway, role: .destructive) {
                deleteWallet(wallet, strategy: .deleteTransactions)
            }
        } message: { wallet in
            Text(L10n.Wallet.deleteRelatedTransactionsWarning((wallet.outgoingTransactions ?? []).filter { $0.deletedAt == nil }.count))
        }
        .sheet(item: $walletToReassign) { wallet in
            MoveTransactionsSheet(
                sourceWallet: wallet,
                candidates: activeWallets.filter { $0.id != wallet.id }
            ) { target in
                deleteWallet(wallet, strategy: .move(to: target))
                walletToReassign = nil
            }
        }
    }

    // MARK: - Sections

    private var archivedSection: some View {
        Section {
            if isArchivedExpanded {
                ForEach(archivedWallets) { wallet in
                    walletRow(wallet, isArchived: true)
                }
            }
        } header: {
            Button {
                withAnimation(.snappy) { isArchivedExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.Wallet.Status.archivedWallets)
                    Text("\(archivedWallets.count)")
                        .font(.app(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.app(.caption2, weight: .semibold))
                        .rotationEffect(.degrees(isArchivedExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Wallet.Status.archivedWallets)
            .accessibilityValue(isArchivedExpanded ? "common.expanded".localized : "common.collapsed".localized)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func walletRow(_ wallet: Wallet, isArchived: Bool) -> some View {
        NavigationLink(destination: WalletDetailView(wallet: wallet, modelContext: modelContext)) {
            WalletRowView(wallet: wallet, refreshToken: refreshToken)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isArchived {
                Button {
                    unarchiveWallet(wallet)
                } label: {
                    Label(L10n.Wallet.unarchive, systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)

                Button(role: .destructive) {
                    walletToDelete = wallet
                    showingDeleteAlert = true
                } label: {
                    Label(L10n.Common.delete, systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    archiveWallet(wallet)
                } label: {
                    Label(L10n.Wallet.archive, systemImage: "archivebox")
                }

                Button {
                    walletToEdit = wallet
                } label: {
                    Label(L10n.Common.edit, systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isArchived {
                Button {
                    quickAction = .addExpense(wallet)
                } label: {
                    Label(L10n.Transaction.add, systemImage: "plus")
                }
                .tint(Color(hex: wallet.colorHex) ?? .blue)
            }
        }
        .contextMenu {
            if !isArchived {
                Section {
                    Button {
                        quickAction = .addExpense(wallet)
                    } label: {
                        Label("wallet.action.addExpense".localized, systemImage: "minus.circle")
                    }
                    Button {
                        quickAction = .addIncome(wallet)
                    } label: {
                        Label("wallet.action.addIncome".localized, systemImage: "plus.circle")
                    }
                    Button {
                        quickAction = .transfer(wallet)
                    } label: {
                        Label("transaction.type.transfer".localized, systemImage: "arrow.left.arrow.right")
                    }
                    Button {
                        quickAction = .adjustBalance(wallet)
                    } label: {
                        Label("wallet.adjustBalance".localized, systemImage: "slider.horizontal.3")
                    }
                }
            }

            Section {
                Button {
                    walletToEdit = wallet
                } label: {
                    Label(L10n.Common.edit, systemImage: "pencil")
                }

                if isArchived {
                    Button {
                        unarchiveWallet(wallet)
                    } label: {
                        Label(L10n.Wallet.unarchive, systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        archiveWallet(wallet)
                    } label: {
                        Label(L10n.Wallet.archive, systemImage: "archivebox")
                    }
                }
            }

            Button(role: .destructive) {
                walletToDelete = wallet
                showingDeleteAlert = true
            } label: {
                Label(L10n.Common.delete, systemImage: "trash")
            }
        }
    }

    // MARK: - Quick action sheets

    @ViewBuilder
    private func quickActionSheet(_ action: WalletQuickAction) -> some View {
        switch action {
        case .addExpense(let wallet):
            AddTransactionContainer(initialWallet: wallet, initialType: .expense)
        case .addIncome(let wallet):
            AddTransactionContainer(initialWallet: wallet, initialType: .income)
        case .transfer(let wallet):
            AddTransactionContainer(initialWallet: wallet, initialType: .transfer)
        case .adjustBalance(let wallet):
            AdjustBalanceView(
                wallet: wallet,
                dataService: SwiftDataService(modelContext: modelContext)
            )
        }
    }

    // MARK: - Mutations

    private func archiveWallet(_ wallet: Wallet) {
        wallet.isArchived = true
        do {
            try modelContext.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "WalletListView.archiveWallet")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }

    private func unarchiveWallet(_ wallet: Wallet) {
        wallet.isArchived = false
        do {
            try modelContext.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "WalletListView.unarchiveWallet")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }

    private func deleteWallet(_ wallet: Wallet, strategy: SoftDeleteService.WalletDeletionStrategy) {
        // Soft-delete (tombstone) so the deletion replicates to other devices.
        SoftDeleteService.deleteWallet(wallet, strategy: strategy)
        do {
            try modelContext.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "WalletListView.deleteWallet")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

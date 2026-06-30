import SwiftUI
import SwiftData

struct WalletListView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAddWallet = false
    @State private var walletToEdit: Wallet?
    @State private var showArchived = false
    @State private var showingFilter = false
    @State private var searchText = ""
    @State private var isSearchPresented = false
    
    var body: some View {
        NavigationStack {
            WalletListContent(showArchived: showArchived, walletToEdit: $walletToEdit, searchText: searchText)
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
                .sheet(isPresented: $showingFilter) {
                    WalletFilterSheet(showArchived: $showArchived, isPresented: $showingFilter)
                }
                
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        //add button
                        Button {
                            showingAddWallet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add wallet")
                        
                        //filter button
                        Button {
                            showingFilter = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .symbolVariant(showArchived ? .fill : .none)
                                .font(.app(.title3))
                                .foregroundStyle(showArchived ? .blue : .primary)
                        }
                        .accessibilityLabel(showArchived ? "Filter, showing archived" : "Filter wallets")
                    }
                }
        }
    }
}

private struct WalletListContent: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { $0.deletedAt == nil }) private var wallets: [Wallet]
    @Query(filter: #Predicate<Wallet> { $0.deletedAt == nil }) private var allActiveWallets: [Wallet]
    @Binding var walletToEdit: Wallet?
    let showArchived: Bool
    let searchText: String
    
    @State private var walletToDelete: Wallet?
    @State private var showingDeleteAlert = false
    @State private var walletToReassign: Wallet?
    @State private var refreshToken = 0
    
    init(showArchived: Bool, walletToEdit: Binding<Wallet?>, searchText: String) {
        self.showArchived = showArchived
        self._walletToEdit = walletToEdit
        self.searchText = searchText
        
        let filter = #Predicate<Wallet> { wallet in
            wallet.deletedAt == nil &&
            (showArchived ? wallet.isArchived : !wallet.isArchived) &&
            (searchText.isEmpty || wallet.name.localizedStandardContains(searchText))
        }
        _wallets = Query(filter: filter, sort: \Wallet.name)

        let netWorthFilter = #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }
        _allActiveWallets = Query(filter: netWorthFilter, sort: \Wallet.name)
    }
    
    var body: some View {
        List {
            if !showArchived {
                Section {
                    NetWorthCard(wallets: allActiveWallets, refreshToken: refreshToken)
                }
            }

            Section(header: Text(showArchived ? L10n.Wallet.Status.archivedWallets : L10n.Wallet.Status.activeWallets)) {
                ForEach(wallets) { wallet in
                    NavigationLink(destination: WalletDetailView(wallet: wallet, modelContext: modelContext)) {
                        WalletRowView(wallet: wallet, refreshToken: refreshToken)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !showArchived {
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
                        } else {
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
                        }
                    }
                    .contextMenu {
                        Button {
                            walletToEdit = wallet
                        } label: {
                            Label(L10n.Common.edit, systemImage: "pencil")
                                .font(.app(.body))
                        }
                        
                        if !showArchived {
                            Button {
                                archiveWallet(wallet)
                            } label: {
                                Label(L10n.Wallet.archive, systemImage: "archivebox")
                                    .font(.app(.body))
                            }
                        } else {
                            Button {
                                unarchiveWallet(wallet)
                            } label: {
                                Label(L10n.Wallet.unarchive, systemImage: "arrow.uturn.backward")
                                    .font(.app(.body))
                            }
                        }
                        
                        Button(role: .destructive) {
                            walletToDelete = wallet
                            showingDeleteAlert = true
                        } label: {
                            Label(L10n.Common.delete, systemImage: "trash")
                                .font(.app(.body))
                        }
                    }
                }
            }
        }
        .overlay {
            if wallets.isEmpty {
                AppEmptyStateView(
                    showArchived ? L10n.Wallet.noArchivedWallets : L10n.Common.error, // Assuming reuse or new string
                    systemImage: showArchived ? "archivebox" : "wallet.pass",
                    description: showArchived ? nil : L10n.Wallet.emptyState
                )
            }
        }
        .syncPullToRefresh(modelContext)
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            // Balances are @Transient-cached and not observed by @Query; invalidate
            // them and bump the token so rows recompute after any data change.
            for wallet in wallets { wallet.invalidateBalanceCache() }
            for wallet in allActiveWallets { wallet.invalidateBalanceCache() }
            refreshToken &+= 1
        }
        .alert(L10n.Common.delete, isPresented: $showingDeleteAlert, presenting: walletToDelete) { wallet in
            Button(L10n.Common.cancel, role: .cancel) {}
            if !showArchived {
                Button(L10n.Wallet.archiveInstead) {
                    archiveWallet(wallet)
                }
            }
            // Offer to move transactions when the wallet has any and another
            // active wallet exists to receive them.
            if (wallet.outgoingTransactions?.contains(where: { $0.deletedAt == nil }) ?? false),
               allActiveWallets.contains(where: { $0.id != wallet.id }) {
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
                candidates: allActiveWallets.filter { $0.id != wallet.id }
            ) { target in
                deleteWallet(wallet, strategy: .move(to: target))
                walletToReassign = nil
            }
        }
    }
    
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

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
                .searchable(text: $searchText, isPresented: $isSearchPresented)
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
                        Button {
                            isSearchPresented = true
                        } label: {
                            Label(L10n.Common.search, systemImage: "magnifyingglass")
                        }

                        Button {
                            showingFilter = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                                .symbolVariant(showArchived ? .fill : .none)
                                .font(.app(.title3))
                                .foregroundStyle(showArchived ? .blue : .primary)
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddWallet = true
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

private struct WalletListContent: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @Binding var walletToEdit: Wallet?
    let showArchived: Bool
    let searchText: String
    
    @State private var walletToDelete: Wallet?
    @State private var showingDeleteAlert = false
    
    init(showArchived: Bool, walletToEdit: Binding<Wallet?>, searchText: String) {
        self.showArchived = showArchived
        self._walletToEdit = walletToEdit
        self.searchText = searchText
        
        let filter = #Predicate<Wallet> { wallet in
            (showArchived ? wallet.isArchived : !wallet.isArchived) &&
            (searchText.isEmpty || wallet.name.localizedStandardContains(searchText))
        }
        _wallets = Query(filter: filter, sort: \Wallet.name)
    }
    
    var body: some View {
        List {
            Section(header: Text(showArchived ? L10n.Wallet.Status.archivedWallets : L10n.Wallet.Status.activeWallets)) {
                ForEach(wallets) { wallet in
                    NavigationLink(destination: WalletDetailView(wallet: wallet, modelContext: modelContext)) {
                        WalletRowView(wallet: wallet)
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
        .alert(L10n.Common.delete, isPresented: $showingDeleteAlert, presenting: walletToDelete) { wallet in
            Button(L10n.Common.cancel, role: .cancel) {}
            if !showArchived {
                Button(L10n.Wallet.archiveInstead) {
                    archiveWallet(wallet)
                }
            }
            Button(L10n.Wallet.deleteAnyway, role: .destructive) {
                deleteWallet(wallet)
            }
        } message: { wallet in
            Text(L10n.Wallet.deleteRelatedTransactionsWarning(wallet.outgoingTransactions?.count ?? 0))
        }
    }
    
    private func archiveWallet(_ wallet: Wallet) {
        wallet.isArchived = true
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
    
    private func unarchiveWallet(_ wallet: Wallet) {
        wallet.isArchived = false
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
    
    private func deleteWallet(_ wallet: Wallet) {
        modelContext.delete(wallet)
    }
}

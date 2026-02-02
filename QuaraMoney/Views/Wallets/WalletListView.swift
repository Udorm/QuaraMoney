import SwiftUI
import SwiftData

struct WalletListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    
    @State private var showingAddWallet = false
    @State private var walletToEdit: Wallet?
    
    var body: some View {
        NavigationStack {
            List {
                if !wallets.isEmpty {
                    Section {
                        NetWorthCard(wallets: wallets)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                
                ForEach(wallets) { wallet in
                    NavigationLink(destination: WalletDetailView(wallet: wallet, modelContext: modelContext)) {
                        WalletRowView(wallet: wallet)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteWallet(wallet)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            walletToEdit = wallet
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            walletToEdit = wallet
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteWallet(wallet)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Wallets")
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddWallet = true }) {
                        Label("Add Wallet", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddWallet) {
                AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
            }
            .sheet(item: $walletToEdit) { wallet in
                AddWalletView(viewModel: AddWalletViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    walletToEdit: wallet
                ))
            }
            .overlay {
                if wallets.isEmpty {
                    ContentUnavailableView(
                        "No Wallets",
                        systemImage: "wallet.pass",
                        description: Text("Tap + to create your first wallet.")
                    )
                }
            }
        }
    }
    
    private func deleteWallet(_ wallet: Wallet) {
        let service = SwiftDataService(modelContext: modelContext)
        let vm = WalletListViewModel(dataService: service)
        if let index = wallets.firstIndex(where: { $0.id == wallet.id }) {
            vm.deleteWallet(at: IndexSet(integer: index), from: wallets)
        }
    }
}

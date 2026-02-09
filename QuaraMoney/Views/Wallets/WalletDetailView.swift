import SwiftUI
import SwiftData

struct WalletDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: WalletDetailViewModel
    
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var showingEditWallet = false
    @State private var isSearchPresented = false
    
    init(wallet: Wallet, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: WalletDetailViewModel(modelContext: modelContext, wallet: wallet))
    }
    
    var body: some View {
        List {
            // Header Section (Balance)
            // Header Section (Hero)
            Section {
                VStack(spacing: 20) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: viewModel.wallet.icon)
                            .appFont(size: 36)
                            .foregroundStyle(.white)
                    }
                    
                    // Balance
                    Text(viewModel.wallet.balance.formatted(.currency(code: viewModel.wallet.currencyCode)))
                        .font(.app(.largeTitle, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 20) // Internal content padding
                .overlay(alignment: .topTrailing) {
                    if viewModel.wallet.isArchived {
                        Text(L10n.Wallet.Status.archived)
                            .font(.app(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.3))
                            .clipShape(Capsule())
                            .padding(12)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: viewModel.wallet.colorHex) ?? .blue,
                                    (Color(hex: viewModel.wallet.colorHex) ?? .blue).opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: (Color(hex: viewModel.wallet.colorHex) ?? .blue).opacity(0.3), radius: 8, x: 0, y: 4)
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets()) // Expand to full row width
            .listRowSeparator(.hidden)
            
            // Filter Description Header
            // Transactions List (grouped by date using reusable component)
            if viewModel.transactions.isEmpty {
                Section {
                    AppEmptyStateView(
                        "No Transactions",
                        systemImage: "list.bullet.clipboard",
                        description: "No transactions in this period."
                    )
                }
            } else {
                TransactionListView(
                    transactions: viewModel.transactions,
                    listHeader: viewModel.filterDescription, // Pass filter description as integrated header
                    onEdit: { txn in
                        transactionToEdit = txn
                    },
                    onDelete: { txn in
                        viewModel.deleteTransaction(txn)
                    }
                )
            }
        }
        .navigationTitle(viewModel.wallet.name)
        .searchable(text: $viewModel.searchText)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Add Button (Top Right / Prominent)
                Button {
                    showingAddTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
                
                // Edit Button
                Button {
                    showingEditWallet = true
                } label: {
                    Label(L10n.Common.edit, systemImage: "pencil")
                }
                
                // Filter Button
                FilterSheetButton(
                    selectedPeriod: $viewModel.selectedPeriod,
                    selectedWallet: .constant(nil),
                    customStartDate: $viewModel.customStartDate,
                    customEndDate: $viewModel.customEndDate,
                    wallets: [],
                    defaultPeriod: .thisMonth,
                    showWalletFilter: false
                )
                
                
            }
        }
        .sheet(isPresented: $showingEditWallet) {
            AddWalletView(viewModel: AddWalletViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                walletToEdit: viewModel.wallet
            ))
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    initialWallet: viewModel.wallet
                ),
                isNewTransaction: true
            )
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    initialWallet: viewModel.wallet,
                    transaction: txn
                ),
                isNewTransaction: false
            )
        }
        .onAppear {
            viewModel.fetchTransactions()
        }
        .onChange(of: showingAddTransaction) { oldValue, newValue in
            if !newValue {
                viewModel.fetchTransactions()
                // Wallet balance might have changed, need to refresh context or wallet object?
                // The wallet object passed in generic init might be stale?
                // Often better to fetch wallet by ID or rely on SwiftData observability if Wallet is Observable.
                // Wallet is @Model, so it's Observable. changes should reflect.
            }
        }
        .onChange(of: transactionToEdit) { oldValue, newValue in
            if newValue == nil {
                 viewModel.fetchTransactions()
            }
        }
    }
}


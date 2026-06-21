import SwiftUI
import SwiftData

struct WalletDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WalletDetailViewModel
    
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: Transaction?
    @State private var showingEditWallet = false
    @State private var showingAdjustBalance = false
    @State private var isSearchPresented = false
    
    init(wallet: Wallet, modelContext: ModelContext) {
        _viewModel = State(wrappedValue: WalletDetailViewModel(modelContext: modelContext, wallet: wallet))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List {
            Section {
                MonthSelectionView(
                    selectedTab: $viewModel.selectedTab,
                    months: Array(viewModel.availableMonths.suffix(3))
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                
                if case .custom = viewModel.selectedTab {
                    HStack {
                        Spacer()
                        DatePicker("Start", selection: $viewModel.customStartDate, displayedComponents: .date)
                            .labelsHidden()
                            .appFont(.subheadline)
                        Text("-")
                            .foregroundStyle(.secondary)
                            .appFont(.subheadline)
                        DatePicker("End", selection: $viewModel.customEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .appFont(.subheadline)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            
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
                    Text(viewModel.wallet.balance.formattedAmount(for: viewModel.wallet.currencyCode))
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
                    sortOption: viewModel.sortOption,
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle(viewModel.wallet.name)
        .searchable(text: $viewModel.searchText)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Sort Button
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

                // Add Button (Top Right / Prominent)
                Button {
                    showingAddTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
                
                // More Options Menu
                Menu {
                    Button {
                        showingAdjustBalance = true
                    } label: {
                        Label("Adjust Balance", systemImage: "dollarsign.circle")
                    }
                    
                    Button {
                        showingEditWallet = true
                    } label: {
                        Label(L10n.Common.edit, systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditWallet) {
            AddWalletView(viewModel: AddWalletViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                walletToEdit: viewModel.wallet
            ))
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddTransactionContainer(isNewTransaction: true, initialWallet: viewModel.wallet)
        }
        .sheet(isPresented: $showingAdjustBalance) {
            AdjustBalanceView(
                wallet: viewModel.wallet,
                dataService: SwiftDataService(modelContext: modelContext)
            )
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionContainer(transaction: txn, isNewTransaction: false, initialWallet: viewModel.wallet)
        }
        .debtDeletionBlockedAlert($viewModel.blockedDeletionMessage)
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


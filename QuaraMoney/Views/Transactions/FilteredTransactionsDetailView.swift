import SwiftUI
import SwiftData

struct FilteredTransactionsDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let config: TransactionFilterConfig

    @State private var vm: FilteredTransactionsViewModel
    @State private var transactionToEdit: Transaction?

    init(config: TransactionFilterConfig) {
        self.config = config
        self._vm = State(initialValue: FilteredTransactionsViewModel(config: config))
    }

    private var preferredCurrency: String {
        CurrencyManager.shared.preferredCurrencyCode
    }

    /// All categories to display — from categoryInfos or single category fallback
    private var displayCategories: [FilterCategoryInfo] {
        if let infos = config.categoryInfos, !infos.isEmpty {
            return infos
        }
        if let id = config.categoryId, let name = config.categoryName {
            return [FilterCategoryInfo(
                id: id,
                name: name,
                icon: config.categoryIcon ?? "circle.fill",
                colorHex: config.categoryColorHex ?? "007AFF"
            )]
        }
        return []
    }

    var body: some View {
        List {
            // MARK: - Filter Context & Summary
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    // Categories
                    if !displayCategories.isEmpty {
                        filterRow(icon: "square.grid.2x2", label: nil) {
                            FlowLayout(spacing: 6) {
                                ForEach(displayCategories) { cat in
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.icon.isEmpty ? "circle.fill" : cat.icon)
                                            .font(.system(size: 10))
                                        Text(cat.name)
                                            .font(.app(.caption))
                                    }
                                    .foregroundStyle(Color(hex: cat.colorHex) ?? .blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background((Color(hex: cat.colorHex) ?? .blue).opacity(0.1))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Date range
                    filterRow(icon: "calendar", label: config.formattedDateRange) {
                        EmptyView()
                    }

                    // Wallet
                    if let walletName = config.walletName {
                        filterRow(icon: "wallet.bifold", label: walletName) {
                            EmptyView()
                        }
                    }

                    // Type + Summary
                    HStack {
                        if let type = config.transactionType {
                            HStack(spacing: 4) {
                                Image(systemName: type == .expense ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                    .font(.system(size: 12))
                                Text(type.rawValue)
                                    .font(.app(.caption))
                            }
                            .foregroundStyle(type == .expense ? ThemeManager.shared.expenseColor : ThemeManager.shared.incomeColor)
                        }

                        Spacer()

                        Text("filteredTransactions.count".localized(with: vm.transactions.count))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)

                        Text(vm.totalAmount.formattedAmount(for: preferredCurrency))
                            .font(.app(.subheadline, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Transaction List
            if vm.isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                TransactionListView(
                    transactions: vm.transactions,
                    onEdit: { txn in
                        transactionToEdit = txn
                    },
                    onDelete: { txn in
                        vm.deleteTransaction(txn)
                    }
                )
            }
        }
        .navigationTitle(config.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            vm.configure(modelContext: modelContext)
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionView(
                viewModel: AddTransactionViewModel(
                    dataService: SwiftDataService(modelContext: modelContext),
                    transaction: txn
                ),
                isNewTransaction: false
            )
        }
    }

    private func filterRow<Content: View>(icon: String, label: String?, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, label != nil ? 2 : 4)

            if let label {
                Text(label)
                    .font(.app(.caption))
                    .foregroundStyle(.primary)
            }

            content()
        }
    }
}


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
                filterSummaryCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                    sortOption: vm.sortOption,
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
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $vm.searchText, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $vm.sortOption, label: Text(L10n.Sort.title)) {
                        ForEach(TransactionSortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .onAppear {
            vm.configure(modelContext: modelContext)
            vm.setVisible(true)
        }
        .onDisappear { vm.setVisible(false) }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionContainer(transaction: txn, isNewTransaction: false)
        }
        .debtDeletionBlockedAlert($vm.blockedDeletionMessage)
    }

    // MARK: - Filter Summary Card

    private var accentColor: Color {
        if let cat = displayCategories.first {
            return Color(hex: cat.colorHex) ?? .blue
        }
        if let type = config.transactionType {
            return type == .expense ? ThemeManager.shared.expenseColor : ThemeManager.shared.incomeColor
        }
        return .blue
    }

    @ViewBuilder
    private var filterSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header — icon + context + type badge
            HStack(alignment: .top, spacing: 12) {

                // Category icon — iOS "app icon" rounded square style
                let iconName: String = {
                    if let cat = displayCategories.first, !cat.icon.isEmpty { return cat.icon }
                    return "line.3.horizontal.decrease.circle.fill"
                }()
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: iconName)
                        .appFont(size: 20, weight: .semibold)
                        .foregroundStyle(accentColor)
                }

                // Name + metadata
                VStack(alignment: .leading, spacing: 4) {
                    if displayCategories.count == 1, let cat = displayCategories.first {
                        Text(cat.name)
                            .appFont(.subheadline, weight: .semibold)
                    } else if displayCategories.count > 1 {
                        FlowLayout(spacing: 4) {
                            ForEach(displayCategories) { cat in
                                let c = Color(hex: cat.colorHex) ?? .blue
                                Text(cat.name)
                                    .appFont(.caption2, weight: .medium)
                                    .foregroundStyle(c)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(c.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .appFont(size: 10)
                        Text(config.formattedDateRange)
                            .appFont(.caption)
                        if let walletName = config.walletName {
                            Text("·").foregroundStyle(.tertiary)
                            Image(systemName: "wallet.bifold")
                                .appFont(size: 10)
                            Text(walletName)
                                .appFont(.caption)
                        }
                        if let goalName = config.savingsGoalName {
                            Text("·").foregroundStyle(.tertiary)
                            Image(systemName: "target")
                                .appFont(size: 10)
                            Text(goalName)
                                .appFont(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                // Transaction type badge
                if let type = config.transactionType {
                    let isExpense = type == .expense
                    let typeColor = isExpense ? ThemeManager.shared.expenseColor : ThemeManager.shared.incomeColor
                    HStack(spacing: 3) {
                        Image(systemName: isExpense ? "arrow.down" : "arrow.up")
                            .appFont(size: 10, weight: .bold)
                        Text(isExpense ? L10n.Transaction.TransactionType.expense : L10n.Transaction.TransactionType.income)
                            .appFont(.caption, weight: .semibold)
                    }
                    .foregroundStyle(typeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(typeColor.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // MARK: Stats — total amount | transaction count
            HStack(alignment: .firstTextBaseline) {
                Text(vm.totalAmount.formattedAmount(for: preferredCurrency))
                    .appFont(.title2, weight: .bold)
                    .monospacedDigit()

                Spacer()

                Text("filteredTransactions.count".localized(with: vm.transactions.count))
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .redacted(reason: vm.hasLoadedOnce ? [] : .placeholder)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }
}

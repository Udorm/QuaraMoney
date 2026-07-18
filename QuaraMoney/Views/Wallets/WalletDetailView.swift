import SwiftUI
import SwiftData

struct WalletDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: WalletDetailViewModel

    @State private var showingAddExpense = false
    @State private var showingAddIncome = false
    @State private var transactionToEdit: Transaction?
    @State private var showingEditWallet = false
    @State private var showingAdjustBalance = false

    init(wallet: Wallet, modelContext: ModelContext) {
        _viewModel = State(wrappedValue: WalletDetailViewModel(modelContext: modelContext, wallet: wallet))
    }

    private var walletColor: Color {
        Color(hex: viewModel.wallet.colorHex) ?? .blue
    }

    /// Income / expense earned and spent from this wallet in the selected period.
    private var periodIncome: Decimal {
        viewModel.transactions
            .filter { $0.type == .income && $0.sourceWallet?.id == viewModel.wallet.id }
            .reduce(0) { $0 + viewModel.wallet.amountInWalletCurrency(for: $1) }
    }

    private var periodExpense: Decimal {
        viewModel.transactions
            .filter { $0.type == .expense && $0.sourceWallet?.id == viewModel.wallet.id }
            .reduce(0) { $0 + viewModel.wallet.amountInWalletCurrency(for: $1) }
    }

    var body: some View {
        List {
            Section {
                heroCard
                    .redacted(reason: viewModel.hasLoadedOnce ? [] : .placeholder)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                quickActionsRow
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // Period selector
            Section {
                GlassPeriodSelector(
                    selectedTab: $viewModel.selectedTab,
                    months: Array(viewModel.availableMonths.suffix(3))
                )
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if case .custom = viewModel.selectedTab {
                    HStack {
                        Spacer()
                        DatePicker("filter.startDate".localized, selection: $viewModel.customStartDate, displayedComponents: .date)
                            .labelsHidden()
                            .appFont(.subheadline)
                        Text("-")
                            .foregroundStyle(.secondary)
                            .appFont(.subheadline)
                        DatePicker("filter.endDate".localized, selection: $viewModel.customEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .appFont(.subheadline)
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
            .listRowSeparator(.hidden)

            // Transactions
            if !viewModel.hasLoadedOnce {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            } else if viewModel.transactions.isEmpty {
                Section {
                    AppEmptyStateView(
                        "home.emptyPeriod.title".localized,
                        systemImage: "list.bullet.clipboard",
                        description: "home.noTransactions".localized
                    )
                }
            } else {
                TransactionListView(
                    transactions: viewModel.transactions,
                    sortOption: viewModel.sortOption,
                    listHeader: viewModel.filterDescription,
                    onEdit: { txn in
                        transactionToEdit = txn
                    },
                    onDelete: { txn in
                        viewModel.deleteTransaction(txn)
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .contentMargins(.top, 8, for: .scrollContent)
        // The wallet name lives in the hero card; keep the bar chrome minimal.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $viewModel.sortOption, label: Text(L10n.Sort.title)) {
                        ForEach(TransactionSortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("a11y.sortTransactions".localized)

                Button {
                    showingEditWallet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(L10n.Common.edit)
            }
        }
        .sheet(isPresented: $showingEditWallet) {
            AddWalletView(viewModel: AddWalletViewModel(
                dataService: SwiftDataService(modelContext: modelContext),
                walletToEdit: viewModel.wallet
            ))
        }
        .sheet(isPresented: $showingAddExpense) {
            AddTransactionContainer(isNewTransaction: true, initialWallet: viewModel.wallet, initialType: .expense)
        }
        .sheet(isPresented: $showingAddIncome) {
            AddTransactionContainer(isNewTransaction: true, initialWallet: viewModel.wallet, initialType: .income)
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
            viewModel.setVisible(true)
        }
        .onDisappear { viewModel.setVisible(false) }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Identity row — wallet name lives here (nav title is hidden)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.wallet.currencyCode)
                        .appFont(.caption2, weight: .semibold)
                        .foregroundStyle(.white.opacity(0.7))
                        .textCase(.uppercase)
                    Text(viewModel.wallet.name)
                        .appFont(.title2, weight: .bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()

                if viewModel.wallet.isArchived {
                    Text(L10n.Wallet.archived)
                        .appFont(.caption2, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.25), in: Capsule())
                }

                Image(systemName: viewModel.wallet.icon)
                    .appFont(size: 22)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer()

            // Balance + period in/out
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.wallet.balance.formattedAmount(for: viewModel.wallet.currencyCode))
                    .appFont(.title, weight: .bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: 14) {
                    heroStat(
                        icon: "arrow.down.left",
                        label: "transaction.type.income".localized,
                        amount: periodIncome
                    )

                    Rectangle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 1, height: 26)

                    heroStat(
                        icon: "arrow.up.right",
                        label: "transaction.type.expense".localized,
                        amount: periodExpense
                    )

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(height: 190)
        .background(
            // Decorative layer: sits on top of the glass, under the content.
            ZStack {
                // Same decorative texture as the Add Wallet preview card.
                Circle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 190, height: 190)
                    .offset(x: 130, y: -90)
                Circle()
                    .fill(.white.opacity(0.05))
                    .frame(width: 240, height: 240)
                    .offset(x: -140, y: 110)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .background(walletColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.wallet.name), balance \(viewModel.wallet.balance.formattedAmount(for: viewModel.wallet.currencyCode))")
    }

    private func heroStat(icon: String, label: String, amount: Decimal) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .appFont(.caption2, weight: .bold)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .appFont(.caption2)
                    .opacity(0.7)
                Text(amount.formattedAmountShort(for: viewModel.wallet.currencyCode))
                    .appFont(.footnote, weight: .semibold)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            // Icons mirror the hero card's in/out stat glyphs so the actions
            // read as "money out" / "money in" at a glance.
            quickActionButton(
                icon: "arrow.up.right",
                title: "wallet.action.addExpense".localized
            ) {
                showingAddExpense = true
            }
            quickActionButton(
                icon: "arrow.down.left",
                title: "wallet.action.addIncome".localized
            ) {
                showingAddIncome = true
            }
            quickActionButton(
                icon: "slider.horizontal.3",
                title: "wallet.adjustBalance".localized
            ) {
                showingAdjustBalance = true
            }
        }
    }

    private func quickActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .appFont(.footnote, weight: .semibold)
                Text(title)
                    .appFont(.footnote, weight: .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Capsule())
            .background(walletColor, in: Capsule())
        }
        .buttonStyle(QuickActionPressStyle())
    }
}

/// Press feedback for the quick-action capsules: scale down + dim, so the
/// effect stays inside the row bounds and can never be clipped.
private struct QuickActionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

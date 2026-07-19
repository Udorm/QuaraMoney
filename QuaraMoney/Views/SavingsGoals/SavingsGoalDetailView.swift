import SwiftUI
import SwiftData
import Charts

struct SavingsGoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: SavingsGoal

    @State private var showAddContribution = false
    @State private var showWithdrawal = false
    @State private var showEditGoal = false

    private var goalColor: Color {
        Color(hex: goal.colorHex) ?? .blue
    }

    var body: some View {
        List {
            // MARK: - Header Section with Donut Chart
            Section {
                VStack(spacing: 24) {
                    // Header Info
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.name)
                                .appFont(.title2, weight: .bold)

                            if let targetDate = goal.targetDate {
                                Text(targetDate.appFormatted(date: .abbreviated, time: .omitted))
                                    .appFont(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let days = goal.daysRemaining, days > 0 {
                                Text(L10n.Budget.daysLeft(days))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: goal.iconName)
                            .appFont(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(goalColor.gradient)
                            .clipShape(Circle())
                            .shadow(color: goalColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 4)

                    // Donut Chart
                    ZStack {
                        Chart {
                            if SavingsGoalReconciler.total(for: goal).total >= goal.targetAmount {
                                SectorMark(
                                    angle: .value("Saved", 100),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(goalColor.gradient)
                            } else {
                                SectorMark(
                                    angle: .value("Saved", Double(truncating: goal.totalSaved(converter: CurrencyManager.shared.convert) as NSNumber)),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(goalColor.gradient)
                                .cornerRadius(4)

                                SectorMark(
                                    angle: .value("Remaining", max(0, Double(truncating: goal.remainingAmount(converter: CurrencyManager.shared.convert) as NSNumber))),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color(.systemGray5))
                                .cornerRadius(4)
                            }
                        }
                        .frame(height: 220)

                        // Center Label
                        VStack(spacing: 4) {
                            Text(goal.progressPercent(converter: CurrencyManager.shared.convert))
                                .appFont(.largeTitle, weight: .bold)
                                .foregroundStyle(SavingsGoalReconciler.total(for: goal).total >= goal.targetAmount ? goalColor : .primary)

                            Text(SavingsGoalReconciler.total(for: goal).total >= goal.targetAmount ? L10n.Savings.complete : L10n.Savings.progress)
                                .appFont(.subheadline, weight: .medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))

            // MARK: - Goal Progress Section
            Section(L10n.Budget.summary) {
                HStack {
                    Text(L10n.Savings.totalSaved)
                    Spacer()
                    Text(goal.totalSaved(converter: CurrencyManager.shared.convert).formattedAmount(for: goal.currencyCode))
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(goalColor)
                }

                HStack {
                    Text(L10n.Savings.targetAmount)
                    Spacer()
                    Text(goal.targetAmount.formattedAmount(for: goal.currencyCode))
                        .foregroundStyle(.secondary)
                }

                if goal.currentAmount > 0 || goal.transactionContributedAmount(converter: CurrencyManager.shared.convert) > 0 {
                    HStack {
                        Text("savings.starting_balance".localized)
                        Spacer()
                        Text(goal.currentAmount.formattedAmount(for: goal.currencyCode))
                            .foregroundStyle(.secondary)
                            .appFont(.caption)
                    }

                    HStack {
                        Text(L10n.Savings.transferContributions)
                        Spacer()
                        Text(goal.transactionContributedAmount(converter: CurrencyManager.shared.convert).formattedAmount(for: goal.currencyCode))
                            .foregroundStyle(.secondary)
                            .appFont(.caption)
                    }
                }

                if let suggested = goal.suggestedMonthlyContribution(converter: CurrencyManager.shared.convert) {
                    HStack {
                        Text(L10n.Savings.monthlyNeeded)
                        Spacer()
                        Text(suggested.formattedAmount(for: goal.currencyCode))
                            .foregroundStyle(.blue)
                    }
                }

                HStack {
                    Text(L10n.Savings.status)
                    Spacer()
                    Text(goal.statusMessage)
                        .foregroundStyle(goal.isOnTrack(converter: CurrencyManager.shared.convert) ? .green : .orange)
                        .appFont(.subheadline, weight: .medium)
                }

                if let wallet = goal.linkedWallet {
                    HStack {
                        Text(L10n.Savings.wallet)
                        Spacer()
                        Label(wallet.name, systemImage: wallet.icon)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Contribution History
            Section(L10n.Savings.contributionHistory) {
                let transactions = goal.linkedTransactions ?? []
                if transactions.isEmpty {
                    Text(L10n.Savings.noLinkedTransactions)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    let config = TransactionFilterConfig(
                        title: goal.name,
                        startDate: .distantPast,
                        endDate: .distantFuture,
                        dateRangeDescription: L10n.Filter.allTime,
                        savingsGoalId: goal.id,
                        savingsGoalName: goal.name
                    )
                    NavigationLink {
                        FilteredTransactionsDetailView(config: config)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(transactions.count) " + "filteredTransactions.transactionsLabel".localized)
                                    .appFont(.subheadline, weight: .medium)
                                Text(goal.transactionContributedAmount(converter: CurrencyManager.shared.convert).formattedAmount(for: goal.currencyCode))
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    ForEach(transactions.filter { SavingsLedger.isEligible($0, for: goal) }.prefix(5)) { transaction in
                        HStack {
                            Label(transaction.savingsIsWithdrawal ? "savings.withdrawal".localized : "savings.contribution".localized,
                                  systemImage: transaction.savingsIsWithdrawal ? "arrow.up.right" : "arrow.down.left")
                            Spacer()
                            if let side = TransferSideAmountResolver.ledgerAmount(for: transaction) {
                                Text((transaction.savingsIsWithdrawal ? -side.amount : side.amount)
                                    .formattedAmount(for: side.currencyCode))
                                    .appFont(size: 15, weight: .semibold).monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("savings.contribution".localized, systemImage: "arrow.down.left") { showAddContribution = true }
                    Button("savings.withdrawal".localized, systemImage: "arrow.up.right") { showWithdrawal = true }
                } label: { Image(systemName: "plus") }
                .accessibilityLabel(L10n.Savings.recordContribution)

                Button {
                    showEditGoal = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(L10n.Savings.edit)
            }
        }
        .sheet(isPresented: $showAddContribution) {
            SavingsContributionSheet(goal: goal, isWithdrawal: false)
        }
        .sheet(isPresented: $showWithdrawal) {
            SavingsContributionSheet(goal: goal, isWithdrawal: true)
        }
        .sheet(isPresented: $showEditGoal) {
            EditSavingsGoalView(goal: goal)
        }
    }

    private var daysColor: Color {
        guard let days = goal.daysRemaining else { return .secondary }
        if days < 14 { return .red }
        if days < 30 { return .orange }
        return .green
    }
}

// MARK: - Savings Contribution Sheet (wraps AddTransactionView)

private struct SavingsContributionSheet: View {
    @Environment(\.modelContext) private var modelContext
    let goal: SavingsGoal
    let isWithdrawal: Bool

    var body: some View {
        let vm = AddTransactionViewModel(
            dataService: SwiftDataService(modelContext: modelContext),
            initialWallet: nil
        )
        let _ = configureSavingsTransfer(vm)
        AddTransactionView(viewModel: vm, isNewTransaction: true)
    }

    private func configureSavingsTransfer(_ vm: AddTransactionViewModel) {
        vm.type = .transfer
        vm.note = goal.name
        vm.selectedSavingsGoal = goal
        vm.savingsIsWithdrawal = isWithdrawal
        if let wallet = goal.linkedWallet {
            if isWithdrawal { vm.selectedWallet = wallet }
            else { vm.destinationWallet = wallet }
        }
    }
}

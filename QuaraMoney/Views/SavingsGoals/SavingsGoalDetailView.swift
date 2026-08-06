import Charts
import SwiftData
import SwiftUI

struct SavingsGoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let wallet: Wallet?
    private let legacyGoal: SavingsGoal?

    @State private var showContribution = false
    @State private var showWithdrawal = false
    @State private var showEditForm = false
    @State private var showCelebration = false

    init(wallet: Wallet) {
        self.wallet = wallet
        self.legacyGoal = nil
    }

    /// Read-only compatibility path for a legacy row whose deterministic
    /// migration is deferred or needs attention.
    init(goal: SavingsGoal) {
        self.wallet = nil
        self.legacyGoal = goal
    }

    var body: some View {
        Group {
            if let wallet {
                savingsWalletBody(wallet)
            } else if let legacyGoal {
                legacyPendingBody(legacyGoal)
            }
        }
        .navigationTitle(wallet?.name ?? legacyGoal?.name ?? "plan.savings".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if wallet != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.edit".localized) { showEditForm = true }
                }
            }
        }
        .sheet(isPresented: $showContribution) {
            if let wallet { SavingsContributionSheet(wallet: wallet, isWithdrawal: false) }
        }
        .sheet(isPresented: $showWithdrawal) {
            if let wallet { SavingsContributionSheet(wallet: wallet, isWithdrawal: true) }
        }
        .sheet(isPresented: $showEditForm) {
            if let wallet { SavingsGoalFormView(existing: wallet) { dismiss() } }
        }
        .alert("savings.reachedTitle".localized, isPresented: $showCelebration) {
            Button("common.ok".localized) {}
        } message: {
            Text("savings.reachedMessage".localized)
        }
        .onAppear { latchCelebrationIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            wallet?.invalidateBalanceCache()
            latchCelebrationIfNeeded()
        }
    }

    private func savingsWalletBody(_ wallet: Wallet) -> some View {
        let color = Color(hex: wallet.colorHex) ?? .green
        return ScrollView {
            LazyVStack(spacing: 16) {
                PlanCard(tint: color) {
                    HStack(spacing: 18) {
                        Image(systemName: wallet.icon)
                            .appFont(size: 32, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(width: 78, height: 78)
                            .background(color.gradient, in: RoundedRectangle(
                                cornerRadius: CornerRadius.large,
                                style: .continuous
                            ))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(wallet.name).appFont(.title2, weight: .bold)
                            if let targetDate = wallet.targetDate {
                                Text("plan.target_date_value".localized(
                                    with: targetDate.appFormatted(date: .abbreviated, time: .omitted)
                                ))
                                .appFont(.subheadline)
                                .foregroundStyle(.secondary)
                            } else {
                                Text("savings.status.noDate".localized)
                                    .appFont(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if wallet.isSavingsReached {
                                Label("savings.reached".localized, systemImage: "checkmark.circle.fill")
                                    .appFont(.caption, weight: .semibold)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                    }
                }

                PlanCard {
                    Text("plan.savings_progress".localized).appFont(.headline, weight: .bold)
                    PlanAmountSummary(
                        title: "plan.saved".localized,
                        amount: wallet.balance.formattedAmount(for: wallet.currencyCode),
                        targetAmount: (wallet.targetAmount ?? 0).formattedAmount(for: wallet.currencyCode),
                        amountColor: wallet.balance < 0 ? .red : color
                    )
                    PlanProgressLine(progress: wallet.savingsProgress, color: color)
                    HStack(spacing: 16) {
                        statColumn(
                            title: "plan.to_go".localized,
                            value: (wallet.savingsRemaining ?? 0).formattedAmount(for: wallet.currencyCode)
                        )
                        if let monthly = wallet.suggestedMonthlyContribution() {
                            Divider().frame(height: 44)
                            statColumn(
                                title: "plan.monthly_target".localized,
                                value: monthly.formattedAmount(for: wallet.currencyCode)
                            )
                        }
                    }
                }

                progressCard(wallet, color: color)
                recentActivityCard(wallet, color: color)

                VStack(spacing: 10) {
                    Button {
                        showContribution = true
                    } label: {
                        Label("plan.add_money".localized, systemImage: "plus.circle.fill")
                            .appFont(.headline, weight: .semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(color)
                    .controlSize(.large)

                    Button("plan.withdraw".localized) { showWithdrawal = true }
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func legacyPendingBody(_ goal: SavingsGoal) -> some View {
        ScrollView {
            PlanCard(tint: .orange) {
                Label("savings.migrationPending".localized, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(.orange)
                Text("savings.migrationPendingDetail".localized)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                PlanAmountSummary(
                    title: "plan.target".localized,
                    amount: goal.targetAmount.formattedAmount(for: goal.currencyCode),
                    amountColor: .orange
                )
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).appFont(.caption).foregroundStyle(.secondary)
            Text(value).appFont(.subheadline, weight: .semibold).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct MonthPoint: Identifiable {
        let date: Date
        let balance: Decimal
        let isUpcoming: Bool
        var id: Date { date }
    }

    private func monthPoints(_ wallet: Wallet) -> [MonthPoint] {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let transactions = ((wallet.outgoingTransactions ?? []) + (wallet.incomingTransactions ?? []))
            .reduce(into: [UUID: Transaction]()) { $0[$1.id] = $1 }
            .values
        var points: [MonthPoint] = []
        for offset in (-11)...0 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: currentMonth),
                  let next = calendar.date(byAdding: .month, value: 1, to: month) else { continue }
            let balance = transactions.reduce(Decimal.zero) { total, transaction in
                guard transaction.date < next, let delta = wallet.ledgerDelta(for: transaction) else { return total }
                return total + delta
            }
            points.append(MonthPoint(date: month, balance: balance, isUpcoming: false))
        }
        if let targetDate = wallet.targetDate,
           targetDate >= (calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? now) {
            let targetMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: targetDate)) ?? targetDate
            points.append(MonthPoint(
                date: targetMonth,
                balance: wallet.targetAmount ?? wallet.balance,
                isUpcoming: true
            ))
        }
        return points
    }

    private func progressCard(_ wallet: Wallet, color: Color) -> some View {
        let points = monthPoints(wallet)
        return PlanCard {
            Text("plan.progress_over_time".localized).appFont(.headline, weight: .bold)
            Chart(points) { point in
                BarMark(
                    x: .value("plan.month".localized, point.date, unit: .month),
                    y: .value(
                        "plan.saved".localized,
                        MoneyMinorUnitConverter.toMinorUnits(point.balance, currencyCode: wallet.currencyCode)
                    )
                )
                .foregroundStyle(point.isUpcoming ? Color.orange.gradient : color.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let upcoming = points.contains {
                                $0.isUpcoming && Calendar.current.isDate($0.date, equalTo: date, toGranularity: .month)
                            }
                            Text(upcoming
                                 ? "plan.upcoming".localized
                                 : AppDateFormatterCache.formatter(dateFormat: "MMM", locale: .app).string(from: date))
                                .appFont(.caption2)
                        }
                    }
                }
            }
            .frame(height: 220)
        }
    }

    private func recentActivityCard(_ wallet: Wallet, color: Color) -> some View {
        let rows = ((wallet.outgoingTransactions ?? []) + (wallet.incomingTransactions ?? []))
            .reduce(into: [UUID: Transaction]()) { $0[$1.id] = $1 }
            .values
            .filter { $0.deletedAt == nil && ($0.type == .transfer || $0.type == .adjustment) }
            .sorted { $0.date > $1.date }
            .prefix(5)
        return PlanCard(spacing: 10) {
            Text("savings.recentActivity".localized).appFont(.headline, weight: .bold)
            if rows.isEmpty {
                Text("plan.no_contributions".localized)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(rows)) { transaction in
                    HStack {
                        Image(systemName: (wallet.ledgerDelta(for: transaction) ?? 0) >= 0
                              ? "arrow.down.left" : "arrow.up.right")
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(color)
                        VStack(alignment: .leading) {
                            Text(transaction.note ?? "savings.activity".localized)
                                .appFont(.subheadline, weight: .medium)
                            Text(transaction.date.appFormatted(date: .abbreviated, time: .shortened))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((wallet.ledgerDelta(for: transaction) ?? 0).formattedAmount(for: wallet.currencyCode))
                            .appFont(.subheadline, weight: .semibold)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func latchCelebrationIfNeeded() {
        guard let wallet, wallet.isSavingsReached, !wallet.hasCelebrated else { return }
        wallet.hasCelebrated = true
        wallet.updatedAt = Date()
        wallet.needsSync = true
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            showCelebration = true
        } catch {
            modelContext.rollback()
        }
    }
}

struct SavingsContributionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]

    let wallet: Wallet
    let isWithdrawal: Bool

    @State private var counterpartID: UUID?
    @State private var amount = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var errorMessage: String?

    init(wallet: Wallet, isWithdrawal: Bool) {
        self.wallet = wallet
        self.isWithdrawal = isWithdrawal
        _wallets = Query(filter: #Predicate<Wallet> { $0.deletedAt == nil && $0.isArchived == false })
    }

    private var counterparts: [Wallet] { wallets.filter { $0.id != wallet.id } }
    private var selectedCounterpart: Wallet? { counterparts.first { $0.id == counterpartID } }
    private var parsedAmount: Decimal? { Decimal(string: amount) }

    var body: some View {
        NavigationStack {
            Form {
                Section("common.details".localized) {
                    Picker("savings.transferAccount".localized, selection: $counterpartID) {
                        Text("common.select".localized).tag(UUID?.none)
                        ForEach(counterparts) { item in
                            Text(item.name).tag(UUID?.some(item.id))
                        }
                    }
                    TextField("transaction.amount".localized, text: $amount)
                        .keyboardType(.decimalPad)
                    DatePicker("transaction.date".localized, selection: $date)
                    TextField("transaction.note".localized, text: $note)
                }
            }
            .navigationTitle(isWithdrawal ? "plan.withdraw".localized : "plan.add_money".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save".localized) { save() }
                        .disabled(selectedCounterpart == nil || (parsedAmount ?? 0) <= 0)
                }
            }
            .alert(
                "common.error".localized,
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("common.ok".localized) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let counterpart = selectedCounterpart, let amount = parsedAmount, amount > 0 else { return }
        let source = isWithdrawal ? wallet : counterpart
        let destination = isWithdrawal ? counterpart : wallet
        let transaction = Transaction(
            amount: amount,
            currencyCode: source.currencyCode,
            date: date,
            type: .transfer
        )
        transaction.note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (isWithdrawal ? "plan.withdrawal".localized : "plan.contribution".localized)
            : note
        transaction.sourceWallet = source
        transaction.destinationWallet = destination
        transaction.storedRate = SoftDeleteService.conversionRate(
            from: source.currencyCode,
            to: destination.currencyCode
        )
        transaction.exchangeRate = transaction.storedRate ?? 1
        do {
            try WalletLedgerRules.validate(transaction: transaction)
            modelContext.insert(transaction)
            try modelContext.save()
            source.invalidateBalanceCache()
            destination.invalidateBalanceCache()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            HapticManager.shared.success()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}

#Preview {
    let wallet = Wallet(name: "Emergency Fund", currencyCode: "USD", icon: "target", colorHex: "#10B981")
    wallet.kind = .savings
    wallet.targetAmount = 10_000
    return NavigationStack { SavingsGoalDetailView(wallet: wallet) }
        .modelContainer(for: [SavingsGoal.self, Transaction.self, Wallet.self], inMemory: true)
}

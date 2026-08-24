import SwiftUI
import SwiftData

struct DebtOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Debt> { $0.deletedAt == nil }, sort: \Debt.dateCreated, order: .reverse)
    private var allDebts: [Debt]

    @State private var viewModel = DebtListViewModel()
    @State private var showAddDebtSheet = false
    @State private var addDebtType: DebtType = .iOwe

    private var preferredCurrency: String { CurrencyManager.shared.preferredCurrencyCode }

    private var debtsOwed: [Debt] {
        allDebts.filter { $0.type == .iOwe }
    }

    private var debtsLent: [Debt] {
        allDebts.filter { $0.type == .owedToMe }
    }

    private var totalIOwe: Decimal {
        viewModel.totalIOwe(allDebts)
    }

    private var totalOwedToMe: Decimal {
        viewModel.totalOwedToMe(allDebts)
    }

    private var netPosition: Decimal {
        totalOwedToMe - totalIOwe
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Top financial overview summary
                netSummaryCard

                // Card 1: Money I Owe (Debts / Liabilities)
                NavigationLink {
                    LazyView(DebtDedicatedListView(type: .iOwe))
                } label: {
                    debtsCard
                }
                .buttonStyle(.plain)

                // Card 2: Money Lent (Loans / Receivables)
                NavigationLink {
                    LazyView(DebtDedicatedListView(type: .owedToMe))
                } label: {
                    loansCard
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.Debt.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        addDebtType = .iOwe
                        showAddDebtSheet = true
                    } label: {
                        Label("debt.overview.iBorrowed".localized, systemImage: "arrow.up.right")
                    }

                    Button {
                        addDebtType = .owedToMe
                        showAddDebtSheet = true
                    } label: {
                        Label("debt.overview.iLent".localized, systemImage: "arrow.down.left")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("debt.overview.quickActions".localized)
            }
        }
        .syncPullToRefresh(modelContext)
        .sheet(isPresented: $showAddDebtSheet) {
            AddDebtView(initialType: addDebtType)
        }
        .onAppear { normalizeCompletionStates() }
        .onChange(of: allDebts.count) { _, _ in normalizeCompletionStates() }
    }

    // MARK: - Net Position Summary Card

    private var netSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("debt.netPosition".localized)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)

                Text(abs(netPosition).formattedAmount(for: preferredCurrency))
                    .appFont(size: 32, weight: .bold)
                    .foregroundStyle(netPosition == 0 ? Color.primary : (netPosition > 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(netCaption)
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
            }

            divergingBar

            HStack(spacing: 0) {
                overviewStat(
                    title: "debt.overview.totalBorrowed".localized,
                    amount: totalIOwe,
                    color: ThemeManager.shared.expenseColor,
                    icon: "arrow.up.right"
                )
                Divider().frame(height: 32)
                overviewStat(
                    title: "debt.overview.totalLent".localized,
                    amount: totalOwedToMe,
                    color: ThemeManager.shared.incomeColor,
                    icon: "arrow.down.left"
                )
            }
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        )
    }

    private var netCaption: String {
        if netPosition > 0 { return "debt.youAreOwed".localized }
        if netPosition < 0 { return "debt.youOwe".localized }
        return "debt.allSettled".localized
    }

    private var divergingBar: some View {
        let total = totalOwedToMe + totalIOwe
        let owedFraction: Double = total > 0
            ? NSDecimalNumber(decimal: totalOwedToMe / total).doubleValue
            : 0.5

        return GeometryReader { geo in
            let owedWidth = max(0, owedFraction) * (geo.size.width - 2)
            let oweWidth = (geo.size.width - 2) - owedWidth
            HStack(spacing: 2) {
                Capsule()
                    .fill(ThemeManager.shared.incomeColor.gradient)
                    .frame(width: owedWidth)
                    .overlay {
                        if owedWidth > 22 {
                            Image(systemName: "arrow.down.left")
                                .appFont(size: 8, weight: .bold)
                                .foregroundStyle(.white)
                        }
                    }
                Capsule()
                    .fill(ThemeManager.shared.expenseColor.gradient)
                    .overlay {
                        if oweWidth > 22 {
                            Image(systemName: "arrow.up.right")
                                .appFont(size: 8, weight: .bold)
                                .foregroundStyle(.white)
                        }
                    }
            }
        }
        .frame(height: 10)
        .opacity(total > 0 ? 1 : 0.25)
        .accessibilityElement()
        .accessibilityLabel("\("debt.youAreOwed".localized) \(totalOwedToMe.formattedAmount(for: preferredCurrency)), \("debt.youOwe".localized) \(totalIOwe.formattedAmount(for: preferredCurrency))")
    }

    private func overviewStat(title: String, amount: Decimal, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .appFont(size: 11, weight: .bold)
                    .foregroundStyle(color)
                Text(title)
                    .appFont(.caption2, weight: .medium)
                    .foregroundStyle(.secondary)
            }
            Text(amount.formattedAmount(for: preferredCurrency))
                .appFont(.callout, weight: .bold)
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, title == "debt.overview.totalLent".localized ? 16 : 0)
    }

    // MARK: - Debts Card (I Owe)

    private var debtsCard: some View {
        let activeDebts = debtsOwed.filter { !$0.isCompleted }
        let overdueCount = activeDebts.filter { $0.isOverdue }.count
        let totalPrincipal = activeDebts.reduce(0) { sum, d in
            sum + CurrencyManager.convert(amount: d.currentTotalAmount, from: d.currencyCode, to: preferredCurrency, rates: CurrencyManager.shared.rates)
        }
        let totalPaid = activeDebts.reduce(0) { sum, d in
            sum + CurrencyManager.convert(amount: d.amountPaid, from: d.currencyCode, to: preferredCurrency, rates: CurrencyManager.shared.rates)
        }
        let progress: Double = totalPrincipal > 0
            ? min(1, max(0, NSDecimalNumber(decimal: totalPaid / totalPrincipal).doubleValue))
            : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "arrow.up.right")
                            .appFont(size: 20, weight: .bold)
                            .foregroundStyle(Color.red)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("debt.debtsCard.title".localized)
                        .appFont(.headline, weight: .bold)
                        .foregroundStyle(Color.primary)
                    Text("debt.debtsCard.subtitle".localized)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.secondary)
            }

            if debtsOwed.isEmpty {
                Text("debt.noActiveDebtsDescription".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            } else if activeDebts.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("debt.hero.debtFree".localized)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.green)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("debt.hero.totalDebt".localized)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)

                    Text(totalIOwe.formattedAmount(for: preferredCurrency))
                        .appFont(.title2, weight: .bold)
                        .foregroundStyle(Color.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if totalPaid > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        DebtProgressBar(progress: progress, tint: .red, height: 6)
                        HStack {
                            Text("debt.hero.paidSoFar".localized)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(totalPaid.formattedAmount(for: preferredCurrency))
                                .appFont(.caption2, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if overdueCount > 0 {
                        Label("\(overdueCount) \("debt.overdue".localized.lowercased())", systemImage: "exclamationmark.circle.fill")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.red)
                    }

                    Text("debt.overview.activeDebtsCount".localized(with: activeDebts.count))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(
            Color.red.opacity(0.06),
            in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .stroke(Color.red.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Loans Card (Owed To Me)

    private var loansCard: some View {
        let activeLoans = debtsLent.filter { !$0.isCompleted }
        let overdueCount = activeLoans.filter { $0.isOverdue }.count
        let totalPrincipal = activeLoans.reduce(0) { sum, d in
            sum + CurrencyManager.convert(amount: d.currentTotalAmount, from: d.currencyCode, to: preferredCurrency, rates: CurrencyManager.shared.rates)
        }
        let totalCollected = activeLoans.reduce(0) { sum, d in
            sum + CurrencyManager.convert(amount: d.amountPaid, from: d.currencyCode, to: preferredCurrency, rates: CurrencyManager.shared.rates)
        }
        let progress: Double = totalPrincipal > 0
            ? min(1, max(0, NSDecimalNumber(decimal: totalCollected / totalPrincipal).doubleValue))
            : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "arrow.down.left")
                            .appFont(size: 20, weight: .bold)
                            .foregroundStyle(Color.green)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text("debt.loansCard.title".localized)
                        .appFont(.headline, weight: .bold)
                        .foregroundStyle(Color.primary)
                    Text("debt.loansCard.subtitle".localized)
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.secondary)
            }

            if debtsLent.isEmpty {
                Text("debt.noActiveLoansDescription".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            } else if activeLoans.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("debt.hero.allCollected".localized)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.green)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("debt.hero.totalLent".localized)
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)

                    Text(totalOwedToMe.formattedAmount(for: preferredCurrency))
                        .appFont(.title2, weight: .bold)
                        .foregroundStyle(Color.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if totalCollected > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        DebtProgressBar(progress: progress, tint: .green, height: 6)
                        HStack {
                            Text("debt.hero.collectedSoFar".localized)
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(totalCollected.formattedAmount(for: preferredCurrency))
                                .appFont(.caption2, weight: .semibold)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if overdueCount > 0 {
                        Label("\(overdueCount) \("debt.overdue".localized.lowercased())", systemImage: "exclamationmark.circle.fill")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(.red)
                    }

                    Text("debt.overview.activeLoansCount".localized(with: activeLoans.count))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(
            Color.green.opacity(0.06),
            in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                .stroke(Color.green.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Normalization

    private func normalizeCompletionStates() {
        let tolerance: Decimal = 0.000001
        var didChange = false

        for debt in allDebts {
            let shouldBeCompleted = debt.remainingAmount <= tolerance
            if debt.isCompleted != shouldBeCompleted {
                debt.isCompleted = shouldBeCompleted
                didChange = true
            }
        }

        if didChange {
            do {
                try modelContext.save()
            } catch {
                ErrorService.shared.handlePersistenceError(error, context: "DebtOverviewView.normalizeCompletionStates")
            }
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        }
    }
}

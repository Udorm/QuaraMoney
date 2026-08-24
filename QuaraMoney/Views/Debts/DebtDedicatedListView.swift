import SwiftUI
import SwiftData

enum DebtSegment: String, CaseIterable, Identifiable {
    case active
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "debt.activeSection".localized
        case .completed: return "debt.completedSection".localized
        }
    }
}

struct DebtDedicatedListView: View {
    let type: DebtType

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Debt> { $0.deletedAt == nil }, sort: \Debt.dateCreated, order: .reverse)
    private var allDebts: [Debt]

    @State private var segment: DebtSegment = .active
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var debtToEdit: Debt?
    @State private var debtToDelete: Debt?
    @State private var showingDeleteAlert = false

    private var preferredCurrency: String { CurrencyManager.shared.preferredCurrencyCode }

    private var typeDebts: [Debt] {
        allDebts.filter { $0.type == type }
    }

    private var filteredDebts: [Debt] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return typeDebts
        }
        return typeDebts.filter { debt in
            debt.personName.localizedCaseInsensitiveContains(query) ||
            (debt.note?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var overdueDebts: [Debt] {
        filteredDebts
            .filter { !$0.isCompleted && $0.isOverdue }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var activeDebts: [Debt] {
        filteredDebts
            .filter { !$0.isCompleted && !$0.isOverdue }
            .sorted { a, b in
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?): return x < y
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return a.dateCreated > b.dateCreated
                }
            }
    }

    private var completedDebts: [Debt] {
        filteredDebts.filter { $0.isCompleted }
    }

    private var totalOutstanding: Decimal {
        typeDebts.filter { !$0.isCompleted }.reduce(0) { sum, d in
            sum + CurrencyManager.convert(
                amount: d.displayRemaining,
                from: d.currencyCode,
                to: preferredCurrency,
                rates: CurrencyManager.shared.rates
            )
        }
    }

    private var totalPaidOrCollected: Decimal {
        typeDebts.filter { !$0.isCompleted }.reduce(0) { sum, d in
            sum + CurrencyManager.convert(
                amount: d.amountPaid,
                from: d.currencyCode,
                to: preferredCurrency,
                rates: CurrencyManager.shared.rates
            )
        }
    }

    private var totalPrincipal: Decimal {
        typeDebts.filter { !$0.isCompleted }.reduce(0) { sum, d in
            sum + CurrencyManager.convert(
                amount: d.currentTotalAmount,
                from: d.currencyCode,
                to: preferredCurrency,
                rates: CurrencyManager.shared.rates
            )
        }
    }

    private var progress: Double {
        guard totalPrincipal > 0 else { return 0 }
        let ratio = NSDecimalNumber(decimal: totalPaidOrCollected / totalPrincipal).doubleValue
        return min(max(ratio, 0), 1)
    }

    private var navigationTitle: String {
        type == .iOwe ? "debt.dedicatedTitle.iOwe".localized : "debt.dedicatedTitle.owedToMe".localized
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            // Segment picker (scrolls with content, non-sticky)
            Section {
                Picker(L10n.Filter.title, selection: $segment) {
                    ForEach(DebtSegment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }
            .listRowBackground(Color.clear)

            if segment == .active {
                activeContent
            } else {
                completedContent
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(navigationTitle)
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "debt.searchPrompt".localized
        )
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.Debt.add)
            }
        }
        .syncPullToRefresh(modelContext)
        .sheet(isPresented: $showAddSheet) {
            AddDebtView(initialType: type)
        }
        .sheet(item: $debtToEdit) { debt in
            AddDebtView(debtToEdit: debt)
        }
        .alert(L10n.Common.delete, isPresented: $showingDeleteAlert, presenting: debtToDelete) { debt in
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.delete, role: .destructive) {
                deleteDebt(debt)
            }
        } message: { debt in
            Text(L10n.Debt.deleteRelatedTransactionsWarning(linkedTransactionCount(debt)))
        }
    }

    // MARK: - Active Content

    @ViewBuilder
    private var activeContent: some View {
        if typeDebts.isEmpty {
            Section {
                AppEmptyStateView(
                    isSearching ? "common.noResults".localized : (type == .iOwe ? "debt.noActiveDebts".localized : "debt.noActiveLoans".localized),
                    systemImage: isSearching ? "magnifyingglass" : (type == .iOwe ? "arrow.up.right.circle" : "arrow.down.left.circle"),
                    description: isSearching ? "debt.searchPrompt".localized : (type == .iOwe ? "debt.noActiveDebtsDescription".localized : "debt.noActiveLoansDescription".localized)
                )
                .padding(.vertical, 32)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            // Hero card for active segment
            Section {
                heroCard
            }

            if !overdueDebts.isEmpty {
                Section {
                    ForEach(overdueDebts) { debt in
                        debtLink(debt)
                    }
                } header: {
                    Label("debt.overdueSection".localized, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            if overdueDebts.isEmpty && activeDebts.isEmpty {
                if !isSearching {
                    Section {
                        allSettledCelebrationCard
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if !activeDebts.isEmpty {
                Section {
                    ForEach(activeDebts) { debt in
                        debtLink(debt)
                    }
                } header: {
                    Text("debt.activeSection".localized)
                }
            }
        }
    }

    // MARK: - Completed Content

    @ViewBuilder
    private var completedContent: some View {
        if completedDebts.isEmpty {
            Section {
                AppEmptyStateView(
                    isSearching ? "common.noResults".localized : (type == .iOwe ? "debt.noSettledDebts".localized : "debt.noSettledLoans".localized),
                    systemImage: isSearching ? "magnifyingglass" : "checkmark.seal",
                    description: isSearching ? "debt.searchPrompt".localized : (type == .iOwe ? "debt.noSettledDebtsDescription".localized : "debt.noSettledLoansDescription".localized)
                )
                .padding(.vertical, 32)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            Section {
                ForEach(completedDebts) { debt in
                    debtLink(debt)
                }
            } header: {
                Text("debt.completedSection".localized)
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(type == .iOwe ? "debt.hero.totalDebt".localized : "debt.hero.totalLent".localized)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)

                Text(totalOutstanding.formattedAmount(for: preferredCurrency))
                    .appFont(size: 30, weight: .bold)
                    .foregroundStyle(type == .iOwe ? ThemeManager.shared.expenseColor : ThemeManager.shared.incomeColor)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            if totalPrincipal > 0 && totalPaidOrCollected > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    DebtProgressBar(progress: progress, tint: type.accentColor, height: 6)
                    HStack {
                        Text(type == .iOwe ? "debt.hero.paidSoFar".localized : "debt.hero.collectedSoFar".localized)
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(totalPaidOrCollected.formattedAmount(for: preferredCurrency))
                            .appFont(.caption2, weight: .semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var allSettledCelebrationCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 36, weight: .semibold)
                .foregroundStyle(ThemeManager.shared.incomeColor)
            Text(type == .iOwe ? "debt.hero.debtFree".localized : "debt.hero.allCollected".localized)
                .appFont(.headline, weight: .bold)
            Text(type == .iOwe ? "debt.hero.debtFreeDescription".localized : "debt.hero.allCollectedDescription".localized)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Row Link & Actions

    private func debtLink(_ debt: Debt) -> some View {
        NavigationLink {
            DebtDetailView(debt: debt)
        } label: {
            DebtRow(debt: debt)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                debtToDelete = debt
                showingDeleteAlert = true
            } label: {
                Label(L10n.Common.delete, systemImage: "trash")
            }

            Button {
                debtToEdit = debt
            } label: {
                Label(L10n.Common.edit, systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func deleteDebt(_ debt: Debt) {
        SoftDeleteService.deleteDebt(debt)
        do {
            try modelContext.save()
        } catch {
            ErrorService.shared.handlePersistenceError(error, context: "DebtDedicatedListView.deleteDebt")
        }
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }

    private func linkedTransactionCount(_ debt: Debt) -> Int {
        (debt.transactions ?? []).filter { $0.deletedAt == nil }.count
    }
}

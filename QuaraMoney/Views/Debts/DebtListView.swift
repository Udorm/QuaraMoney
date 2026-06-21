import SwiftUI
import SwiftData

struct DebtListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Debt.dateCreated, order: .reverse) private var allDebts: [Debt]

    @State private var viewModel = DebtListViewModel()

    @State private var showAddDebtSheet = false
    @State private var debtToEdit: Debt?
    @State private var debtToDelete: Debt?
    @State private var showingDeleteAlert = false

    private var preferredCurrency: String { CurrencyManager.shared.preferredCurrencyCode }

    private var activeDebts: [Debt] { viewModel.activeDebts(allDebts) }
    private var completedDebts: [Debt] { viewModel.completedDebts(allDebts) }
    private var hasAnyDebts: Bool { !allDebts.isEmpty }

    var body: some View {
        Group {
            if !hasAnyDebts {
                emptyState
            } else {
                List {
                    Section {
                        heroContent
                    }

                    Section {
                        typeFilter
                    }

                    if activeDebts.isEmpty {
                        Section {
                            allSettledRow
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } else {
                        Section {
                            ForEach(activeDebts) { debt in
                                debtLink(debt)
                            }
                        } header: {
                            Text("debt.activeSection".localized)
                        }
                    }

                    if viewModel.showCompleted && !completedDebts.isEmpty {
                        Section {
                            ForEach(completedDebts) { debt in
                                debtLink(debt)
                            }
                        } header: {
                            Text("debt.completedSection".localized)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
            }
        }
        .navigationTitle(L10n.Debt.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HapticManager.shared.impact(style: .light)
                    showAddDebtSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L10n.Debt.add)
            }

            if !completedDebts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $viewModel.showCompleted) {
                            Label("debt.completedSection".localized, systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: viewModel.showCompleted ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("debt.completedSection".localized)
                }
            }
        }
        .sheet(isPresented: $showAddDebtSheet) {
            AddDebtView()
        }
        .sheet(item: $debtToEdit) { debt in
            AddDebtView(debtToEdit: debt)
        }
        .alert(L10n.Common.delete, isPresented: $showingDeleteAlert, presenting: debtToDelete) { debt in
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.delete, role: .destructive) {
                viewModel.deleteDebt(debt, context: modelContext)
            }
        } message: { debt in
            Text(L10n.Debt.deleteRelatedTransactionsWarning(viewModel.linkedTransactionCount(debt)))
        }
        .onAppear { normalizeCompletionStates() }
        .onChange(of: allDebts.count) { _, _ in normalizeCompletionStates() }
    }

    // MARK: - Hero summary

    private var heroContent: some View {
        let owed = viewModel.totalOwedToMe(allDebts)
        let owe = viewModel.totalIOwe(allDebts)
        let net = owed - owe

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("debt.netPosition".localized)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)

                Text(abs(net).formattedAmount(for: preferredCurrency))
                    .appFont(size: 30, weight: .bold)
                    .foregroundStyle(net == 0 ? Color.primary : (net > 0 ? Color.green : Color.red))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(netCaption(net))
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
            }

            divergingBar(owed: owed, owe: owe)

            HStack(spacing: 0) {
                heroStat(title: "debt.youAreOwed".localized, amount: owed, color: .green, icon: "arrow.down.left")
                Divider().frame(height: 32)
                heroStat(title: "debt.youOwe".localized, amount: owe, color: .red, icon: "arrow.up.right")
            }
        }
        .padding(.vertical, 2)
    }

    private func netCaption(_ net: Decimal) -> String {
        if net > 0 { return "debt.youAreOwed".localized }
        if net < 0 { return "debt.youOwe".localized }
        return "debt.allSettled".localized
    }

    private func divergingBar(owed: Decimal, owe: Decimal) -> some View {
        let total = owed + owe
        let owedFraction: Double = total > 0
            ? NSDecimalNumber(decimal: owed / total).doubleValue
            : 0.5
        return GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule()
                    .fill(Color.green.gradient)
                    .frame(width: max(0, owedFraction) * (geo.size.width - 2))
                Capsule()
                    .fill(Color.red.gradient)
            }
        }
        .frame(height: 8)
        .opacity(total > 0 ? 1 : 0.25)
    }

    private func heroStat(title: String, amount: Decimal, color: Color, icon: String) -> some View {
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
        .padding(.leading, title == "debt.youOwe".localized ? 16 : 0)
    }

    // MARK: - Filter

    private var typeFilter: some View {
        Picker("Filter", selection: $viewModel.selectedType) {
            Text("debt.filterAll".localized).tag(Optional<DebtType>.none)
            Text(L10n.Debt.owedToMe).tag(Optional(DebtType.owedToMe))
            Text(L10n.Debt.iOwe).tag(Optional(DebtType.iOwe))
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Rows

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

    private var allSettledRow: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .appFont(size: 32, weight: .semibold)
                .foregroundStyle(.green)
            Text("debt.allSettled".localized)
                .appFont(.headline)
            Text("debt.allSettledDescription".localized)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("debt.noDebts".localized, systemImage: "person.2.badge.gearshape")
        } description: {
            Text("debt.noDebtsDescription".localized)
        } actions: {
            Button {
                showAddDebtSheet = true
            } label: {
                Text(L10n.Debt.add)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Completion normalization

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
                ErrorService.shared.handlePersistenceError(error, context: "DebtListView.normalizeCompletionStates")
            }
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        }
    }
}

// MARK: - Debt Row

struct DebtRow: View {
    let debt: Debt

    private var isPartiallyPaid: Bool {
        !debt.isCompleted && debt.amountPaid > 0 && debt.progress < 1
    }

    var body: some View {
        HStack(spacing: 12) {
            DebtAvatar(name: debt.personName, type: debt.type)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(debt.personName)
                        .appFont(.body, weight: .semibold)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(debt.displayRemaining.formattedAmount(for: debt.currencyCode))
                        .appFont(.body, weight: .bold)
                        .foregroundStyle(debt.isCompleted ? .secondary : debt.type.accentColor)
                        .lineLimit(1)
                }

                if isPartiallyPaid {
                    DebtProgressBar(progress: debt.progress, tint: debt.type.accentColor, height: 6)
                }

                HStack(spacing: 8) {
                    DebtDueChip(debt: debt)
                    Spacer(minLength: 8)
                    if isPartiallyPaid {
                        Text("debt.paidOfTotal".localized(
                            with: debt.amountPaid.formattedAmount(for: debt.currencyCode),
                            debt.currentTotalAmount.formattedAmount(for: debt.currencyCode)
                        ))
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else if let note = debt.note, !note.isEmpty {
                        Text(note)
                            .appFont(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(debt.personName), \(debt.type.relationshipPhrase) \(debt.remainingAmount.formattedAmount(for: debt.currencyCode))\(debt.isCompleted ? ", \("debt.settled".localized)" : "")")
    }
}

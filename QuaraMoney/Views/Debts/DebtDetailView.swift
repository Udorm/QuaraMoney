import SwiftUI
import SwiftData

struct DebtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var debt: Debt

    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]

    @State private var paymentContext: DebtPaymentContext?
    @State private var showEditSheet = false
    @State private var transactionToEdit: Transaction?
    @State private var statusErrorMessage: String?
    @State private var showStatusError = false
    @State private var blockedDeletionMessage: String?
    @State private var sortOption: TransactionSortOption = .newestFirst

    private let completionTolerance: Decimal = 0.000001

    private var hasRemainingBalance: Bool {
        debt.remainingAmount > completionTolerance
    }

    private var debtTransactions: [Transaction] {
        let list = (debt.transactions ?? []).filter { $0.deletedAt == nil }
        let preferredCurrency = CurrencyManager.shared.preferredCurrencyCode
        let rates = CurrencyManager.shared.rates

        switch sortOption {
        case .newestFirst:
            return list.sorted { $0.date > $1.date }
        case .oldestFirst:
            return list.sorted { $0.date < $1.date }
        case .highestAmount:
            return list.sorted { t1, t2 in
                let a1 = CurrencyManager.convert(amount: t1.amount, from: t1.currencyCode, to: preferredCurrency, rates: rates)
                let a2 = CurrencyManager.convert(amount: t2.amount, from: t2.currencyCode, to: preferredCurrency, rates: rates)
                return a1 == a2 ? t1.date > t2.date : a1 > a2
            }
        case .lowestAmount:
            return list.sorted { t1, t2 in
                let a1 = CurrencyManager.convert(amount: t1.amount, from: t1.currencyCode, to: preferredCurrency, rates: rates)
                let a2 = CurrencyManager.convert(amount: t2.amount, from: t2.currencyCode, to: preferredCurrency, rates: rates)
                return a1 == a2 ? t1.date > t2.date : a1 < a2
            }
        }
    }

    var body: some View {
        List {
            Section {
                heroContent
            }

            if let note = debt.note, !note.isEmpty {
                Section(L10n.Transaction.note) {
                    Text(note)
                        .appFont(.body)
                }
            }

            if debtTransactions.isEmpty {
                Section(L10n.Debt.history) {
                    Text("debt.noTransactions".localized)
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                TransactionListView(
                    transactions: debtTransactions,
                    sortOption: sortOption,
                    listHeader: L10n.Debt.history,
                    onEdit: { transactionToEdit = $0 },
                    onDelete: { deleteTransaction($0) }
                )
            }

            if debt.isCompleted && hasRemainingBalance {
                Section {
                    Button {
                        setActive()
                    } label: {
                        Label("debt.markActive".localized, systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.orange)
                }
            } else if !debt.isCompleted && !hasRemainingBalance {
                Section {
                    Button {
                        setCompleted()
                    } label: {
                        Label(L10n.Debt.markCompleted, systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(debt.personName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if hasRemainingBalance {
                Button {
                    HapticManager.shared.impact(style: .light)
                    startPayment()
                } label: {
                    Label(L10n.Debt.recordPayment, systemImage: "plus.circle.fill")
                        .appFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label(L10n.Common.edit, systemImage: "pencil")
                    }

                    Picker(L10n.Sort.title, selection: $sortOption) {
                        ForEach(TransactionSortOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $paymentContext) { ctx in
            // Recording a payment reuses the full transaction editor (amount,
            // currency, wallet, date/time, location, note, exclude) preconfigured
            // for this debt's repayment. Item-based so the resolved category/wallet
            // are bound to the presentation (no stale-state race).
            AddTransactionContainer(
                isNewTransaction: true,
                initialWallet: ctx.wallet,
                initialDebt: ctx.debt,
                initialCategory: ctx.category
            )
        }
        .sheet(isPresented: $showEditSheet) {
            AddDebtView(debtToEdit: debt)
        }
        .sheet(item: $transactionToEdit) { txn in
            AddTransactionContainer(transaction: txn, isNewTransaction: false, initialWallet: txn.sourceWallet)
        }
        .alert(L10n.Common.error, isPresented: $showStatusError) {
            Button(L10n.Common.ok, role: .cancel) { }
        } message: {
            Text(statusErrorMessage ?? "Failed to update debt status.".localized)
        }
        .debtDeletionBlockedAlert($blockedDeletionMessage)
        .onAppear { syncStatusIfNeeded() }
    }

    // MARK: - Hero

    private var heroContent: some View {
        let total = debt.currentTotalAmount
        let accent = debt.type.accentColor

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DebtAvatar(name: debt.personName, type: debt.type, size: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(debt.personName)
                        .appFont(.headline, weight: .bold)
                        .lineLimit(1)
                    typeBadge
                }

                Spacer(minLength: 8)

                statusBadge
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(debt.isCompleted ? "debt.settled".localized : L10n.Debt.remaining)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(debt.displayRemaining.formattedAmount(for: debt.currencyCode))
                    .appFont(size: 30, weight: .bold)
                    .foregroundStyle(debt.isCompleted ? .green : accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            if total > 0 {
                VStack(spacing: 6) {
                    DebtProgressBar(progress: debt.progress, tint: debt.isCompleted ? .green : accent, height: 8)
                    HStack {
                        Text("\(L10n.Debt.paid) \(debt.amountPaid.formattedAmount(for: debt.currencyCode))")
                        Spacer()
                        Text("\(L10n.Debt.total) \(total.formattedAmount(for: debt.currencyCode))")
                    }
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            DebtDueChip(debt: debt)
        }
        .padding(.vertical, 2)
    }

    private var typeBadge: some View {
        Text(debt.type.localizedTitle)
            .appFont(.caption2, weight: .semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(debt.type.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(debt.type.accentColor)
    }

    private var statusBadge: some View {
        let settled = debt.isCompleted
        return Text(settled ? "debt.settled".localized : "debt.activeSection".localized)
            .appFont(.caption2, weight: .semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((settled ? Color.green : Color.secondary).opacity(0.15), in: Capsule())
            .foregroundStyle(settled ? .green : .secondary)
    }

    // MARK: - Actions

    private func deleteTransaction(_ transaction: Transaction) {
        // The advance that anchors this debt can't be deleted from the history —
        // removing it would orphan the debt. Delete the whole debt instead.
        if transaction.isDebtAnchor {
            blockedDeletionMessage = "debt.cannotDeleteAnchor".localized(with: debt.personName)
            HapticManager.shared.warning()
            return
        }

        SoftDeleteService.deleteTransaction(transaction)

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            syncStatusIfNeeded()
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }

    private func syncStatusIfNeeded() {
        do {
            try DebtService(modelContext: modelContext).syncCompletionStatus(for: debt)
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }

    private func setCompleted() {
        do {
            try DebtService(modelContext: modelContext).setCompletion(for: debt, isCompleted: true)
            HapticManager.shared.notification(type: .success)
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }

    private func setActive() {
        do {
            try DebtService(modelContext: modelContext).setCompletion(for: debt, isCompleted: false)
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }

    /// Prepares and presents the shared transaction editor for a repayment:
    /// ensures the managed repayment category exists and picks a default wallet
    /// (preferring one in the debt's currency). Resolved up front and carried in
    /// the sheet item so the editor always receives the correct category.
    private func startPayment() {
        let category = try? DebtService(modelContext: modelContext).repaymentCategory(for: debt)
        let wallet = wallets.first(where: { $0.currencyCode == debt.currencyCode }) ?? wallets.first
        paymentContext = DebtPaymentContext(debt: debt, category: category, wallet: wallet)
    }
}

/// Carries the resolved repayment context to the item-based payment sheet.
private struct DebtPaymentContext: Identifiable {
    let id = UUID()
    let debt: Debt
    let category: Category?
    let wallet: Wallet?
}

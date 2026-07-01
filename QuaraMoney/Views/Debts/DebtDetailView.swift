import SwiftUI
import SwiftData

struct DebtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var debt: Debt

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
                paymentBar
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
                initialCategory: ctx.category,
                initialAmount: ctx.amount
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

    // MARK: - Payment bar

    /// Bottom action bar: quick partial-amount presets and a one-tap "settle in
    /// full" primary, with a path into the full editor for a custom amount. Each
    /// preset opens the editor pre-filled so recording a repayment is one tap.
    private var paymentBar: some View {
        let remaining = debt.displayRemaining
        let accent = debt.type.accentColor
        let showPartials = roundedPreset(remaining, fraction: 0.25) > 0
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                if showPartials {
                    quickAmountChip(fraction: 0.25, label: "¼", remaining: remaining, accent: accent)
                    quickAmountChip(fraction: 0.5, label: "½", remaining: remaining, accent: accent)
                }
                customAmountChip
            }

            Button {
                HapticManager.shared.impact(style: .light)
                startPayment(amount: remaining)
            } label: {
                Label(
                    "\("debt.settleInFull".localized) · \(remaining.formattedAmount(for: debt.currencyCode))",
                    systemImage: "checkmark.circle.fill"
                )
                .appFont(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func quickAmountChip(fraction: Double, label: String, remaining: Decimal, accent: Color) -> some View {
        let amount = roundedPreset(remaining, fraction: fraction)
        return Button {
            HapticManager.shared.selection()
            startPayment(amount: amount)
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .appFont(.subheadline, weight: .semibold)
                Text(amount.formattedAmount(for: debt.currencyCode))
                    .appFont(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("debt.quickPayHint".localized(with: label))
    }

    private var customAmountChip: some View {
        Button {
            HapticManager.shared.impact(style: .light)
            startPayment(amount: 0)   // 0 → editor opens blank for a typed amount
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "square.and.pencil")
                    .appFont(.subheadline, weight: .semibold)
                Text("debt.customAmount".localized)
                    .appFont(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    /// Rounds a fraction of the remaining balance to 2 decimal places so presets
    /// read as clean amounts (e.g. $25.00, not $24.9975).
    private func roundedPreset(_ remaining: Decimal, fraction: Double) -> Decimal {
        var raw = remaining * Decimal(fraction)
        var result = Decimal()
        NSDecimalRound(&result, &raw, 2, .plain)
        return result
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
    private func startPayment(amount: Decimal?) {
        let category = try? DebtService(modelContext: modelContext).repaymentCategory(for: debt)
        // Fetch wallets lazily here (only when a payment is actually started)
        // rather than via an eager `@Query`. A compound `@Query` predicate
        // (`!isArchived && deletedAt == nil`) evaluated while this view is being
        // pushed from a NavigationLink hangs SwiftData and freezes the app, so we
        // use a single-condition fetch and filter `isArchived` in memory.
        let wallets = (try? modelContext.fetch(
            FetchDescriptor<Wallet>(
                predicate: #Predicate<Wallet> { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\Wallet.name)]
            )
        ))?.filter { !$0.isArchived } ?? []
        let wallet = wallets.first(where: { $0.currencyCode == debt.currencyCode }) ?? wallets.first
        paymentContext = DebtPaymentContext(debt: debt, category: category, wallet: wallet, amount: amount)
    }
}

/// Carries the resolved repayment context to the item-based payment sheet.
private struct DebtPaymentContext: Identifiable {
    let id = UUID()
    let debt: Debt
    let category: Category?
    let wallet: Wallet?
    /// Pre-fill amount for the editor: a preset amount, or 0 for a blank/custom
    /// entry. `nil` falls back to the debt's full remaining balance.
    let amount: Decimal?
}

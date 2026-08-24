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
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            if !debt.isCompleted || hasRemainingBalance {
                Section {
                    quickActionsRow
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section(L10n.Debt.history) {
                if debtTransactions.isEmpty {
                    Text("debt.noTransactions".localized)
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(debtTransactions) { txn in
                        Button {
                            transactionToEdit = txn
                        } label: {
                            DebtTransactionRow(transaction: txn)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(L10n.Common.delete, role: .destructive) {
                                deleteTransaction(txn)
                            }

                            Button(L10n.Common.edit) {
                                transactionToEdit = txn
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .navigationTitle(debt.personName)
        .navigationBarTitleDisplayMode(.inline)
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
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(item: $paymentContext) { ctx in
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

    // MARK: - Hero Content

    private var heroContent: some View {
        let total = debt.currentTotalAmount
        let accent = debt.type.accentColor

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DebtAvatar(name: debt.personName, type: debt.type, isCompleted: debt.isCompleted, size: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(debt.personName)
                        .appFont(.headline, weight: .bold)
                        .lineLimit(1)
                    typeBadge
                }

                Spacer(minLength: 8)

                statusBadge
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(debt.isCompleted ? L10n.Debt.total : L10n.Debt.remaining)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Text(debt.isCompleted
                    ? debt.currentTotalAmount.formattedAmount(for: debt.currencyCode)
                    : debt.displayRemaining.formattedAmount(for: debt.currencyCode))
                    .appFont(size: 30, weight: .bold)
                    .foregroundStyle(debt.isCompleted ? .primary : accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            if !debt.isCompleted && total > 0 {
                VStack(spacing: 6) {
                    DebtProgressBar(progress: debt.progress, tint: accent, height: 8)
                    HStack {
                        Text("\(L10n.Debt.paid) \(debt.amountPaid.formattedAmount(for: debt.currencyCode))")
                        Spacer()
                        Text("\(L10n.Debt.total) \(total.formattedAmount(for: debt.currencyCode))")
                    }
                    .appFont(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            // Dates metadata (Borrow/Lent date & Due date)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .appFont(size: 11, weight: .semibold)
                    Text(borrowOrLentDateLabel)
                        .appFont(.caption2, weight: .medium)
                }
                .foregroundStyle(.secondary)

                if let due = debt.dueDate {
                    Text("•")
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .appFont(size: 11, weight: .semibold)
                        Text("\("debt.due".localized) \(due.appFormatted(date: .abbreviated, time: .omitted))")
                            .appFont(.caption2, weight: .medium)
                    }
                    .foregroundStyle(debt.isOverdue && !debt.isCompleted ? .red : .secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var borrowOrLentDate: Date {
        debt.principalTransaction?.date ?? debt.dateCreated
    }

    private var borrowOrLentDateLabel: String {
        let dateString = borrowOrLentDate.appFormatted(date: .abbreviated, time: .omitted)
        if debt.type == .iOwe {
            return "debt.detail.borrowedOn".localized(with: dateString)
        } else {
            return "debt.detail.lentOn".localized(with: dateString)
        }
    }

    // MARK: - Quick Actions Row (Matching Wallet Detail style)

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            if !debt.isCompleted {
                quickActionButton(
                    icon: debt.type == .iOwe ? "arrow.up.right" : "arrow.down.left",
                    title: "debt.recordPayment".localized,
                    color: debt.type.accentColor
                ) {
                    startPayment(amount: 0)
                }

                quickActionButton(
                    icon: "checkmark.circle.fill",
                    title: "debt.settleInFull".localized,
                    color: ThemeManager.shared.incomeColor
                ) {
                    startPayment(amount: debt.displayRemaining)
                }
            } else if hasRemainingBalance {
                quickActionButton(
                    icon: "arrow.uturn.backward",
                    title: "debt.markActive".localized,
                    color: .orange
                ) {
                    setActive()
                }
            }
        }
    }

    private func quickActionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.shared.impact(style: .light)
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .appFont(.footnote, weight: .semibold)
                Text(title)
                    .appFont(.footnote, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(Capsule())
            .background(color, in: Capsule())
        }
        .buttonStyle(DebtQuickActionPressStyle())
    }

    // MARK: - Badges

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
            .background((settled ? ThemeManager.shared.incomeColor : Color.secondary).opacity(0.15), in: Capsule())
            .foregroundStyle(settled ? ThemeManager.shared.incomeColor : .secondary)
    }

    // MARK: - Actions & Persistence

    private func deleteTransaction(_ transaction: Transaction) {
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

    private func setActive() {
        do {
            try DebtService(modelContext: modelContext).setCompletion(for: debt, isCompleted: false)
        } catch {
            statusErrorMessage = error.localizedDescription
            showStatusError = true
        }
    }

    private func startPayment(amount: Decimal?) {
        let category = try? DebtService(modelContext: modelContext).repaymentCategory(for: debt)
        let wallets = (try? modelContext.fetch(
            FetchDescriptor<Wallet>(
                predicate: #Predicate<Wallet> { $0.deletedAt == nil },
                sortBy: [SortDescriptor(\Wallet.name)]
            )
        ))?.filter { !$0.isArchived && !$0.isSavings } ?? []
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
    let amount: Decimal?
}

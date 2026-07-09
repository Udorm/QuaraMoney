import SwiftUI
import SwiftData

/// The confirm-before-post inbox: every rule with an occurrence due today or
/// earlier. The user posts (creates the ledger transaction) or skips each, or
/// batches all of them.
struct RecurringReviewView: View {
    @Environment(\.modelContext) private var modelContext

    // Live source of truth: re-evaluated as rules are posted/skipped, so a rule
    // drops out the instant it's no longer due (no stale snapshot to over-post).
    // Uses the same simple predicate as the list view (a compound `isActive &&
    // deletedAt == nil` #Predicate hangs SwiftData here); `isActive`/`isDue`
    // filtering is done in memory — exactly where `isDue` already lives.
    let allRules: [RecurringRule]
    private var dueRules: [RecurringRule] { allRules.filter { RecurringRuleService.isDue($0) } }

    /// Aggregate of everything currently waiting in the inbox — the count of
    /// pending occurrences (not rules) plus expense/income totals converted to
    /// the preferred currency. Drives the summary header and confirmation
    /// dialogs so the user sees the scale of a batch before committing.
    private struct ReviewTotals {
        var occurrences: Int
        var expense: Decimal
        var income: Decimal
        var currency: String
    }

    private var totals: ReviewTotals {
        let manager = CurrencyManager.shared
        let target = manager.preferredCurrencyCode
        var occ = 0
        var exp: Decimal = 0
        var inc: Decimal = 0
        for rule in dueRules {
            let n = RecurringRuleService.pendingOccurrenceCount(for: rule)
            occ += n
            // Post All creates one transaction per pending occurrence, so the
            // total must scale by `n`, not count the rule once.
            let converted = manager.convert(amount: rule.amount, from: rule.currencyCode, to: target) * Decimal(n)
            if rule.type == .expense { exp += converted } else { inc += converted }
        }
        return ReviewTotals(occurrences: occ, expense: exp, income: inc, currency: target)
    }

    @State private var editingRule: RecurringRule?
    @State private var confirmPostAll = false
    @State private var confirmSkipAll = false
    @State private var lastMutation: RecurringMutation?

    var body: some View {
        Group {
            if dueRules.isEmpty {
                AppEmptyStateView(
                    L10n.Recurring.Review.empty,
                    systemImage: "checkmark.circle"
                )
            } else {
                List {
                    Section {
                        summaryHeader
                            .listRowSeparator(.hidden)
                    }
                    ForEach(dueRules) { rule in
                        RecurringDueRow(
                            rule: rule,
                            onPost: {
                                let mutation = RecurringRuleService.post(rule: rule, in: modelContext)
                                lastMutation = mutation
                                HapticManager.shared.notification(type: mutation == nil ? .error : .success)
                            },
                            onSkip: { lastMutation = RecurringRuleService.skip(rule: rule, in: modelContext) },
                            onEdit: { editingRule = rule }
                        )
                    }
                }
            }
        }
        .navigationTitle(L10n.Recurring.Review.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !dueRules.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(L10n.Recurring.Review.postAll, systemImage: "tray.and.arrow.down") {
                            confirmPostAll = true
                        }
                        Button(L10n.Recurring.Review.skipAll, systemImage: "forward.end", role: .destructive) {
                            confirmSkipAll = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(L10n.Recurring.Review.postAll, isPresented: $confirmPostAll, titleVisibility: .visible) {
            Button(L10n.Recurring.Review.postAll) { postAll() }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Recurring.Review.postAllMessage(totals.occurrences))
        }
        .confirmationDialog(L10n.Recurring.Review.skipAll, isPresented: $confirmSkipAll, titleVisibility: .visible) {
            Button(L10n.Recurring.Review.skipAll, role: .destructive) { skipAll() }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Recurring.Review.skipAllMessage(totals.occurrences))
        }
        .sheet(item: $editingRule) { rule in
            RecurringPostEditorView(rule: rule)
        }
        .undoToast($lastMutation, message: { $0.undoSummary }) { mutation in
            RecurringRuleService.undo(mutation, in: modelContext)
        }
    }

    /// At-a-glance batch summary: how many occurrences are waiting and what
    /// posting them all nets, so the scale of "Post All" is visible up front.
    private var summaryHeader: some View {
        let t = totals
        return HStack(alignment: .firstTextBaseline) {
            Text(L10n.Recurring.Review.summary(t.occurrences))
                .font(.app(.headline))
            Spacer()
            HStack(spacing: 10) {
                if t.expense > 0 {
                    Text("-" + t.expense.formattedAmount(for: t.currency))
                        .foregroundStyle(.primary)
                }
                if t.income > 0 {
                    Text("+" + t.income.formattedAmount(for: t.currency))
                        .foregroundStyle(.green)
                }
            }
            .font(.app(.subheadline, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func postAll() {
        for rule in dueRules { RecurringRuleService.postAllDue(rule: rule, in: modelContext) }
        HapticManager.shared.notification(type: .success)
    }

    private func skipAll() {
        for rule in dueRules { RecurringRuleService.skipAllDue(rule: rule, in: modelContext) }
    }
}

/// One due occurrence: summary (with destination wallet/category) + inline
/// Edit / Skip / Post. Shared by the review inbox and the rule-detail screen.
/// `onEdit` is optional; when supplied a visible "Edit" button is shown so the
/// amount/date can be adjusted before posting without hunting for a swipe.
struct RecurringDueRow: View {
    let rule: RecurringRule
    let onPost: () -> Void
    let onSkip: () -> Void
    var onEdit: (() -> Void)? = nil

    private var pendingCount: Int { RecurringRuleService.pendingOccurrenceCount(for: rule) }

    private var dueLabel: String {
        let isOverdue = rule.nextDueDate < Calendar.current.startOfDay(for: Date())
        let base = isOverdue ? L10n.Recurring.overdue : L10n.Recurring.dueToday
        return pendingCount > 1 ? "\(base) · \(L10n.Recurring.dueCount(pendingCount))" : base
    }

    private var signedAmount: String {
        let formatted = rule.amount.formattedAmount(for: rule.currencyCode)
        return rule.type == .income ? "+\(formatted)" : formatted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: rule.category?.icon ?? (rule.type == .income ? "arrow.down.left" : "arrow.up.right"))
                    .foregroundStyle(rule.type == .income ? .green : .red)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name).font(.app(.headline))
                    Text(dueLabel).font(.app(.caption)).foregroundStyle(.secondary)
                    metaChips
                }
                Spacer()
                Text(signedAmount)
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(rule.type == .income ? Color.green : Color.primary)
            }
            HStack(spacing: 8) {
                if let onEdit {
                    Button(action: onEdit) {
                        Label(L10n.Common.edit, systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                    .font(.app(.subheadline))
                }
                Spacer(minLength: 16)
                // Skip recedes (gray) — it silently drops the occurrence, so it
                // must not compete visually with Post. Extra spacing keeps it
                // from sitting flush against the primary action.
                Button(L10n.Recurring.skip, action: onSkip)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                Button(L10n.Recurring.post, action: onPost)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    /// Small pills surfacing where this occurrence posts — the destination
    /// wallet (and category). A missing wallet is flagged so the user
    /// understands why Post would fail.
    @ViewBuilder
    private var metaChips: some View {
        HStack(spacing: 6) {
            if let wallet = rule.wallet {
                chip(icon: "wallet.pass.fill", text: wallet.name, tint: .secondary)
            } else {
                chip(icon: "exclamationmark.triangle.fill", text: "recurring.noWallet".localized, tint: .orange)
            }
            if let category = rule.category {
                chip(icon: category.icon, text: category.displayName, tint: .secondary)
            }
        }
    }

    private func chip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .font(.app(.caption2))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Adjust the amount/date of a single due occurrence before posting it.
struct RecurringPostEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let rule: RecurringRule

    @State private var amountString: String
    @State private var date: Date

    init(rule: RecurringRule) {
        self.rule = rule
        _amountString = State(initialValue: NSDecimalNumber(decimal: rule.amount).stringValue)
        _date = State(initialValue: rule.nextDueDate)
    }

    /// Parsed amount, tolerant of comma decimal separators (matches the rule
    /// editor). `nil` when the field can't be parsed, so we never silently post
    /// the rule default in place of an edited-but-invalid amount.
    private var parsedAmount: Decimal? {
        Decimal(string: amountString.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Recurring.proposed) {
                    LabeledContent(L10n.Recurring.name, value: rule.name)
                    if let wallet = rule.wallet {
                        LabeledContent(L10n.Wallet.selectWallet, value: wallet.name)
                    }
                    if let category = rule.category {
                        LabeledContent(L10n.Category.select, value: category.name)
                    }
                    HStack {
                        Text(rule.currencyCode).foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker(L10n.Transaction.date, selection: $date, displayedComponents: [.date])
                }
            }
            .navigationTitle(L10n.Recurring.editAndPost)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        RecurringRuleService.post(rule: rule, amount: parsedAmount, date: date, in: modelContext)
                        HapticManager.shared.notification(type: .success)
                        dismiss()
                    } label: { Text(L10n.Recurring.post) }
                        .buttonStyle(.borderedProminent)
                        .disabled(parsedAmount == nil)
                }
            }
        }
    }
}

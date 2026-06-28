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
    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil },
           sort: \RecurringRule.nextDueDate) private var allRules: [RecurringRule]
    private var dueRules: [RecurringRule] { allRules.filter { RecurringRuleService.isDue($0) } }

    @State private var editingRule: RecurringRule?
    @State private var confirmPostAll = false
    @State private var confirmSkipAll = false

    var body: some View {
        Group {
            if dueRules.isEmpty {
                AppEmptyStateView(
                    L10n.Recurring.Review.empty,
                    systemImage: "checkmark.circle"
                )
            } else {
                List {
                    ForEach(dueRules) { rule in
                        RecurringDueRow(
                            rule: rule,
                            onPost: {
                                let posted = RecurringRuleService.post(rule: rule, in: modelContext)
                                HapticManager.shared.notification(type: posted == nil ? .error : .success)
                            },
                            onSkip: { RecurringRuleService.skip(rule: rule, in: modelContext) }
                        )
                        .swipeActions(edge: .leading) {
                            Button { editingRule = rule } label: {
                                Label(L10n.Recurring.editAndPost, systemImage: "slider.horizontal.3")
                            }
                            .tint(.blue)
                        }
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
        }
        .confirmationDialog(L10n.Recurring.Review.skipAll, isPresented: $confirmSkipAll, titleVisibility: .visible) {
            Button(L10n.Recurring.Review.skipAll, role: .destructive) { skipAll() }
            Button(L10n.Common.cancel, role: .cancel) {}
        }
        .sheet(item: $editingRule) { rule in
            RecurringPostEditorView(rule: rule)
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

/// One due occurrence: summary + inline Post / Skip. Swipe leading → Edit & Post.
private struct RecurringDueRow: View {
    let rule: RecurringRule
    let onPost: () -> Void
    let onSkip: () -> Void

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
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.app(.headline))
                    Text(dueLabel).font(.app(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(signedAmount)
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(rule.type == .income ? Color.green : Color.primary)
            }
            HStack {
                Spacer()
                Button(L10n.Recurring.skip, action: onSkip)
                    .buttonStyle(.bordered)
                Button(L10n.Recurring.post, action: onPost)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
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

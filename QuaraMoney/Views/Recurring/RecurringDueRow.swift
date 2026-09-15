import SwiftUI
import SwiftData

/// One due occurrence: summary + inline Edit / Skip / Post. Shared by the
/// Upcoming tab (leading with a date tile) and the rule-detail screen (leading
/// with the category icon). `onEdit` is optional; when supplied a visible
/// "Edit" button is shown so the amount/date can be adjusted before posting
/// without hunting for a swipe.
struct RecurringDueRow: View {
    let rule: RecurringRule
    let onPost: () -> Void
    let onSkip: () -> Void
    var onEdit: (() -> Void)? = nil
    /// Leads with a calendar tile and names the wallet — for lists of dated
    /// payments, where the date matters more than the category.
    var showsDateTile = false

    private var pendingCount: Int { RecurringRuleService.pendingOccurrenceCount(for: rule) }

    private var isOverdue: Bool { rule.nextDueDate < Calendar.current.startOfDay(for: Date()) }

    private var dueLabel: String {
        let status = isOverdue ? L10n.Recurring.overdue : L10n.Recurring.dueToday
        let date = rule.nextDueDate.appFormatted(date: .abbreviated, time: .omitted)
        var parts = [date, status]
        if pendingCount > 1 { parts.append(L10n.Recurring.dueCount(pendingCount)) }
        return parts.joined(separator: " · ")
    }

    /// Date-tile variant: the tile already carries the date, so the line adds
    /// the wallet the payment comes from instead.
    private var tileDetail: String {
        var parts: [String] = []
        if let wallet = rule.wallet { parts.append(wallet.name) }
        if pendingCount > 1 { parts.append(L10n.Recurring.dueCount(pendingCount)) }
        return parts.joined(separator: " · ")
    }

    private var signedAmount: String {
        let formatted = rule.amount.formattedAmount(for: rule.currencyCode)
        return rule.type == .income ? "+\(formatted)" : formatted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: showsDateTile ? 14 : 12) {
                lead
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name).appFont(.headline)
                    if showsDateTile {
                        HStack(spacing: 5) {
                            Text(isOverdue ? L10n.Recurring.overdue : L10n.Recurring.dueToday)
                                .foregroundStyle(isOverdue ? Color.red : Color.orange)
                            if !tileDetail.isEmpty {
                                Text("·").foregroundStyle(.tertiary)
                                Text(tileDetail).foregroundStyle(.secondary)
                            }
                        }
                        .appFont(.caption)
                        .lineLimit(1)
                    } else {
                        Text(dueLabel).appFont(.caption).foregroundStyle(.secondary)
                    }
                    metaChips
                }
                Spacer()
                Text(signedAmount)
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(rule.type == .income ? Color.green : Color.primary)
            }
            HStack(spacing: 8) {
                if let onEdit {
                    Button(L10n.Common.edit, action: onEdit)
                        .buttonStyle(.bordered)
                        .tint(.secondary)
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

    @ViewBuilder
    private var lead: some View {
        if showsDateTile {
            RecurringDateTile(date: rule.nextDueDate, style: isOverdue ? .overdue : .upcoming)
        } else {
            Image(systemName: rule.category?.icon ?? (rule.type == .income ? "arrow.down.left" : "arrow.up.right"))
                .foregroundStyle(rule.type == .income ? .green : .red)
                .frame(width: 24)
        }
    }

    /// The category and destination wallet are already conveyed by the row's
    /// icon and the rule's context, so no chips are shown for them. A *missing*
    /// wallet is still flagged, since it's the reason Post would fail.
    @ViewBuilder
    private var metaChips: some View {
        if rule.wallet == nil {
            chip(icon: "exclamationmark.triangle.fill", text: "recurring.noWallet".localized, tint: .orange)
        }
    }

    private func chip(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
        }
        .appFont(.caption2)
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

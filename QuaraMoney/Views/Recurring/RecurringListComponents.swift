import SwiftUI

// MARK: - Formatting

/// Strings shared by the Recurring screen's rows, cards and headers.
enum RecurringFormat {
    /// Section header with a count, e.g. "Expenses · 5".
    static func sectionTitle(_ title: String, count: Int) -> String {
        "\(title) · \(count)"
    }

    static func ruleCount(_ count: Int) -> String {
        count == 1 ? "recurring.rulesCount.one".localized : "recurring.rulesCount".localized(with: count)
    }

    static func reviewTitle(_ count: Int) -> String {
        count == 1 ? "recurring.review.cardTitle.one".localized : "recurring.review.cardTitle".localized(with: count)
    }

    /// "Next Sep 25" — the year is only spelled out when it isn't this year.
    static func nextDate(_ date: Date, now: Date = Date()) -> String {
        let text = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
            ? AppDateFormatterCache.formatter(dateTemplate: "MMMd", locale: .app).string(from: date)
            : date.appFormatted(date: .abbreviated, time: .omitted)
        return "recurring.nextOn".localized(with: text)
    }

    static func signedAmount(_ amount: Decimal, currency: String, type: TransactionType) -> String {
        let formatted = amount.formattedAmount(for: currency)
        return type == .income ? "+\(formatted)" : formatted
    }

    /// "≈ $43.33/mo" — only when the rule's own amount doesn't already read as
    /// its monthly cost in the user's currency (non-monthly schedules, or
    /// another currency).
    static func monthlyHint(for rule: RecurringRule, currency: String) -> String? {
        guard rule.frequency != .monthly || rule.interval != 1 || rule.currencyCode != currency else { return nil }
        let monthly = RecurringRuleService.monthlyEquivalent(amount: rule.amount, frequency: rule.frequency, interval: rule.interval)
        let converted = CurrencyManager.shared.convert(amount: monthly, from: rule.currencyCode, to: currency)
        return "recurring.perMonthApprox".localized(with: converted.formattedAmount(for: currency))
    }

    /// "≈ $45.00" for an amount in a currency other than the user's.
    static func convertedHint(_ amount: Decimal, from code: String, to currency: String) -> String? {
        guard code != currency else { return nil }
        let converted = CurrencyManager.shared.convert(amount: amount, from: code, to: currency)
        return "recurring.approx".localized(with: converted.formattedAmount(for: currency))
    }
}

// MARK: - Rule row

/// One rule on the Rules tab: category icon, schedule, next payment, amount,
/// and its average monthly cost when that differs from the amount shown.
struct RecurringRuleRow: View {
    let rule: RecurringRule
    /// The user's preferred currency, for the monthly hint.
    let currency: String

    private var isLive: Bool { rule.isActive && !RecurringRuleService.hasEnded(rule) }

    private var tint: Color {
        rule.type == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var icon: String {
        rule.category?.icon ?? (rule.type == .income ? "arrow.down.left" : "arrow.up.right")
    }

    private var chipText: String? {
        if !rule.isActive {
            return rule.pauseReason == .invalidSavingsWallet
                ? "recurring.pausedForSavings".localized
                : L10n.Recurring.paused
        }
        return RecurringRuleService.hasEnded(rule) ? "recurring.ended".localized : nil
    }

    private var status: (text: String, color: Color)? {
        guard isLive else { return nil }
        let calendar = Calendar.current
        if rule.nextDueDate < calendar.startOfDay(for: Date()) {
            return (L10n.Recurring.overdue, .red)
        } else if calendar.isDateInToday(rule.nextDueDate) {
            return (L10n.Recurring.dueToday, .orange)
        }
        return (RecurringFormat.nextDate(rule.nextDueDate), .secondary)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .appFont(.body, weight: .semibold)
                .foregroundStyle(isLive ? tint : Color.secondary)
                .frame(width: 42, height: 42)
                .background(
                    (isLive ? tint : Color.secondary).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.name)
                        .appFont(.headline)
                        .lineLimit(1)
                    if let chipText {
                        RecurringStatusChip(text: chipText)
                    }
                }

                HStack(spacing: 5) {
                    Text(rule.frequency.displayName(interval: rule.interval))
                        .foregroundStyle(.secondary)
                    if let status {
                        Text("·").foregroundStyle(.tertiary)
                        Text(status.text).foregroundStyle(status.color)
                    }
                }
                .appFont(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(RecurringFormat.signedAmount(rule.amount, currency: rule.currencyCode, type: rule.type))
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(!isLive ? Color.secondary : rule.type == .income ? tint : Color.primary)
                    .lineLimit(1)
                if isLive, let hint = RecurringFormat.monthlyHint(for: rule, currency: currency) {
                    Text(hint)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecurringStatusChip: View {
    let text: String

    var body: some View {
        Text(text)
            .appFont(.caption2, weight: .bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

// MARK: - Dated payment rows

/// Calendar-style day tile (weekday over day number). It marks a row as a
/// dated payment, so it never reads as a rule.
struct RecurringDateTile: View {
    enum Style { case upcoming, overdue, done }

    let date: Date
    var style: Style = .upcoming

    private var weekday: String {
        AppDateFormatterCache.formatter(dateTemplate: "EEE", locale: .app)
            .string(from: date)
            .uppercased(with: .app)
    }

    private var day: String {
        AppDateFormatterCache.formatter(dateTemplate: "d", locale: .app).string(from: date)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(weekday)
                .appFont(.caption2, weight: .semibold)
                .foregroundStyle(style == .overdue ? Color.red : Color.secondary)
            Text(day)
                .appFont(.headline, weight: .bold)
                .foregroundStyle(style == .overdue ? Color.red : style == .done ? Color.secondary : Color.primary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: 42, height: 42)
        .background(
            style == .overdue ? Color.red.opacity(0.12) : Color(uiColor: .tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.appFormatted(date: .complete, time: .omitted))
    }
}

/// A still-scheduled payment on the Upcoming tab.
struct RecurringOccurrenceRow: View {
    let rule: RecurringRule
    let date: Date
    let currency: String

    private var detail: String {
        [rule.frequency.displayName(interval: rule.interval), rule.wallet?.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            RecurringDateTile(date: date)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .appFont(.headline)
                    .lineLimit(1)
                Text(detail)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(RecurringFormat.signedAmount(rule.amount, currency: rule.currencyCode, type: rule.type))
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(rule.type == .income ? ThemeManager.shared.incomeColor : Color.primary)
                    .lineLimit(1)
                if let hint = RecurringFormat.convertedHint(rule.amount, from: rule.currencyCode, to: currency) {
                    Text(hint)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A payment already posted this month.
struct RecurringPaidRow: View {
    let transaction: Transaction

    private var detail: String {
        ["recurring.upcoming.paid".localized, transaction.sourceWallet?.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            RecurringDateTile(date: transaction.date, style: .done)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.recurringRule?.name ?? "")
                    .appFont(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                .appFont(.caption)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(RecurringFormat.signedAmount(transaction.amount, currency: transaction.currencyCode, type: transaction.type))
                .appFont(.body, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Section header with optional signed expense/income totals on the trailing edge.
struct RecurringSectionHeader: View {
    let title: String
    var totals = RecurringMonthSummary.Totals()
    var currency = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if totals.expense > 0 || totals.income > 0 {
                HStack(spacing: 8) {
                    if totals.expense > 0 {
                        Text("-" + totals.expense.formattedAmount(for: currency))
                            .foregroundStyle(.primary)
                    }
                    if totals.income > 0 {
                        Text("+" + totals.income.formattedAmount(for: currency))
                            .foregroundStyle(.green)
                    }
                }
                .appFont(.caption, weight: .semibold)
            }
        }
    }
}

// MARK: - Cards

/// Shown on the Rules tab only while something is due. The whole card is one
/// button that switches to the Upcoming tab, where due payments are handled.
struct RecurringReviewCard: View {
    let occurrenceCount: Int
    let ruleNames: [String]
    let expense: Decimal
    let income: Decimal
    let currency: String
    let onReview: () -> Void

    private var subtitle: String {
        let names: String
        if ruleNames.count <= 2 {
            names = ruleNames.formatted(.list(type: .and).locale(.app))
        } else {
            names = "recurring.review.namesMore".localized(with: ruleNames.prefix(2).joined(separator: ", "), ruleNames.count - 2)
        }
        var parts = [names]
        if expense > 0 { parts.append("-" + expense.formattedAmount(for: currency)) }
        if income > 0 { parts.append("+" + income.formattedAmount(for: currency)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onReview) {
            HStack(spacing: 14) {
                Image(systemName: "bell.fill")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(RecurringFormat.reviewTitle(occurrenceCount))
                        .appFont(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("recurring.review.action".localized)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Rules-tab summary: how many rules exist and what the active ones cost per
/// month on average.
struct RecurringRulesSummaryCard: View {
    let ruleCount: Int
    let pausedCount: Int
    let monthlyExpense: Decimal
    let monthlyIncome: Decimal
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(RecurringFormat.ruleCount(ruleCount))
                    .appFont(.title, weight: .bold)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if pausedCount > 0 {
                    Text("recurring.pausedCount".localized(with: pausedCount))
                        .appFont(.subheadline, weight: .medium)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("recurring.averagePerMonth".localized)
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 12) {
                    stat(
                        title: L10n.Recurring.expenses,
                        value: monthlyExpense.formattedAmount(for: currency),
                        color: ThemeManager.shared.expenseColor,
                        valueColor: .primary,
                        icon: "arrow.up.right"
                    )
                    stat(
                        title: L10n.Recurring.income,
                        value: "+" + monthlyIncome.formattedAmount(for: currency),
                        color: ThemeManager.shared.incomeColor,
                        valueColor: ThemeManager.shared.incomeColor,
                        icon: "arrow.down.left"
                    )
                }
            }
        }
        .recurringCardStyle()
    }

    private func stat(title: String, value: String, color: Color, valueColor: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            RecurringCardIcon(systemImage: icon, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                Text(value)
                    .appFont(.headline, weight: .bold)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Upcoming-tab card: the displayed month with step buttons, and paid vs
/// expected progress for expenses and income.
struct RecurringMonthProgressCard: View {
    let monthStart: Date
    let paid: RecurringMonthSummary.Totals
    let expected: RecurringMonthSummary.Totals
    let currency: String
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    private var title: String {
        AppDateFormatterCache.formatter(dateTemplate: "MMMMyyyy", locale: .app).string(from: monthStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(title)
                    .appFont(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    stepButton("chevron.left", label: "recurring.upcoming.previousMonth".localized, enabled: canGoBack, action: onBack)
                    stepButton("chevron.right", label: "recurring.upcoming.nextMonth".localized, enabled: canGoForward, action: onForward)
                }
            }

            if expected.expense > 0 || expected.income > 0 {
                VStack(spacing: 18) {
                    if expected.expense > 0 {
                        progressRow(
                            title: L10n.Recurring.expenses,
                            paid: paid.expense,
                            expected: expected.expense,
                            color: ThemeManager.shared.expenseColor,
                            icon: "arrow.up.right"
                        )
                    }
                    if expected.income > 0 {
                        progressRow(
                            title: L10n.Recurring.income,
                            paid: paid.income,
                            expected: expected.income,
                            color: ThemeManager.shared.incomeColor,
                            icon: "arrow.down.left"
                        )
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark")
                        .appFont(.title3)
                        .foregroundStyle(.secondary)
                    Text("recurring.upcoming.noPayments".localized(with: title))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .recurringCardStyle()
    }

    private func stepButton(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .appFont(.footnote, weight: .bold)
                .frame(width: 36, height: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func progressRow(title: String, paid: Decimal, expected: Decimal, color: Color, icon: String) -> some View {
        let percentage = expected > 0
            ? min(1, max(0, NSDecimalNumber(decimal: paid).doubleValue / NSDecimalNumber(decimal: expected).doubleValue))
            : 0

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RecurringCardIcon(systemImage: icon, color: color)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.primary)
                    Text("\(Int((percentage * 100).rounded()))%")
                        .appFont(.caption2, weight: .medium)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                // Paid amount in tint, expected as a muted denominator.
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(paid.formattedAmount(for: currency))
                        .appFont(.callout, weight: .bold)
                        .foregroundStyle(color)
                    Text(" / \(expected.formattedAmount(for: currency))")
                        .appFont(.caption, weight: .medium)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(0, geometry.size.width * CGFloat(percentage)))
                }
            }
            .frame(height: 8)
        }
    }
}

private struct RecurringCardIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .appFont(.footnote, weight: .bold)
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))
    }
}

private extension View {
    /// Raised grouped-list card used by the Recurring screen's summary cards.
    func recurringCardStyle() -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}

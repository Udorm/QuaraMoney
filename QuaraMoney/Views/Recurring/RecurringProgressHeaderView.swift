import SwiftUI
import SwiftData

struct RecurringProgressHeaderView: View {
    @State private var viewModel: RecurringProgressViewModel

    init(modelContext: ModelContext) {
        _viewModel = State(wrappedValue: RecurringProgressViewModel(dataService: SwiftDataService(modelContext: modelContext), context: modelContext))
    }

    private var expenseColor: Color { ThemeManager.shared.expenseColor }
    private var incomeColor: Color { ThemeManager.shared.incomeColor }

    private var hasProgress: Bool {
        viewModel.expectedExpenses > 0 || viewModel.expectedIncome > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Card title with the current month for context.
            HStack {
                Text(L10n.Recurring.monthlyProgress)
                    .font(.app(.headline))
                    .foregroundStyle(.primary)
                Spacer()
                Text(Date().formatted(.dateTime.month(.wide)))
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if hasProgress {
                VStack(spacing: 18) {
                    if viewModel.expectedExpenses > 0 {
                        progressRow(
                            title: L10n.Recurring.expenses,
                            paid: viewModel.paidExpenses,
                            expected: viewModel.expectedExpenses,
                            color: expenseColor,
                            icon: "arrow.up.right"
                        )
                    }

                    if viewModel.expectedIncome > 0 {
                        progressRow(
                            title: L10n.Recurring.income,
                            paid: viewModel.receivedIncome,
                            expected: viewModel.expectedIncome,
                            color: incomeColor,
                            icon: "arrow.down.left"
                        )
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.app(.title3))
                        .foregroundStyle(.secondary)
                    Text(L10n.Recurring.noProgressThisMonth)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private func progressRow(title: String, paid: Decimal, expected: Decimal, color: Color, icon: String) -> some View {
        let currencyCode = viewModel.preferredCurrencyCode
        let percentage = expected > 0
            ? min(1, max(0, NSDecimalNumber(decimal: paid).doubleValue / NSDecimalNumber(decimal: expected).doubleValue))
            : 0

        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.app(.footnote, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(Int((percentage * 100).rounded()))%")
                        .font(.app(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                // Paid amount in tint, expected as a muted denominator.
                (
                    Text(paid.formattedAmount(for: currencyCode))
                        .font(.app(.callout, weight: .bold))
                        .foregroundColor(color)
                    + Text(" / \(expected.formattedAmount(for: currencyCode))")
                        .font(.app(.caption, weight: .medium))
                        .foregroundColor(.secondary)
                )
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

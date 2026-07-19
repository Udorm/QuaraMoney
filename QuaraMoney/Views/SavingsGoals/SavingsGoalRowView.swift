import SwiftUI

struct SavingsGoalRowView: View {
    let goal: SavingsGoal
    let metrics: SavingsGoalMetrics

    private var color: Color { Color(hex: goal.colorHex) ?? .green }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlanIconTile(systemImage: goal.iconName, color: color)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(goal.name)
                        .appFont(.body, weight: .semibold)
                        .lineLimit(1)

                    if metrics.isCompleted == true {
                        Image(systemName: "checkmark.circle.fill")
                            .appFont(.caption)
                            .foregroundStyle(.green)
                    } else if metrics.isBehind == true {
                        Text("savings.behind".localized)
                            .appFont(.caption2, weight: .semibold)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 4)
                    if metrics.isDeterminate {
                        Text(PlanDisplayFormatting.percent(metrics.progress))
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(color)
                            .monospacedDigit()
                    }
                }

                if let targetDate = goal.targetDate {
                    Text("plan.target_date_value".localized(
                        with: targetDate.appFormatted(date: .abbreviated, time: .omitted)
                    ))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("savings.status.noDate".localized)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }

                if metrics.isDeterminate {
                    Text("plan.saved_of".localized(
                        with: metrics.saved.formattedAmount(for: goal.currencyCode),
                        goal.targetAmount.formattedAmount(for: goal.currencyCode)
                    ))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    PlanProgressBar(progress: metrics.progress, color: color)
                } else {
                    Text(metrics.saved.formattedAmount(for: goal.currencyCode))
                        .appFont(.caption, weight: .medium)
                        .monospacedDigit()
                    PlanPartialDataLabel()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let goal = SavingsGoal(name: "Emergency Fund", targetAmount: 10_000, currencyCode: "USD")
    SavingsGoalRowView(
        goal: goal,
        metrics: SavingsGoalMetrics(
            saved: 4_250,
            remaining: 5_750,
            progress: Decimal(string: "0.425")!,
            monthlyTarget: 575,
            isCompleted: false,
            isBehind: true,
            isDeterminate: true
        )
    )
    .padding()
}

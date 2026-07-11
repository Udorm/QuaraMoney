import SwiftUI

struct SavingsGoalRowView: View {
    let goal: SavingsGoal

    private var goalColor: Color {
        Color(hex: goal.colorHex) ?? .blue
    }

    var body: some View {
        HStack(spacing: 14) {
            // MARK: Icon
            ZStack {
                Circle()
                    .fill(goalColor.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: goal.iconName)
                    .font(.app(.title3))
                    .foregroundStyle(goalColor)
            }

            // MARK: Content
            VStack(alignment: .leading, spacing: 6) {
                // Title + status badge
                HStack(spacing: 6) {
                    Text(goal.name)
                        .font(.app(.body, weight: .semibold))
                        .lineLimit(1)

                    if goal.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.app(.caption))
                    } else if !goal.isOnTrack(converter: CurrencyManager.shared.convert) {
                        Text("savings.behind".localized)
                            .font(.app(.caption2, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                // Progress Bar with gradient fill
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [goalColor, goalColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * CGFloat(min(goal.progress(converter: CurrencyManager.shared.convert), 1.0)),
                                height: 6
                            )
                            .animation(.spring(duration: 0.6), value: goal.progress(converter: CurrencyManager.shared.convert))
                    }
                }
                .frame(height: 6)

                // Footer row
                HStack(spacing: 0) {
                    Text(goal.progressPercent(converter: CurrencyManager.shared.convert))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)

                    Text(" \u{2022} ")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)

                    Text(goal.totalSaved(converter: CurrencyManager.shared.convert).formattedAmount(for: goal.currencyCode))
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(goalColor)

                    Text(L10n.Budget.leftOf(goal.targetAmount.formattedAmount(for: goal.currencyCode)))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    // Days remaining pill or Complete tag
                    if goal.isCompleted {
                        Text(L10n.Savings.complete)
                            .font(.app(.caption2, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.12), in: Capsule())
                    } else if let days = goal.daysRemaining {
                        Text(days > 0 ? "\(days)d" : L10n.Savings.Status.pastDate)
                            .font(.app(.caption2, weight: .medium))
                            .foregroundStyle(days < 30 ? .orange : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (days < 30 ? Color.orange : Color(.systemGray4)).opacity(0.12),
                                in: Capsule()
                            )
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

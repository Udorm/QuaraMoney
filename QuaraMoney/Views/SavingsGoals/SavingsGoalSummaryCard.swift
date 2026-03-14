import SwiftUI

struct SavingsGoalSummaryCard: View {
    let totalSaved: Decimal
    let totalTarget: Decimal
    let overallProgress: Double
    let activeCount: Int
    let completedCount: Int
    let dominantColor: Color

    var body: some View {
        Section {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Savings.totalSaved)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Text(totalSaved.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                            .font(.app(.title2, weight: .bold))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(L10n.Savings.totalTarget)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Text(totalTarget.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                            .font(.app(.title2, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                // Overall progress
                VStack(spacing: 8) {
                    ProgressView(value: min(overallProgress, 1.0))
                        .tint(dominantColor)

                    HStack {
                        Text(L10n.Budget.percentUsed(Int(overallProgress * 100)))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(activeCount) \(L10n.Budget.Filter.active), \(completedCount) \(L10n.Common.done)")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

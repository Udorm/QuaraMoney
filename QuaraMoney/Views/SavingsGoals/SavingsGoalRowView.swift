import SwiftUI

struct SavingsGoalRowView: View {
    let wallet: Wallet

    private var color: Color { Color(hex: wallet.colorHex) ?? .green }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PlanIconTile(systemImage: wallet.icon, color: color)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(wallet.name)
                        .appFont(.body, weight: .semibold)
                        .lineLimit(1)
                    if wallet.isSavingsReached {
                        Image(systemName: "checkmark.circle.fill")
                            .appFont(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer(minLength: 4)
                }

                if let targetDate = wallet.targetDate {
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

                (Text(wallet.balance.formattedAmount(for: wallet.currencyCode))
                    .foregroundStyle(.primary)
                 + Text(" / \((wallet.targetAmount ?? 0).formattedAmount(for: wallet.currencyCode))")
                    .foregroundStyle(.secondary))
                    .appFont(.caption, weight: .medium)
                    .monospacedDigit()
                PlanProgressLine(progress: wallet.savingsProgress, color: color)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let wallet = Wallet(name: "Emergency Fund", currencyCode: "USD", icon: "target", colorHex: "#10B981")
    wallet.kind = .savings
    wallet.targetAmount = 10_000
    return SavingsGoalRowView(wallet: wallet).padding()
}

import SwiftUI

/// Net-worth hero for the wallet list: headline total, 30-day change badge,
/// and a trend sparkline. Content-layer only — no glass.
///
/// Pure display: the total and series arrive precomputed (off-main) from
/// `WalletBalanceStore`. `hasLoaded == false` renders a redacted placeholder
/// instead of flashing $0 on first open.
struct NetWorthCard: View {
    let total: Decimal
    let series: [Wallet.BalancePoint]
    let currencyCode: String
    let hasLoaded: Bool

    /// Change over the sparkline window (today vs the first point).
    private var change: Decimal? {
        guard let first = series.first, series.count > 1 else { return nil }
        return total - first.balance
    }

    private var changeColor: Color {
        guard let change else { return .secondary }
        if change == 0 { return .secondary }
        return change > 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var trendTint: Color {
        guard let change, change != 0 else { return .accentColor }
        return change > 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Wallet.netWorth)
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(total.formattedAmount(for: currencyCode))
                    .font(.app(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(total >= 0 ? Color.primary : ThemeManager.shared.expenseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .redacted(reason: hasLoaded ? [] : .placeholder)
            }

            if !series.isEmpty {
                WalletSparkline(points: series, tint: trendTint, lineWidth: 2)
                    .frame(height: 52)
            }

            HStack(spacing: 6) {
                if let change {
                    HStack(spacing: 3) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.app(.caption2, weight: .bold))
                        Text(change.magnitude.formattedAmountShort(for: currencyCode))
                            .font(.app(.caption, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(changeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(changeColor.opacity(0.12), in: Capsule())
                }

                Text("wallet.last30Days".localized)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("a11y.netWorth".localized(with: total.formattedAmount(for: currencyCode)))
    }
}

#Preview {
    NetWorthCard(total: 1234.56, series: [], currencyCode: "USD", hasLoaded: true)
}

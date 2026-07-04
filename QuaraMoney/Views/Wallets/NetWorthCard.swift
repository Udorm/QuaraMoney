import SwiftUI

/// Net-worth hero for the wallet list: headline total, 30-day change badge,
/// and a trend sparkline. Content-layer only — no glass.
struct NetWorthCard: View {
    let wallets: [Wallet]
    /// Bumped by the parent on `.dataDidUpdate` so the total recomputes after
    /// balances change (the `@Transient` balance cache isn't observed by SwiftUI).
    var refreshToken: Int = 0
    @ObservedObject private var currencyManager = CurrencyManager.shared

    private static let historyDays = 30

    @State private var series: [Wallet.BalancePoint] = []

    private var totalNetWorth: Decimal {
        wallets.reduce(0) { total, wallet in
            total + currencyManager.convert(
                amount: wallet.balance,
                from: wallet.currencyCode,
                to: currencyManager.preferredCurrencyCode
            )
        }
    }

    /// Change over the sparkline window (today vs the first point).
    private var change: Decimal? {
        guard let first = series.first, series.count > 1 else { return nil }
        return totalNetWorth - first.balance
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

                Text(totalNetWorth.formattedAmount(for: currencyManager.preferredCurrencyCode))
                    .font(.app(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(totalNetWorth >= 0 ? Color.primary : ThemeManager.shared.expenseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
                        Text(change.magnitude.formattedAmountShort(for: currencyManager.preferredCurrencyCode))
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
        .accessibilityLabel("Net worth, \(totalNetWorth.formattedAmount(for: currencyManager.preferredCurrencyCode))")
        .onAppear(perform: recomputeSeries)
        .onChange(of: refreshToken) { recomputeSeries() }
        .onChange(of: currencyManager.preferredCurrencyCode) { recomputeSeries() }
    }

    private func recomputeSeries() {
        series = WalletBalanceHistory.netWorthSeries(
            wallets: wallets,
            days: Self.historyDays,
            currencyCode: currencyManager.preferredCurrencyCode
        )
    }
}

#Preview {
    NetWorthCard(wallets: [])
}

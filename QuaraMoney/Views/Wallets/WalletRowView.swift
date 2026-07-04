import SwiftUI

/// Stocks-style wallet row: identity on the left, 30-day trend in the middle,
/// balance on the right.
struct WalletRowView: View {
    let wallet: Wallet
    /// Bumped by the parent on `.dataDidUpdate` so the row re-renders and recomputes
    /// the (`@Transient`-cached) balance after transactions change elsewhere.
    var refreshToken: Int = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let historyDays = 30

    @State private var series: [Wallet.BalancePoint] = []

    // Cache theme color for performance
    private let expenseColor: Color

    init(wallet: Wallet, refreshToken: Int = 0) {
        self.wallet = wallet
        self.refreshToken = refreshToken
        self.expenseColor = ThemeManager.shared.expenseColor
    }

    private var walletColor: Color {
        Color(hex: wallet.colorHex) ?? .blue
    }

    private var showsSparkline: Bool {
        !dynamicTypeSize.isAccessibilitySize && series.count > 1
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: wallet.icon)
                .font(.app(.title3))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [walletColor, walletColor.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.name)
                    .font(.app(.headline))
                    .lineLimit(1)
                Text(wallet.currencyCode)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if showsSparkline {
                WalletSparkline(points: series, tint: walletColor, showsArea: false)
                    .frame(width: 52, height: 22)
            }

            Text(wallet.balance.formattedAmount(for: wallet.currencyCode))
                .font(.app(.body, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(wallet.balance >= 0 ? Color.primary : expenseColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(wallet.name) wallet, balance \(wallet.balance.formattedAmount(for: wallet.currencyCode))")
        .onAppear(perform: recomputeSeries)
        .onChange(of: refreshToken) { recomputeSeries() }
    }

    private func recomputeSeries() {
        series = wallet.dailyBalanceSeries(days: Self.historyDays)
    }
}

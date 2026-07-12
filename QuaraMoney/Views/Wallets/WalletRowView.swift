import SwiftUI

/// Stocks-style wallet row: identity on the left, 30-day trend in the middle,
/// balance on the right.
///
/// Pure display: the balance and series are computed off-main by
/// `WalletBalanceStore` and passed in — the row never walks the wallet's
/// transaction relationships itself. `figures == nil` means the store hasn't
/// published yet (first load); the row shows a quiet placeholder instead of
/// flashing $0.
struct WalletRowView: View {
    let wallet: Wallet
    let figures: WalletFigures?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Cache theme color for performance
    private let expenseColor: Color

    init(wallet: Wallet, figures: WalletFigures?) {
        self.wallet = wallet
        self.figures = figures
        self.expenseColor = ThemeManager.shared.expenseColor
    }

    private var walletColor: Color {
        Color(hex: wallet.colorHex) ?? .blue
    }

    private var showsSparkline: Bool {
        guard let figures else { return false }
        return !dynamicTypeSize.isAccessibilitySize && figures.series.count > 1
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: wallet.icon)
                .appFont(.title3)
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
                    .appFont(.headline)
                    .lineLimit(1)
                Text(wallet.currencyCode)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if showsSparkline, let figures {
                WalletSparkline(points: figures.series, tint: walletColor, showsArea: false)
                    .frame(width: 52, height: 22)
            }

            if let figures {
                Text(figures.balance.formattedAmount(for: wallet.currencyCode))
                    .appFont(.body, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(figures.balance >= 0 ? Color.primary : expenseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                // First load: figures land a beat later (computed off-main).
                Text(verbatim: "–")
                    .appFont(.body, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(wallet.name) wallet" +
            (figures.map { ", balance \($0.balance.formattedAmount(for: wallet.currencyCode))" } ?? "")
        )
    }
}

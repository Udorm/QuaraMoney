import SwiftUI
import Charts

/// Tiny non-interactive balance trend line used in wallet rows and heroes.
/// Pure display: no axes, no hit testing, flat line when there's no history.
struct WalletSparkline: View {
    let points: [Wallet.BalancePoint]
    let tint: Color
    var showsArea: Bool = true
    var lineWidth: CGFloat = 1.5

    private var domain: ClosedRange<Double> {
        let values = points.map { ($0.balance as NSDecimalNumber).doubleValue }
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        guard min != max else { return (min - 1)...(max + 1) }
        // Small headroom so the line doesn't kiss the frame edges.
        let pad = (max - min) * 0.12
        return (min - pad)...(max + pad)
    }

    var body: some View {
        Chart(points) { point in
            if showsArea {
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Min", domain.lowerBound),
                    yEnd: .value("Balance", (point.balance as NSDecimalNumber).doubleValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.28), tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            LineMark(
                x: .value("Date", point.date),
                y: .value("Balance", (point.balance as NSDecimalNumber).doubleValue)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .foregroundStyle(tint)
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum WalletBalanceHistory {
    /// Combined net-worth series across wallets, converted into `currencyCode`
    /// with live rates (same conversion the Net Worth total uses).
    @MainActor
    static func netWorthSeries(
        wallets: [Wallet],
        days: Int,
        currencyCode: String
    ) -> [Wallet.BalancePoint] {
        guard !wallets.isEmpty, days > 0 else { return [] }
        let manager = CurrencyManager.shared
        var totals: [Date: Decimal] = [:]
        for wallet in wallets {
            for point in wallet.dailyBalanceSeries(days: days) {
                let converted = manager.convert(
                    amount: point.balance,
                    from: wallet.currencyCode,
                    to: currencyCode
                )
                totals[point.date, default: 0] += converted
            }
        }
        return totals
            .map { Wallet.BalancePoint(date: $0.key, balance: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

import SwiftUI

/// Flat Plan surface copied locally from the Pro Analytics card recipe to keep
/// the two features visually aligned without coupling their private components.
struct PlanCard<Content: View>: View {
    var tint: Color?
    var spacing: CGFloat
    var usesGlass: Bool
    @ViewBuilder var content: () -> Content

    init(
        tint: Color? = nil,
        spacing: CGFloat = 16,
        usesGlass: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.spacing = spacing
        self.usesGlass = usesGlass
        self.content = content
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        if #available(iOS 26.0, *), usesGlass {
            if let tint {
                cardContent
                    .glassEffect(.regular.tint(tint.opacity(0.16)), in: shape)
                    .clipShape(shape)
                    .contentShape(shape)
            } else {
                cardContent
                    .glassEffect(.regular, in: shape)
                    .clipShape(shape)
                    .contentShape(shape)
            }
        } else {
            cardContent
                .background(
                    (tint?.opacity(0.09) ?? Color(.secondarySystemGroupedBackground)),
                    in: shape
                )
                .contentShape(shape)
        }
    }
}

/// Gives the current amount clear visual priority while keeping the target
/// nearby as supporting context. The vertical fallback prevents long currency
/// values and Khmer copy from becoming cramped at larger text sizes.
struct PlanAmountSummary: View {
    let title: String
    let amount: String
    var targetAmount: String?
    var amountColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)

            if let targetAmount {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        amountText
                            .fixedSize(horizontal: true, vertical: false)
                        targetText(targetAmount)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        amountText
                        targetText(targetAmount)
                    }
                }
            } else {
                amountText
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var amountText: some View {
        Text(amount)
            .appFont(.title, weight: .bold)
            .foregroundStyle(amountColor)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private func targetText(_ targetAmount: String) -> some View {
        Text("plan.of_amount".localized(with: targetAmount))
            .appFont(.subheadline, weight: .medium)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

struct PlanProgressBar: View {
    let progress: Decimal
    let color: Color
    var isDeterminate = true

    private var clampedFraction: CGFloat {
        let clamped = min(max(progress, 0), 1)
        return CGFloat(NSDecimalNumber(decimal: clamped).doubleValue)
    }

    private var percent: Int {
        NSDecimalNumber(decimal: max(0, progress) * 100).intValue
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))

                if isDeterminate {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.68)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * clampedFraction)
                } else {
                    Capsule()
                        .fill(Color.orange.opacity(0.55))
                        .frame(width: max(24, proxy.size.width * clampedFraction))
                }
            }
        }
        .frame(height: 10)
        .accessibilityElement()
        .accessibilityLabel("plan.progress".localized)
        .accessibilityValue(
            isDeterminate
                ? "plan.percent_accessibility".localized(with: percent)
                : "plan.partial_data".localized
        )
    }
}

struct PlanProgressLine: View {
    let progress: Decimal
    let color: Color
    var isDeterminate = true

    var body: some View {
        HStack(spacing: 10) {
            PlanProgressBar(
                progress: progress,
                color: color,
                isDeterminate: isDeterminate
            )

            if isDeterminate {
                Text(PlanDisplayFormatting.percent(progress))
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
    }
}

struct PlanIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .appFont(size: size * 0.42, weight: .semibold)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                color.opacity(0.14),
                in: RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
            )
    }
}

struct PlanPartialDataLabel: View {
    var body: some View {
        Label("plan.partial_data_conversion".localized, systemImage: "exclamationmark.triangle.fill")
            .appFont(.caption)
            .foregroundStyle(.orange)
    }
}

enum PlanDisplayFormatting {
    static func percent(_ progress: Decimal) -> String {
        let value = NSDecimalNumber(decimal: max(0, progress)).doubleValue
        return value.formatted(
            .percent
                .locale(.app)
                .precision(.fractionLength(0))
        )
    }

    static func displayEnd(for range: PlanDateRange, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
    }

    static func range(_ range: PlanDateRange) -> String {
        let formatter = AppDateFormatterCache.formatter(dateFormat: "MMM d, yyyy", locale: .app)
        return "\(formatter.string(from: range.start)) – \(formatter.string(from: displayEnd(for: range)))"
    }
}

#Preview {
    ScrollView {
        PlanCard(tint: .blue) {
            Label("plan.budgets".localized, systemImage: "chart.bar.fill")
                .appFont(.headline)
            Text(Decimal(725).formattedAmount(for: "USD"))
                .appFont(.title2, weight: .bold)
            PlanProgressBar(progress: Decimal(string: "0.72")!, color: .blue)
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

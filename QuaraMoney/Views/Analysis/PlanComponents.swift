import SwiftUI

/// Flat Plan surface copied locally from the Pro Analytics card recipe to keep
/// the two features visually aligned without coupling their private components.
struct PlanCard<Content: View>: View {
    var tint: Color?
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        tint: Color? = nil,
        spacing: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (tint?.opacity(0.09) ?? Color(.secondarySystemGroupedBackground)),
            in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        )
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
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("plan.progress".localized)
        .accessibilityValue(
            isDeterminate
                ? "plan.percent_accessibility".localized(with: percent)
                : "plan.partial_data".localized
        )
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
        "\(NSDecimalNumber(decimal: max(0, progress) * 100).intValue)%"
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

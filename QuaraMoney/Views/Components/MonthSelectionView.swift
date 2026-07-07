import SwiftUI

// MARK: - GlassPeriodSelector

/// Glass-capsule period picker: a translucent capsule track with a sliding
/// tinted pill for the selected period.
struct GlassPeriodSelector: View {
    @Binding var selectedTab: TabPeriodSelection
    let months: [Date] // Expected to be precisely 3 months

    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 2) {
            segment(label: L10n.Period.custom, tag: .custom)
            ForEach(months, id: \.self) { date in
                segment(label: monthLabel(for: date), tag: .month(date))
            }
        }
        .padding(3)
        .onAppear {
            if case .custom = selectedTab { return }
            if case .month(let date) = selectedTab, !months.contains(where: { Calendar.current.isDate($0, equalTo: date, toGranularity: .month) }) {
                if let first = months.last {
                    selectedTab = .month(first)
                }
            }
        }
    }

    private func segment(label: String, tag: TabPeriodSelection) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            withAnimation(.smooth(duration: 0.3)) {
                selectedTab = tag
            }
        } label: {
            Text(label)
                .font(.app(.footnote, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selectedPill", in: pillNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Shared helper

private func monthLabel(for date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
        return L10n.Filter.thisMonth
    } else if calendar.isDate(
        date,
        equalTo: calendar.date(byAdding: .month, value: -1, to: Date())!,
        toGranularity: .month
    ) {
        return L10n.Filter.lastMonth
    } else {
        let formatter = DateFormatter()
        // Shorter format to save space in the segmented control (e.g., Jan 2026)
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}

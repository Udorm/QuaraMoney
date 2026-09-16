import SwiftUI

// MARK: - PeriodTabPicker

/// Period tabs for transaction lists — Custom plus the three most recent
/// months — as a native segmented control, so it matches the app's other tab
/// bars.
struct PeriodTabPicker: View {
    @Binding var selectedTab: TabPeriodSelection
    let months: [Date] // Expected to be precisely 3 months

    var body: some View {
        // Animated so the custom date range row below slides in and out.
        Picker("filter.period".localized, selection: $selectedTab.animation(.smooth(duration: 0.3))) {
            Text(L10n.Period.custom).tag(TabPeriodSelection.custom)
            ForEach(months, id: \.self) { date in
                Text(monthLabel(for: date)).tag(TabPeriodSelection.month(date))
            }
        }
        .pickerStyle(.segmented)
        .onAppear {
            if case .custom = selectedTab { return }
            if case .month(let date) = selectedTab, !months.contains(where: { Calendar.current.isDate($0, equalTo: date, toGranularity: .month) }) {
                if let first = months.last {
                    selectedTab = .month(first)
                }
            }
        }
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
        // Shorter format to save space in the segmented control (e.g., Jan 2026)
        return AppDateFormatterCache.formatter(dateFormat: "MMM yyyy", locale: .app)
            .string(from: date)
    }
}

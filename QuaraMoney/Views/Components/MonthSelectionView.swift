import SwiftUI
import UIKit

// MARK: - MonthSelectionView

struct MonthSelectionView: View {
    @Binding var selectedTab: TabPeriodSelection
    let months: [Date] // Expected to be precisely 3 months
    
    var body: some View {
        Picker("Month", selection: $selectedTab) {
            Text(L10n.Period.custom).tag(TabPeriodSelection.custom)
            ForEach(months, id: \.self) { date in
                Text(monthLabel(for: date)).tag(TabPeriodSelection.month(date))
            }
        }
        .pickerStyle(.segmented)
        // Set the default if it somehow isn't valid
        .onAppear {
            // Reset appearance to system defaults
            UISegmentedControl.appearance().backgroundColor = nil
            UISegmentedControl.appearance().selectedSegmentTintColor = nil
            
//            // Set consistent font size to match DatePicker
//            let font = UIFont.app(ofSize: 15, weight: .regular)
//            let selectedFont = UIFont.app(ofSize: 15, weight: .semibold)
//            
//            UISegmentedControl.appearance().setTitleTextAttributes([.font: font], for: .normal)
//            UISegmentedControl.appearance().setTitleTextAttributes([.font: selectedFont], for: .selected)

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
        let formatter = DateFormatter()
        // Shorter format to save space in the segmented control (e.g., Jan 2026)
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}

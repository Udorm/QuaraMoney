import SwiftUI

struct MonthSelectionView: View {
    @Binding var selectedDate: Date
    let months: [Date]
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(months, id: \.self) { date in
                        MonthTab(
                            date: date,
                            isSelected: Calendar.current.isDate(date, equalTo: selectedDate, toGranularity: .month),
                            onTap: {
                                withAnimation {
                                    selectedDate = date
                                    proxy.scrollTo(date, anchor: .center)
                                }
                            }
                        )
                        .id(date)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .onAppear {
                // Scroll to the selected date (usually current month which is last in the list)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(selectedDate, anchor: .center)
                    }
                }
            }
            .onChange(of: selectedDate) { oldValue, newValue in
                 withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                 }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct MonthTab: View {
    let date: Date
    let isSelected: Bool
    let onTap: () -> Void
    
    // Helper to format date
    private var title: String {
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
            return L10n.Filter.thisMonth
        } else if calendar.isDate(date, equalTo: calendar.date(byAdding: .month, value: -1, to: Date())!, toGranularity: .month) {
            return L10n.Filter.lastMonth
        } else {
            // Using a custom format or standard one
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy" 
            // Or just Month if year is current year? User said "the following last months". 
            // Let's stick to Month Year for clarity or just Month if context is clear.
            // Given it scrolls back 12 months, year change is likely.
            return formatter.string(from: date)
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.app(.subheadline))
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor : Color(.separator), lineWidth: 1)
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

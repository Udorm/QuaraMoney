import Foundation

/// Shared filter period enum used across ViewModels.
/// Consolidates duplicate Period enums from HomeViewModel, AnalysisViewModel, WalletDetailViewModel.
enum FilterPeriod: String, CaseIterable, Identifiable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisYear = "This Year"
    case custom = "Custom"
    
    var id: String { self.rawValue }
    
    /// Returns the start and end dates for this period
    func dateRange(customStart: Date? = nil, customEnd: Date? = nil) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .thisMonth:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return (now, now)
            }
            return (start, end)
            
        case .lastMonth:
            guard let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return (now, now)
            }
            return (start, end)
            
        case .thisYear:
            guard let start = calendar.date(from: calendar.dateComponents([.year], from: now)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else {
                return (now, now)
            }
            return (start, end)
            
        case .custom:
            let start = calendar.startOfDay(for: customStart ?? now)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEnd ?? now) ?? now
            return (start, end)
        }
    }
    
    /// Formats the period for display
    func description(customStart: Date? = nil, customEnd: Date? = nil) -> String {
        switch self {
        case .custom:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            let start = customStart ?? Date()
            let end = customEnd ?? Date()
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        default:
            return self.rawValue
        }
    }
}

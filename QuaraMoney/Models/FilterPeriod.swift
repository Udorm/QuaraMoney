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

// MARK: - Analysis Period (for AnalysisView with navigation support)

/// Period enum specifically for AnalysisView with time-based navigation
enum AnalysisPeriod: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case sixMonths = "6 Months"
    case year = "Year"
    case custom = "Custom"
    
    var id: String { self.rawValue }
    
    /// Time grouping for chart display
    var grouping: TimeGrouping {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        case .sixMonths, .year: return .month
        case .custom: return .day // Will be auto-detected based on range
        }
    }
    
    /// Returns the date range for this period relative to a reference date
    func dateRange(referenceDate: Date, customStart: Date? = nil, customEnd: Date? = nil) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        
        switch self {
        case .day:
            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? referenceDate
            return (start, end)
            
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            guard let startOfWeek = calendar.date(from: components),
                  let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else {
                return (referenceDate, referenceDate)
            }
            return (startOfWeek, endOfWeek)
            
        case .month:
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)),
                  let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
                return (referenceDate, referenceDate)
            }
            return (startOfMonth, endOfMonth)
            
        case .sixMonths:
            guard let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)),
                  let startOfRange = calendar.date(byAdding: .month, value: -5, to: startOfCurrentMonth),
                  let endOfRange = calendar.date(byAdding: .month, value: 1, to: startOfCurrentMonth) else {
                return (referenceDate, referenceDate)
            }
            return (startOfRange, endOfRange)
            
        case .year:
            guard let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: referenceDate)),
                  let endOfYear = calendar.date(byAdding: .year, value: 1, to: startOfYear) else {
                return (referenceDate, referenceDate)
            }
            return (startOfYear, endOfYear)
            
        case .custom:
            let start = calendar.startOfDay(for: customStart ?? referenceDate)
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: customEnd ?? referenceDate) ?? referenceDate
            return (start, end)
        }
    }
    
    /// Navigate back one period
    func navigateBack(from date: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: -1, to: date) ?? date
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -3, to: date) ?? date
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: date) ?? date
        case .custom:
            return date
        }
    }
    
    /// Navigate forward one period
    func navigateForward(from date: Date) -> Date {
        let calendar = Calendar.current
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .sixMonths:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .year:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        case .custom:
            return date
        }
    }
    
    /// Formats the period for display
    func description(referenceDate: Date, customStart: Date? = nil, customEnd: Date? = nil) -> String {
        let calendar = Calendar.current
        let range = dateRange(referenceDate: referenceDate, customStart: customStart, customEnd: customEnd)
        
        switch self {
        case .day:
            return range.start.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .week:
            let weekEnd = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            return "\(range.start.formatted(.dateTime.month(.abbreviated).day())) - \(weekEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month:
            return range.start.formatted(.dateTime.month(.wide).year())
        case .sixMonths:
            let rangeEnd = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            return "\(range.start.formatted(.dateTime.month(.abbreviated).year())) - \(rangeEnd.formatted(.dateTime.month(.abbreviated).year()))"
        case .year:
            return range.start.formatted(.dateTime.year())
        case .custom:
            return "\((customStart ?? Date()).formatted(date: .abbreviated, time: .omitted)) - \((customEnd ?? Date()).formatted(date: .abbreviated, time: .omitted))"
        }
    }
    
    /// Auto-detect appropriate grouping based on custom date range
    static func autoDetectGrouping(start: Date, end: Date) -> TimeGrouping {
        let calendar = Calendar.current
        if let days = calendar.dateComponents([.day], from: start, to: end).day {
            if days <= 1 {
                return .hour
            } else if days <= 60 {
                return .day
            } else if days <= 365 {
                return .week
            } else {
                return .month
            }
        }
        return .day
    }
}

// MARK: - Time Grouping

enum TimeGrouping {
    case hour
    case day
    case week
    case month
    case year
}

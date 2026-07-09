import Foundation

/// Budget period types supporting flexible budgeting timeframes
enum BudgetPeriodType: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .weekly: return L10n.Period.weekly
        case .biweekly: return "period.biweekly".localized
        case .monthly: return L10n.Period.monthly
        case .quarterly: return L10n.Period.quarterly
        case .yearly: return L10n.Period.yearly
        case .custom: return L10n.Period.custom
        }
    }
    
    var icon: String {
        switch self {
        case .weekly: return "calendar.badge.clock"
        case .biweekly: return "calendar"
        case .monthly: return "calendar.circle"
        case .quarterly: return "calendar.badge.plus"
        case .yearly: return "calendar.badge.exclamationmark"
        case .custom: return "calendar.day.timeline.left"
        }
    }
    
    /// Calculate the date range for a budget period starting from a given date
    func dateRange(from startDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: startDate)
        
        switch self {
        case .weekly:
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return (start, end)
            
        case .biweekly:
            let end = calendar.date(byAdding: .day, value: 14, to: start) ?? start
            return (start, end)
            
        case .monthly:
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (start, end)
            
        case .quarterly:
            let end = calendar.date(byAdding: .month, value: 3, to: start) ?? start
            return (start, end)
            
        case .yearly:
            let end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
            return (start, end)
            
        case .custom:
            // For custom, end date is managed externally
            return (start, start)
        }
    }
    
    /// Calculate the next period's start date
    func nextPeriodStart(from currentStart: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: currentStart) ?? currentStart
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: currentStart) ?? currentStart
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: currentStart) ?? currentStart
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3, to: currentStart) ?? currentStart
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: currentStart) ?? currentStart
        case .custom:
            return currentStart
        }
    }
    
    /// Get the start of the current period containing a date
    func periodStart(containing date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            
        case .biweekly:
            // Start from a known reference point and find the bi-weekly period
            let referenceDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
            let daysSinceReference = calendar.dateComponents([.day], from: referenceDate, to: date).day ?? 0
            let periodNumber = daysSinceReference / 14
            return calendar.date(byAdding: .day, value: periodNumber * 14, to: referenceDate) ?? date
            
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            
        case .quarterly:
            let components = calendar.dateComponents([.year, .month], from: date)
            let month = components.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var quarterComponents = DateComponents()
            quarterComponents.year = components.year
            quarterComponents.month = quarterStartMonth
            quarterComponents.day = 1
            return calendar.date(from: quarterComponents) ?? calendar.startOfDay(for: date)
            
        case .yearly:
            let components = calendar.dateComponents([.year], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
            
        case .custom:
            return calendar.startOfDay(for: date)
        }
    }
    
    /// Format the period for display
    func formatPeriod(startDate: Date, endDate: Date? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.selectedLanguage.locale

        switch self {
        case .weekly:
            formatter.dateFormat = "MMM d"
            let range = dateRange(from: startDate)
            let endDisplay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            return "\(formatter.string(from: range.start)) - \(formatter.string(from: endDisplay))"
            
        case .biweekly:
            formatter.dateFormat = "MMM d"
            let range = dateRange(from: startDate)
            let endDisplay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            return "\(formatter.string(from: range.start)) - \(formatter.string(from: endDisplay))"
            
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: startDate)
            
        case .quarterly:
            let calendar = Calendar.current
            let month = calendar.component(.month, from: startDate)
            let year = calendar.component(.year, from: startDate)
            let quarter = ((month - 1) / 3) + 1
            return "Q\(quarter) \(year)"
            
        case .yearly:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: startDate)
            
        case .custom:
            formatter.dateFormat = "MMM d, yyyy"
            if let end = endDate {
                return "\(formatter.string(from: startDate)) - \(formatter.string(from: end))"
            }
            return formatter.string(from: startDate)
        }
    }
    
    /// Days remaining in the current period
    func daysRemaining(from date: Date = Date(), calendar: Calendar = .current) -> Int {
        let periodStart = self.periodStart(containing: date, calendar: calendar)
        let range = dateRange(from: periodStart, calendar: calendar)
        return calendar.dateComponents([.day], from: date, to: range.end).day ?? 0
    }
    
    /// Total days in the period
    func totalDays(from startDate: Date, calendar: Calendar = .current) -> Int {
        let range = dateRange(from: startDate, calendar: calendar)
        return calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1
    }
}

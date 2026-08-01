import Foundation

enum TransactionSortOption: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst
    case highestAmount
    case lowestAmount
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .newestFirst: return L10n.Sort.newestFirst
        case .oldestFirst: return L10n.Sort.oldestFirst
        case .highestAmount: return L10n.Sort.highestAmount
        case .lowestAmount: return L10n.Sort.lowestAmount
        }
    }

    /// Row glyph for the expanded sort panel. Date sorts read as calendar
    /// variants, amount sorts as trend lines, so the two axes stay separable
    /// at a glance even before the label is read.
    var systemImage: String {
        switch self {
        case .newestFirst: return "calendar.badge.clock"
        case .oldestFirst: return "calendar"
        case .highestAmount: return "chart.line.uptrend.xyaxis"
        case .lowestAmount: return "chart.line.downtrend.xyaxis"
        }
    }
}

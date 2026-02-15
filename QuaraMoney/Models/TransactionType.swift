import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case transfer
    case adjustment
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .income: return L10n.Transaction.TransactionType.income
        case .expense: return L10n.Transaction.TransactionType.expense
        case .transfer: return L10n.Transaction.TransactionType.transfer
        case .adjustment: return "Adjustment" // TODO: Add localization
        }
    }
}

enum Frequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .daily: return L10n.Frequency.daily
        case .weekly: return L10n.Frequency.weekly
        case .monthly: return L10n.Frequency.monthly
        case .yearly: return L10n.Frequency.yearly
        }
    }
}

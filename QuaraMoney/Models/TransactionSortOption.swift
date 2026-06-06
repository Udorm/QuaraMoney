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
}

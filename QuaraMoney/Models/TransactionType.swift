import Foundation

enum TransactionType: String, Codable {
    case income
    case expense
    case transfer
}

enum Frequency: String, Codable {
    case daily, weekly, monthly, yearly
}

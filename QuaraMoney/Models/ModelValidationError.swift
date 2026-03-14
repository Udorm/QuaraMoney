import Foundation

/// Validation errors for core financial models.
///
/// Each case carries a user-facing message suitable for display in alerts.
enum ModelValidationError: LocalizedError, Equatable {
    case emptyName(field: String)
    case negativeOrZeroAmount(field: String)
    case invalidCurrencyCode
    case invalidExchangeRate

    var errorDescription: String? {
        switch self {
        case .emptyName(let field):
            return "\(field) cannot be empty."
        case .negativeOrZeroAmount(let field):
            return "\(field) must be greater than zero."
        case .invalidCurrencyCode:
            return "Currency code must be a valid 3-letter ISO code."
        case .invalidExchangeRate:
            return "Exchange rate must be greater than zero."
        }
    }
}

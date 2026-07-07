import Foundation

/// Defines how a budget amount is calculated
enum BudgetAmountType: Codable, Equatable, Sendable {
    /// Fixed amount budget (e.g., $500)
    case fixed(Decimal)
    
    /// Percentage of income (e.g., 30% of monthly income)
    /// Value is stored as 0.0 - 1.0 (e.g., 0.30 for 30%)
    case percentOfIncome(Double)
    
    // MARK: - Computed Properties
    
    var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }
    
    var isPercentage: Bool {
        if case .percentOfIncome = self { return true }
        return false
    }
    
    var fixedAmount: Decimal? {
        if case .fixed(let amount) = self { return amount }
        return nil
    }
    
    var percentage: Double? {
        if case .percentOfIncome(let percent) = self { return percent }
        return nil
    }
    
    var displayString: String {
        switch self {
        case .fixed(let amount):
            return amount.formatted(.number.precision(.fractionLength(2)))
        case .percentOfIncome(let percent):
            return "\(Int(percent * 100))% of income"
        }
    }
    
    // MARK: - Calculations
    
    /// Calculate the actual budget limit based on income (for percentage-based budgets)
    func calculateLimit(income: Decimal) -> Decimal {
        switch self {
        case .fixed(let amount):
            return amount
        case .percentOfIncome(let percent):
            return income * Decimal(percent)
        }
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    private enum AmountTypeIdentifier: String, Codable {
        case fixed
        case percentOfIncome
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AmountTypeIdentifier.self, forKey: .type)
        
        switch type {
        case .fixed:
            let value = try container.decode(Decimal.self, forKey: .value)
            self = .fixed(value)
        case .percentOfIncome:
            let value = try container.decode(Double.self, forKey: .value)
            self = .percentOfIncome(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .fixed(let amount):
            try container.encode(AmountTypeIdentifier.fixed, forKey: .type)
            try container.encode(amount, forKey: .value)
        case .percentOfIncome(let percent):
            try container.encode(AmountTypeIdentifier.percentOfIncome, forKey: .type)
            try container.encode(percent, forKey: .value)
        }
    }

    
    // MARK: - Helpers
    
    static func decode(from data: Data) -> BudgetAmountType? {
        try? JSONDecoder().decode(BudgetAmountType.self, from: data)
    }
    
    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

// MARK: - Budget Category Type

/// High-level budget category types for template-based allocation
enum BudgetCategoryType: String, CaseIterable, Codable {
    case needs    // Essential expenses: housing, utilities, groceries, insurance
    case wants    // Discretionary: entertainment, dining out, hobbies
    case savings  // Savings & debt: emergency fund, investments, debt payoff
    
    var displayName: String {
        switch self {
        case .needs: return L10n.BudgetCategoryType.Needs.title
        case .wants: return L10n.BudgetCategoryType.Wants.title
        case .savings: return L10n.BudgetCategoryType.Savings.title
        }
    }
    
    var description: String {
        switch self {
        case .needs: return L10n.BudgetCategoryType.Needs.desc
        case .wants: return L10n.BudgetCategoryType.Wants.desc
        case .savings: return L10n.BudgetCategoryType.Savings.desc
        }
    }
    
    var icon: String {
        switch self {
        case .needs: return "house.fill"
        case .wants: return "star.fill"
        case .savings: return "banknote.fill"
        }
    }
    
    var color: String {
        switch self {
        case .needs: return "#3B82F6"   // Blue
        case .wants: return "#8B5CF6"   // Purple
        case .savings: return "#10B981" // Green
        }
    }
}

import SwiftData
import Foundation

/// Groups multiple categories together for bundled budgeting
@Model
final class CategoryGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var groupDescription: String?
    var iconName: String
    var colorHex: String
    
    /// Budget category type stored as raw value for SwiftData compatibility
    private var budgetCategoryTypeRaw: String?
    
    var budgetCategoryType: BudgetCategoryType? {
        get {
            guard let raw = budgetCategoryTypeRaw else { return nil }
            return BudgetCategoryType(rawValue: raw)
        }
        set { budgetCategoryTypeRaw = newValue?.rawValue }
    }
    
    // Relationships
    @Relationship(deleteRule: .nullify) var categories: [Category]
    @Relationship(deleteRule: .cascade, inverse: \Budget.categoryGroup) var budgets: [Budget]?
    
    init(
        name: String,
        iconName: String = "folder.fill",
        colorHex: String = "#6B7280",
        budgetCategoryType: BudgetCategoryType? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.groupDescription = nil
        self.iconName = iconName
        self.colorHex = colorHex
        self.budgetCategoryTypeRaw = budgetCategoryType?.rawValue
        self.categories = []
    }
    
    // MARK: - Computed Properties
    
    /// Total number of categories in the group
    var categoryCount: Int {
        categories.count
    }
    
    /// Names of categories for display
    var categoryNames: [String] {
        categories.map { $0.name }
    }
    
    /// Combined category IDs for transaction filtering
    var categoryIds: [UUID] {
        categories.map { $0.id }
    }
    
    // MARK: - Methods
    
    /// Add a category to the group
    func addCategory(_ category: Category) {
        if !categories.contains(where: { $0.id == category.id }) {
            categories.append(category)
        }
    }
    
    /// Remove a category from the group
    func removeCategory(_ category: Category) {
        categories.removeAll { $0.id == category.id }
    }
    
    /// Check if group contains a specific category
    func contains(_ category: Category) -> Bool {
        categories.contains { $0.id == category.id }
    }
}

// MARK: - Predefined Category Groups

enum PredefinedCategoryGroup: String, CaseIterable, Identifiable {
    case essentials
    case lifestyle
    case entertainment
    case transportation
    case healthWellness
    case financialGoals
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .essentials: return "Essentials"
        case .lifestyle: return "Lifestyle"
        case .entertainment: return "Entertainment"
        case .transportation: return "Transportation"
        case .healthWellness: return "Health & Wellness"
        case .financialGoals: return "Financial Goals"
        }
    }
    
    var icon: String {
        switch self {
        case .essentials: return "house.fill"
        case .lifestyle: return "sparkles"
        case .entertainment: return "tv.fill"
        case .transportation: return "car.fill"
        case .healthWellness: return "heart.fill"
        case .financialGoals: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var color: String {
        switch self {
        case .essentials: return "#3B82F6"      // Blue
        case .lifestyle: return "#8B5CF6"       // Purple
        case .entertainment: return "#F59E0B"   // Amber
        case .transportation: return "#06B6D4"  // Cyan
        case .healthWellness: return "#EF4444"  // Red
        case .financialGoals: return "#10B981"  // Green
        }
    }
    
    var budgetCategoryType: BudgetCategoryType {
        switch self {
        case .essentials: return .needs
        case .lifestyle: return .wants
        case .entertainment: return .wants
        case .transportation: return .needs
        case .healthWellness: return .needs
        case .financialGoals: return .savings
        }
    }
    
    var description: String {
        switch self {
        case .essentials:
            return "Housing, utilities, groceries, and other must-haves"
        case .lifestyle:
            return "Shopping, dining, and personal care"
        case .entertainment:
            return "Streaming, gaming, movies, and hobbies"
        case .transportation:
            return "Car, gas, public transit, and ride-shares"
        case .healthWellness:
            return "Healthcare, gym, and wellness activities"
        case .financialGoals:
            return "Savings, investments, and debt payments"
        }
    }
    
    /// Suggested category names that belong to this group
    var suggestedCategories: [String] {
        switch self {
        case .essentials:
            return ["Rent/Mortgage", "Utilities", "Groceries", "Insurance", "Internet"]
        case .lifestyle:
            return ["Shopping", "Dining Out", "Personal Care", "Clothing"]
        case .entertainment:
            return ["Streaming", "Gaming", "Movies", "Hobbies", "Books"]
        case .transportation:
            return ["Gas/Fuel", "Car Payment", "Public Transit", "Parking", "Maintenance"]
        case .healthWellness:
            return ["Healthcare", "Gym", "Pharmacy", "Mental Health"]
        case .financialGoals:
            return ["Savings", "Investments", "Debt Payment", "Emergency Fund"]
        }
    }
    
    /// Create a CategoryGroup instance from this template
    func createGroup() -> CategoryGroup {
        CategoryGroup(
            name: displayName,
            iconName: icon,
            colorHex: color,
            budgetCategoryType: budgetCategoryType
        )
    }
}

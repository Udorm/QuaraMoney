import SwiftData
import Foundation

/// Savings goal model integrated with the budgeting system
@Model
final class SavingsGoal {
    @Attribute(.unique) var id: UUID
    var name: String
    var goalDescription: String?
    var targetAmount: Decimal
    var currentAmount: Decimal
    var currencyCode: String
    var targetDate: Date?
    var createdDate: Date
    var iconName: String
    var colorHex: String
    var isCompleted: Bool
    var completedDate: Date?
    
    /// Auto-contribution settings
    var autoContributeEnabled: Bool
    var autoContributeAmount: Decimal?
    
    /// Auto-contribute period stored as raw value for SwiftData compatibility
    private var autoContributePeriodRaw: String?
    
    var autoContributePeriod: BudgetPeriodType? {
        get {
            guard let raw = autoContributePeriodRaw else { return nil }
            return BudgetPeriodType(rawValue: raw)
        }
        set { autoContributePeriodRaw = newValue?.rawValue }
    }
    
    /// Priority for ordering (lower = higher priority)
    var priority: Int
    
    // Relationships
    @Relationship(deleteRule: .nullify) var linkedWallet: Wallet?
    @Relationship(deleteRule: .nullify, inverse: \Budget.savingsGoal) var linkedBudget: Budget?
    
    init(
        name: String,
        targetAmount: Decimal,
        currencyCode: String = "USD",
        targetDate: Date? = nil,
        iconName: String = "target",
        colorHex: String = "#10B981"
    ) {
        self.id = UUID()
        self.name = name
        self.goalDescription = nil
        self.targetAmount = targetAmount
        self.currentAmount = 0
        self.currencyCode = currencyCode
        self.targetDate = targetDate
        self.createdDate = Date()
        self.iconName = iconName
        self.colorHex = colorHex
        self.isCompleted = false
        self.completedDate = nil
        self.autoContributeEnabled = false
        self.autoContributeAmount = nil
        self.autoContributePeriodRaw = nil
        self.priority = 0
    }
    
    // MARK: - Computed Properties
    
    /// Progress towards goal (0.0 - 1.0+)
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return Double(truncating: currentAmount as NSNumber) / Double(truncating: targetAmount as NSNumber)
    }
    
    /// Progress as percentage string
    var progressPercent: String {
        "\(Int(min(progress, 1.0) * 100))%"
    }
    
    /// Amount remaining to reach goal
    var remainingAmount: Decimal {
        max(targetAmount - currentAmount, 0)
    }
    
    /// Days until target date (nil if no target date)
    var daysRemaining: Int? {
        guard let targetDate = targetDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: Date(), to: targetDate).day
    }
    
    /// Suggested monthly contribution to reach goal by target date
    var suggestedMonthlyContribution: Decimal? {
        guard let targetDate = targetDate,
              targetDate > Date(),
              remainingAmount > 0 else { return nil }
        
        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: Date(), to: targetDate).month ?? 1
        guard months > 0 else { return remainingAmount }
        
        return remainingAmount / Decimal(months)
    }
    
    /// Whether the goal is on track based on target date
    var isOnTrack: Bool {
        guard let targetDate = targetDate,
              let daysRemaining = daysRemaining,
              daysRemaining > 0 else { return true }
        
        let calendar = Calendar.current
        let totalDays = calendar.dateComponents([.day], from: createdDate, to: targetDate).day ?? 1
        guard totalDays > 0 else { return true }
        
        let expectedProgress = Double(totalDays - daysRemaining) / Double(totalDays)
        return progress >= expectedProgress * 0.9 // 10% buffer
    }
    
    /// Status message for the goal
    var statusMessage: String {
        if isCompleted {
            return L10n.Savings.Status.reached
        }
        
        if let days = daysRemaining {
            if days < 0 {
                return L10n.Savings.Status.pastDate
            } else if days == 0 {
                return L10n.Savings.Status.today
            } else if days <= 7 {
                return L10n.Savings.Status.daysLeft(days)
            } else if days <= 30 {
                return L10n.Savings.Status.weeksLeft(days / 7)
            } else {
                return L10n.Savings.Status.monthsLeft(days / 30)
            }
        }
        
        return L10n.Savings.Status.noDate
    }
    
    // MARK: - Methods
    
    /// Add contribution to the goal
    func addContribution(_ amount: Decimal) {
        currentAmount += amount
        checkCompletion()
    }
    
    /// Withdraw from the goal
    func withdraw(_ amount: Decimal) {
        currentAmount = max(currentAmount - amount, 0)
        // Uncomplete if withdrawn below target
        if currentAmount < targetAmount {
            isCompleted = false
            completedDate = nil
        }
    }
    
    /// Check and update completion status
    private func checkCompletion() {
        if currentAmount >= targetAmount && !isCompleted {
            isCompleted = true
            completedDate = Date()
        }
    }
}

// MARK: - Predefined Goal Templates

enum SavingsGoalTemplate: String, CaseIterable, Identifiable {
    case emergencyFund
    case vacation
    case carPurchase
    case homePurchase
    case retirement
    case education
    case wedding
    case debtPayoff
    case electronics
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .emergencyFund: return L10n.Savings.Template.EmergencyFund.title
        case .vacation: return L10n.Savings.Template.Vacation.title
        case .carPurchase: return L10n.Savings.Template.CarPurchase.title
        case .homePurchase: return L10n.Savings.Template.HomePurchase.title
        case .retirement: return L10n.Savings.Template.Retirement.title
        case .education: return L10n.Savings.Template.Education.title
        case .wedding: return L10n.Savings.Template.Wedding.title
        case .debtPayoff: return L10n.Savings.Template.DebtPayoff.title
        case .electronics: return L10n.Savings.Template.Electronics.title
        case .custom: return L10n.Savings.Template.Custom.title
        }
    }
    
    var icon: String {
        switch self {
        case .emergencyFund: return "cross.case.fill"
        case .vacation: return "airplane"
        case .carPurchase: return "car.fill"
        case .homePurchase: return "house.fill"
        case .retirement: return "figure.walk"
        case .education: return "graduationcap.fill"
        case .wedding: return "heart.fill"
        case .debtPayoff: return "creditcard.fill"
        case .electronics: return "laptopcomputer"
        case .custom: return "target"
        }
    }
    
    var suggestedColor: String {
        switch self {
        case .emergencyFund: return "#EF4444"  // Red
        case .vacation: return "#F59E0B"       // Amber
        case .carPurchase: return "#3B82F6"    // Blue
        case .homePurchase: return "#10B981"   // Green
        case .retirement: return "#8B5CF6"     // Purple
        case .education: return "#06B6D4"      // Cyan
        case .wedding: return "#EC4899"        // Pink
        case .debtPayoff: return "#F97316"     // Orange
        case .electronics: return "#6366F1"    // Indigo
        case .custom: return "#6B7280"         // Gray
        }
    }
    
    /// Suggested target amount (in USD, for reference)
    var suggestedAmount: Decimal? {
        switch self {
        case .emergencyFund: return 10000
        case .vacation: return 3000
        case .carPurchase: return 25000
        case .homePurchase: return 50000
        case .retirement: return 100000
        case .education: return 20000
        case .wedding: return 15000
        case .debtPayoff: return nil  // Varies
        case .electronics: return 2000
        case .custom: return nil
        }
    }
    
    var description: String {
        switch self {
        case .emergencyFund: return L10n.Savings.Template.EmergencyFund.desc
        case .vacation: return L10n.Savings.Template.Vacation.desc
        case .carPurchase: return L10n.Savings.Template.CarPurchase.desc
        case .homePurchase: return L10n.Savings.Template.HomePurchase.desc
        case .retirement: return L10n.Savings.Template.Retirement.desc
        case .education: return L10n.Savings.Template.Education.desc
        case .wedding: return L10n.Savings.Template.Wedding.desc
        case .debtPayoff: return L10n.Savings.Template.DebtPayoff.desc
        case .electronics: return L10n.Savings.Template.Electronics.desc
        case .custom: return L10n.Savings.Template.Custom.desc
        }
    }
}

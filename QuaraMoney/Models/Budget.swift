import SwiftData
import Foundation

@Model
final class Budget {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var deletedAt: Date?
    var needsSync: Bool = true

    // MARK: - Core Properties
    
    /// Budget name (optional, auto-generated if nil)
    var name: String?
    
    /// The budget limit amount (for fixed budgets)
    var amountLimit: Decimal
    
    /// Currency of the budget limit
    var currencyCode: String = "USD"

    /// Additive, lossless budget target discriminator for cloud compatibility.
    var targetKindRaw: String?

    /// Additive alert policy. Nil is interpreted from legacy toggles.
    var alertModeRaw: String?
    var lastAlertPeriodKey: String?

    /// Calendar weekday (1...7) used to derive weekly periods identically on every device.
    var weekStartDay: Int?
    
    // MARK: - Period Configuration (New)
    
    /// Type of budget period stored as raw value for SwiftData compatibility
    private var periodTypeRaw: String = "monthly"
    
    /// Type of budget period (weekly, monthly, etc.)
    var periodType: BudgetPeriodType {
        get { BudgetPeriodType(rawValue: periodTypeRaw) ?? .monthly }
        set { periodTypeRaw = newValue.rawValue }
    }
    
    /// Start date of the budget period
    var startDate: Date = Date()

    // Timestamps (for future sync readiness)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    /// End date for custom periods (nil for standard periods)
    var customEndDate: Date?
    
    // MARK: - Legacy Period (for migration)
    
    /// Legacy month field (1-12) - kept for backward compatibility
    var month: Int = 1
    
    /// Legacy year field - kept for backward compatibility  
    var year: Int = 2026
    
    // MARK: - Recurring Budget Support (New)
    
    /// Whether this budget auto-renews each period
    var isRecurring: Bool = false
    
    /// Whether to carry over unused budget to next period
    var rolloverExcess: Bool = false
    
    /// Accumulated rollover amount from previous periods
    var rolloverAmount: Decimal = 0
    
    // MARK: - Amount Type (New)
    
    /// How the budget amount is calculated (stored as JSON)
    /// Default is fixed amount for backward compatibility
    private var amountTypeData: Data?
    
    var amountType: BudgetAmountType {
        get {
            guard let data = amountTypeData else {
                return .fixed(amountLimit)
            }

            return BudgetAmountType.decode(from: data) ?? .fixed(amountLimit)
        }
        set {
            amountTypeData = newValue.encode()
            // Keep amountLimit in sync for fixed amounts
            if case .fixed(let amount) = newValue {
                amountLimit = amount
            }
        }
    }
    
    // MARK: - Alert Configuration (New)
    
    /// Alert at 50% spent
    var alertAt50: Bool = false
    
    /// Alert at 80% spent
    var alertAt80: Bool = true
    
    /// Alert at 100% spent
    var alertAt100: Bool = true
    
    /// Alert for projected overspend
    var alertOnProjectedOverspend: Bool = false
    
    /// Last time an alert was triggered (to prevent spam)
    var lastAlertTriggeredDate: Date?
    
    /// Highest alert threshold that has been triggered this period
    var lastAlertThreshold: Int = 0
    
    // MARK: - Budget Category Type (New)
    
    /// High-level category type stored as raw value for SwiftData compatibility
    private var budgetCategoryTypeRaw: String?
    
    /// High-level category type for template-based budgeting
    var budgetCategoryType: BudgetCategoryType? {
        get {
            guard let raw = budgetCategoryTypeRaw else { return nil }
            return BudgetCategoryType(rawValue: raw)
        }
        set { budgetCategoryTypeRaw = newValue?.rawValue }
    }
    
    // MARK: - Relationships
    
    /// Single category (nil = total/overall budget)
    @Relationship(deleteRule: .nullify) var category: Category?

    /// List of categories for this budget (New - replaces single category and group)
    @Relationship(deleteRule: .nullify) var categories: [Category]?
    
    // MARK: - Initialization
    
    /// Full initializer with all new options
    init(
        name: String? = nil,
        amountLimit: Decimal,
        currencyCode: String = "USD",
        periodType: BudgetPeriodType = .monthly,
        startDate: Date = Date(),
        customEndDate: Date? = nil,
        category: Category? = nil,

        isRecurring: Bool = false,
        rolloverExcess: Bool = false,
        alertAt50: Bool = false,
        alertAt80: Bool = true,
        alertAt100: Bool = true,
        budgetCategoryType: BudgetCategoryType? = nil,
        categories: [Category]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.amountLimit = amountLimit
        self.currencyCode = currencyCode
        self.periodTypeRaw = periodType.rawValue
        self.startDate = startDate
        self.customEndDate = customEndDate
        self.category = category
        self.isRecurring = isRecurring
        self.rolloverExcess = rolloverExcess
        self.rolloverAmount = 0
        self.alertAt50 = alertAt50
        self.alertAt80 = alertAt80
        self.alertAt100 = alertAt100
        self.budgetCategoryTypeRaw = budgetCategoryType?.rawValue
        self.categories = categories
        self.targetKindRaw = ((categories?.isEmpty == false) || category != nil)
            ? BudgetTargetKind.categories.rawValue : BudgetTargetKind.total.rawValue
        self.alertModeRaw = BudgetAlertMode.nearingOver.rawValue
        self.weekStartDay = periodType == .weekly ? Calendar.current.firstWeekday : nil
        
        // Set legacy fields from start date for compatibility
        let calendar = Calendar.current
        self.month = calendar.component(.month, from: startDate)
        self.year = calendar.component(.year, from: startDate)
        
        // Initialize amount type as fixed
        self.amountType = .fixed(amountLimit)
    }
    
    /// Legacy initializer for backward compatibility
    convenience init(amountLimit: Decimal, currencyCode: String = "USD", category: Category?, month: Int, year: Int) {
        // Convert legacy month/year to start date
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let startDate = Calendar.current.date(from: components) ?? Date()
        
        self.init(
            amountLimit: amountLimit,
            currencyCode: currencyCode,
            periodType: .monthly,
            startDate: startDate,
            category: category
        )
        
        // Preserve legacy fields
        self.month = month
        self.year = year
    }
    
    // MARK: - Computed Properties
    
    /// Display name for the budget
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        if let categories = categories, !categories.isEmpty {
            if categories.count == 1 {
                return categories.first?.displayName ?? "Budget"
            } else if categories.count == 2 {
                return "\(categories[0].displayName) & \(categories[1].displayName)"
            } else {
                return "\(categories[0].displayName) & \(categories.count - 1) others"
            }
        }
        if let category = category {
            return category.displayName
        }
        return "Total Budget"
    }
    
    /// Whether this is a total/overall budget (no specific category)
    var isTotalBudget: Bool {
        targetKind == .total
    }

    var targetKind: BudgetTargetKind {
        get {
            if let targetKindRaw, let value = BudgetTargetKind(rawValue: targetKindRaw) { return value }
            return ((categories?.isEmpty == false) || category != nil) ? .categories : .total
        }
        set { targetKindRaw = newValue.rawValue }
    }

    var alertMode: BudgetAlertMode {
        get {
            if let alertModeRaw, let value = BudgetAlertMode(rawValue: alertModeRaw) { return value }
            switch (alertAt80, alertAt100) {
            case (false, false): return .off
            case (true, false): return .nearing
            case (false, true): return .overOnly
            case (true, true): return .nearingOver
            }
        }
        set { alertModeRaw = newValue.rawValue }
    }
    

    
    /// The effective budget period date range
    var periodDateRange: (start: Date, end: Date) {
        periodDateRange(containing: Date())
    }

    func periodDateRange(containing date: Date, calendar baseCalendar: Calendar = .current) -> (start: Date, end: Date) {
        if periodType == .custom, let customEnd = customEndDate {
            let calendar = baseCalendar
            let start = calendar.startOfDay(for: startDate)
            let inclusiveEnd = calendar.startOfDay(for: customEnd)
            return (start, calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd)
        }
        var calendar = baseCalendar
        if periodType == .weekly, let weekStartDay { calendar.firstWeekday = weekStartDay }
        return periodType.currentPeriodRange(containing: date, calendar: calendar)
    }
    
    /// End date of the current period
    var endDate: Date {
        periodDateRange.end
    }
    
    /// Formatted period string for display
    var periodDisplayString: String {
        periodType.formatPeriod(startDate: startDate, endDate: customEndDate)
    }
    
    /// The effective budget limit including rollover
    var effectiveLimit: Decimal {
        amountLimit
    }
    
    /// Days remaining in the current budget period
    var daysRemaining: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: endDate)
        return max(0, calendar.dateComponents([.day], from: today, to: end).day ?? 0)
    }
    
    /// Total days in the budget period
    var totalDays: Int {
        periodType.totalDays(from: startDate)
    }
    
    /// Whether the budget period has ended
    var isPeriodEnded: Bool {
        Date() >= endDate
    }
    
    /// Whether the budget period is active (current)
    var isActive: Bool {
        if periodType != .custom { return true }
        let now = Date()
        return now >= startDate && now < endDate
    }

    var needsAttention: Bool {
        amountLimit <= 0 || (targetKind == .categories && trackedCategoryIds.isEmpty)
    }

    func periodKey(containing date: Date = Date(), calendar: Calendar = .current) -> String {
        if periodType == .custom { return id.uuidString }
        var calendar = calendar
        if periodType == .weekly, let weekStartDay { calendar.firstWeekday = weekStartDay }
        let start = periodType.currentPeriodRange(containing: date, calendar: calendar).start
        let year = calendar.component(.year, from: start)
        switch periodType {
        case .weekly, .biweekly:
            let week = calendar.component(.weekOfYear, from: start)
            return String(format: "%04d-W%02d", calendar.component(.yearForWeekOfYear, from: start), week)
        case .monthly: return String(format: "%04d-%02d", year, calendar.component(.month, from: start))
        case .quarterly: return "\(year)-Q\(((calendar.component(.month, from: start) - 1) / 3) + 1)"
        case .yearly: return String(format: "%04d", year)
        case .custom: return id.uuidString
        }
    }
    
    /// All category IDs this budget tracks (for filtering transactions)
    var trackedCategoryIds: [UUID] {
        if let categories = categories, !categories.isEmpty {
            return categories.filter { $0.deletedAt == nil }.map { $0.id }
        }
        if let category = category, category.deletedAt == nil {
            return [category.id]
        }
        return [] // Total budget tracks all
    }

    /// Category display info for filter chips
    var trackedCategoryInfos: [FilterCategoryInfo] {
        if let categories = categories, !categories.isEmpty {
            return categories.map { FilterCategoryInfo(id: $0.id, name: $0.displayName, icon: $0.icon, colorHex: $0.colorHex) }
        }
        if let category = category {
            return [FilterCategoryInfo(id: category.id, name: category.displayName, icon: category.icon, colorHex: category.colorHex)]
        }
        return []
    }

    // MARK: - Methods

    /// Persists one selected category through the dedicated to-one relationship.
    /// The to-many join is reserved for genuinely multi-category budgets so an
    /// existing one-item join cannot be reassigned when another budget selects
    /// the same category.
    func setTrackedCategories(_ selectedCategories: [Category], targetKind: BudgetTargetKind) {
        self.targetKind = targetKind
        guard targetKind == .categories else {
            category = nil
            categories = nil
            return
        }

        if selectedCategories.count == 1 {
            category = selectedCategories[0]
            categories = nil
        } else {
            category = nil
            categories = selectedCategories
        }
    }
    
    /// Calculate the effective limit for percentage-based budgets
    func calculateEffectiveLimit(income: Decimal) -> Decimal {
        let baseLimit = amountType.calculateLimit(income: income)
        return baseLimit + rolloverAmount
    }
    
    /// Check if an alert should be triggered for the given progress
    func shouldTriggerAlert(progress: Double) -> BudgetAlertType? {
        let progressPercent = Int(progress * 100)
        
        // Check thresholds in descending order
        if alertAt100 && progressPercent >= 100 && lastAlertThreshold < 100 {
            return .exceeded
        }
        if alertAt80 && progressPercent >= 80 && lastAlertThreshold < 80 {
            return .warning80
        }
        if alertAt50 && progressPercent >= 50 && lastAlertThreshold < 50 {
            return .info50
        }
        
        return nil
    }
    
    /// Mark that an alert was triggered
    func recordAlertTriggered(threshold: Int) {
        lastAlertTriggeredDate = Date()
        lastAlertThreshold = threshold
    }
    
    /// Reset alert tracking for new period
    func resetAlertTracking() {
        lastAlertTriggeredDate = nil
        lastAlertThreshold = 0
    }
    
    /// Rollover to next period (for recurring budgets)
    func rolloverToNextPeriod(unusedAmount: Decimal) {
        guard isRecurring else { return }
        
        // Update start date to next period
        startDate = periodType.nextPeriodStart(from: startDate)
        
        // Update legacy fields
        let calendar = Calendar.current
        month = calendar.component(.month, from: startDate)
        year = calendar.component(.year, from: startDate)
        
        // Handle rollover
        if rolloverExcess && unusedAmount > 0 {
            rolloverAmount += unusedAmount
        } else {
            rolloverAmount = 0
        }
        
        // Reset alert tracking
        resetAlertTracking()
    }

    // MARK: - Validation

    func validate() -> [ModelValidationError] {
        var errors: [ModelValidationError] = []
        if amountLimit < 0 { errors.append(.negativeOrZeroAmount(field: "Budget limit")) }
        if currencyCode.count != 3 { errors.append(.invalidCurrencyCode) }
        return errors
    }
}

enum BudgetTargetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case total, categories
    var id: String { rawValue }
}

enum BudgetAlertMode: String, Codable, CaseIterable, Identifiable {
    case off, nearing, overOnly, nearingOver
    var id: String { rawValue }
    var thresholds: [Int] {
        switch self {
        case .off: return []
        case .nearing: return [80]
        case .overOnly: return [100]
        case .nearingOver: return [80, 100]
        }
    }
}

// MARK: - Budget Alert Types

enum BudgetAlertType: String, CaseIterable, Codable {
    case info50 = "50% Spent"
    case warning80 = "80% Spent"
    case exceeded = "Budget Exceeded"
    case projectedOverspend = "Projected Overspend"
    
    var threshold: Int {
        switch self {
        case .info50: return 50
        case .warning80: return 80
        case .exceeded: return 100
        case .projectedOverspend: return 100
        }
    }
    
    var icon: String {
        switch self {
        case .info50: return "info.circle.fill"
        case .warning80: return "exclamationmark.triangle.fill"
        case .exceeded: return "xmark.circle.fill"
        case .projectedOverspend: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var color: String {
        switch self {
        case .info50: return "#3B82F6"      // Blue
        case .warning80: return "#F59E0B"   // Amber
        case .exceeded: return "#EF4444"    // Red
        case .projectedOverspend: return "#F97316" // Orange
        }
    }
    
    func message(budgetName: String) -> String {
        switch self {
        case .info50:
            return L10n.Alert.Budget.info50(budgetName)
        case .warning80:
            return L10n.Alert.Budget.warning80(budgetName)
        case .exceeded:
            return L10n.Alert.Budget.exceeded(budgetName)
        case .projectedOverspend:
            return L10n.Alert.Budget.projectedOverspend(budgetName)
        }
    }
}

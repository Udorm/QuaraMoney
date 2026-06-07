import Foundation

// MARK: - Codable conformance for the shared type filter

extension TransactionTypeFilter: Codable {}

// MARK: - Dashboard Filter

/// All filter dimensions for the Pro analytics dashboard, captured as plain `Sendable`
/// values so they can cross the actor boundary into `ProAnalyticsProcessor`.
///
/// Empty `walletIds` / `categoryIds` means "all". `minAmount` / `maxAmount` are expressed
/// in the user's preferred currency (the same currency every amount is converted to before
/// comparison). The period itself is owned separately by the view model.
struct DashboardFilter: Equatable, Sendable, Codable {
    var transactionType: TransactionTypeFilter = .expense
    var walletIds: Set<UUID> = []
    var categoryIds: Set<UUID> = []
    var minAmount: Decimal? = nil
    var maxAmount: Decimal? = nil
    /// When `true`, transactions flagged `excludeFromReports` are still counted.
    var includeExcluded: Bool = false

    static let `default` = DashboardFilter()

    /// Whether any dimension beyond the default transaction type is constraining the data.
    var hasActiveConstraints: Bool {
        !walletIds.isEmpty
            || !categoryIds.isEmpty
            || minAmount != nil
            || maxAmount != nil
            || includeExcluded
    }

    /// Number of distinct active constraints — drives the badge on the filter button.
    var activeConstraintCount: Int {
        var n = 0
        if !walletIds.isEmpty { n += 1 }
        if !categoryIds.isEmpty { n += 1 }
        if minAmount != nil || maxAmount != nil { n += 1 }
        if includeExcluded { n += 1 }
        return n
    }

    /// Clears every constraint while preserving the chosen transaction type.
    mutating func clearConstraints() {
        walletIds = []
        categoryIds = []
        minAmount = nil
        maxAmount = nil
        includeExcluded = false
    }
}

// MARK: - Dashboard Sections

/// Every configurable widget on the Pro dashboard. The raw value is the stable persistence key.
enum DashboardSection: String, CaseIterable, Identifiable, Codable, Sendable {
    case overview
    case cashFlow
    case netTrend
    case category
    case patterns
    case heatmap
    case merchants
    case insights

    var id: String { rawValue }

    /// Localized title shown in the customize sheet.
    var title: String {
        switch self {
        case .overview:  return "analysis.pro.section.overview".localized
        case .cashFlow:  return "analysis.pro.cashFlow".localized
        case .netTrend:  return "analysis.pro.netTrend".localized
        case .category:  return "analysis.pro.section.category".localized
        case .patterns:  return "analysis.pro.weekdayPattern".localized
        case .heatmap:   return "analysis.pro.heatmap".localized
        case .merchants: return "analysis.pro.topPlaces".localized
        case .insights:  return "analysis.pro.insights".localized
        }
    }

    var systemImage: String {
        switch self {
        case .overview:  return "rectangle.3.group.fill"
        case .cashFlow:  return "arrow.left.arrow.right"
        case .netTrend:  return "chart.xyaxis.line"
        case .category:  return "chart.pie.fill"
        case .patterns:  return "calendar"
        case .heatmap:   return "square.grid.3x3.fill"
        case .merchants: return "mappin.and.ellipse"
        case .insights:  return "sparkles"
        }
    }
}

// MARK: - Dashboard Layout

/// Which sections are visible and in what order. Persisted as JSON in `UserDefaults`.
struct DashboardLayout: Equatable, Codable, Sendable {
    /// Full ordering of every known section (visible + hidden).
    var order: [DashboardSection]
    /// Sections the user has switched off.
    var hidden: Set<DashboardSection>

    static let `default` = DashboardLayout(order: DashboardSection.allCases, hidden: [])

    /// Sections to render, in user order, excluding hidden ones.
    var visibleSections: [DashboardSection] {
        order.filter { !hidden.contains($0) }
    }

    var isDefault: Bool { self == .default }

    /// Repairs a decoded layout so newly-shipped sections always appear (appended, visible)
    /// and stale raw values are dropped. Keeps the user's ordering for everything else.
    mutating func reconcileWithKnownSections() {
        let known = Set(DashboardSection.allCases)
        order = order.filter { known.contains($0) }
        let present = Set(order)
        for section in DashboardSection.allCases where !present.contains(section) {
            order.append(section)
        }
        hidden = hidden.intersection(known)
    }
}

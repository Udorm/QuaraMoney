import SwiftUI
import SwiftData

struct EditBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var budget: Budget
    
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \CategoryGroup.name) private var categoryGroups: [CategoryGroup]
    @Query(sort: \SavingsGoal.name) private var savingsGoals: [SavingsGoal]
    
    // MARK: - Form State (initialized from budget)
    
    @State private var budgetName: String = ""
    @State private var amountString: String = ""
    @State private var selectedCurrency: String = ""
    
    // Target selection
    @State private var targetType: BudgetTargetType = .category
    @State private var selectedCategory: Category?
    @State private var selectedCategoryGroup: CategoryGroup?
    
    // Period configuration
    @State private var periodType: BudgetPeriodType = .monthly
    @State private var startDate: Date = Date()
    @State private var customEndDate: Date = Date()
    
    // Recurring options
    @State private var isRecurring: Bool = false
    @State private var rolloverExcess: Bool = false
    
    // Amount type
    @State private var usePercentage: Bool = false
    @State private var percentageValue: Double = 30
    
    // Alert settings
    @State private var alertAt50: Bool = false
    @State private var alertAt80: Bool = true
    @State private var alertAt100: Bool = true
    
    // Savings goal
    @State private var linkSavingsGoal: Bool = false
    @State private var selectedSavingsGoal: SavingsGoal?
    
    // Budget category type
    @State private var budgetCategoryType: BudgetCategoryType?
    
    // UI State
    @State private var showAdvancedOptions: Bool = false
    
    init(budget: Budget) {
        self.budget = budget
        
        // Initialize state from budget
        _budgetName = State(initialValue: budget.name ?? "")
        _amountString = State(initialValue: "\(budget.amountLimit)")
        _selectedCurrency = State(initialValue: budget.currencyCode)
        
        // Target type
        if budget.category != nil {
            _targetType = State(initialValue: .category)
            _selectedCategory = State(initialValue: budget.category)
        } else if budget.categoryGroup != nil {
            _targetType = State(initialValue: .categoryGroup)
            _selectedCategoryGroup = State(initialValue: budget.categoryGroup)
        } else {
            _targetType = State(initialValue: .total)
        }
        
        // Period
        _periodType = State(initialValue: budget.periodType)
        _startDate = State(initialValue: budget.startDate)
        _customEndDate = State(initialValue: budget.customEndDate ?? budget.endDate)
        
        // Recurring
        _isRecurring = State(initialValue: budget.isRecurring)
        _rolloverExcess = State(initialValue: budget.rolloverExcess)
        
        // Amount type
        if case .percentOfIncome(let percent) = budget.amountType {
            _usePercentage = State(initialValue: true)
            _percentageValue = State(initialValue: percent * 100)
        }
        
        // Alerts
        _alertAt50 = State(initialValue: budget.alertAt50)
        _alertAt80 = State(initialValue: budget.alertAt80)
        _alertAt100 = State(initialValue: budget.alertAt100)
        
        // Savings goal
        _linkSavingsGoal = State(initialValue: budget.savingsGoal != nil)
        _selectedSavingsGoal = State(initialValue: budget.savingsGoal)
        
        // Category type
        _budgetCategoryType = State(initialValue: budget.budgetCategoryType)
    }
    
    private var isFormValid: Bool {
        let hasTarget = targetType == .total || selectedCategory != nil || selectedCategoryGroup != nil
        let hasAmount = !amountString.isEmpty || usePercentage
        return hasTarget && hasAmount
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Budget Name
                Section {
                    TextField(L10n.Budget.nameOptional, text: $budgetName)
                } header: {
                    Text(L10n.Budget.name)
                } footer: {
                    Text(L10n.Budget.nameHint)
                }
                
                // MARK: - Target Selection
                Section(L10n.Budget.whatToBudget) {
                    Picker(L10n.Budget.Target.type, selection: $targetType) {
                        ForEach(BudgetTargetType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    switch targetType {
                    case .category:
                        if categories.isEmpty {
                            Text(L10n.Category.noAvailable)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(L10n.Budget.category, selection: $selectedCategory) {
                                Text(L10n.Category.select).tag(nil as Category?)
                                ForEach(categories.filter { $0.type == .expense }) { category in
                                    Label(category.name, systemImage: category.icon)
                                        .tag(category as Category?)
                                }
                            }
                        }
                        
                    case .categoryGroup:
                        if categoryGroups.isEmpty {
                            Text(L10n.CategoryGroup.noAvailable)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(L10n.CategoryGroup.select, selection: $selectedCategoryGroup) {
                                Text(L10n.CategoryGroup.select).tag(nil as CategoryGroup?)
                                ForEach(categoryGroups) { group in
                                    Label(group.name, systemImage: group.iconName)
                                        .tag(group as CategoryGroup?)
                                }
                            }
                        }
                        
                    case .total:
                        HStack {
                            Image(systemName: "sum")
                                .foregroundStyle(.blue)
                            Text(L10n.Budget.allExpenses)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: - Budget Amount
                Section(L10n.Budget.limit) {
                    Toggle(L10n.Budget.usePercentage, isOn: $usePercentage)
                    
                    if usePercentage {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(Int(percentageValue))%")
                                    .font(.app(.title2, weight: .bold))
                                    .monospacedDigit()
                                Spacer()
                                Text(L10n.Budget.ofIncome)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(value: $percentageValue, in: 5...100, step: 5)
                                .tint(.blue)
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            TextField(L10n.Transaction.amount, text: $amountString)
                                .keyboardType(.decimalPad)
                            
                            Picker("", selection: $selectedCurrency) {
                                ForEach(CurrencyManager.shared.availableCurrencies, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 80)
                        }
                    }
                }
                
                // MARK: - Period Configuration
                Section(L10n.Budget.periodType) {
                    Picker(L10n.Budget.periodType, selection: $periodType) {
                        ForEach(BudgetPeriodType.allCases) { period in
                            Label(period.displayName, systemImage: period.icon)
                                .tag(period)
                        }
                    }
                    
                    DatePicker(
                        L10n.Budget.startDate,
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    
                    if periodType == .custom {
                        DatePicker(
                            L10n.Budget.endDate,
                            selection: $customEndDate,
                            in: startDate...,
                            displayedComponents: .date
                        )
                    } else {
                        HStack {
                            Text(L10n.Budget.endDate)
                            Spacer()
                            Text(periodType.dateRange(from: startDate).end.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: - Recurring Options
                Section {
                    Toggle(L10n.Budget.recurring, isOn: $isRecurring)
                    
                    if isRecurring {
                        Toggle(L10n.Budget.rollover, isOn: $rolloverExcess)
                    }
                } header: {
                    Text(L10n.Budget.recurring)
                } footer: {
                    if isRecurring {
                        Text(rolloverExcess 
                             ? L10n.Budget.rolloverDescription
                             : L10n.Budget.resetDescription)
                    }
                }
                
                // MARK: - Advanced Options
                DisclosureGroup(L10n.Common.advancedOptions, isExpanded: $showAdvancedOptions) {
                    // Alert Settings
                    Section {
                        Toggle(L10n.Budget.alertAt(50), isOn: $alertAt50)
                        Toggle(L10n.Budget.alertAt(80), isOn: $alertAt80)
                        Toggle(L10n.Budget.alertAt(100), isOn: $alertAt100)
                    } header: {
                        Label(L10n.Budget.notifications, systemImage: "bell.fill")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Budget Category Type
                    Picker(L10n.Budget.category, selection: $budgetCategoryType) {
                        Text(L10n.CategoryGroup.none).tag(nil as BudgetCategoryType?)
                        ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as BudgetCategoryType?)
                        }
                    }
                    
                    // Savings Goal Link
                    if !savingsGoals.isEmpty {
                        Toggle(L10n.Budget.linkSavings, isOn: $linkSavingsGoal)
                        
                        if linkSavingsGoal {
                            Picker(L10n.Savings.selectGoal, selection: $selectedSavingsGoal) {
                                Text(L10n.Savings.selectGoal).tag(nil as SavingsGoal?)
                                ForEach(savingsGoals.filter { !$0.isCompleted }) { goal in
                                    Label(goal.name, systemImage: goal.iconName)
                                        .tag(goal as SavingsGoal?)
                                }
                            }
                        }
                    }
                }
                
                // MARK: - Current Status (Read-only info)
                if budget.rolloverAmount > 0 {
                    Section(L10n.Budget.currentPeriod) {
                        HStack {
                            Text(L10n.Budget.rolloverAmountLabel)
                            Spacer()
                            Text(budget.rolloverAmount.formatted(.currency(code: budget.currencyCode)))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle(L10n.Budget.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        saveBudget()
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }
    
    // MARK: - Save Budget
    
    private func saveBudget() {
        // Update basic properties
        budget.name = budgetName.isEmpty ? nil : budgetName
        budget.currencyCode = selectedCurrency
        
        // Update target
        switch targetType {
        case .category:
            budget.category = selectedCategory
            budget.categoryGroup = nil
        case .categoryGroup:
            budget.category = nil
            budget.categoryGroup = selectedCategoryGroup
        case .total:
            budget.category = nil
            budget.categoryGroup = nil
        }
        
        // Update period
        budget.periodType = periodType
        budget.startDate = startDate
        budget.customEndDate = periodType == .custom ? customEndDate : nil
        
        // Update legacy fields
        let calendar = Calendar.current
        budget.month = calendar.component(.month, from: startDate)
        budget.year = calendar.component(.year, from: startDate)
        
        // Update recurring
        budget.isRecurring = isRecurring
        budget.rolloverExcess = rolloverExcess
        
        // Update amount
        if usePercentage {
            budget.amountType = .percentOfIncome(percentageValue / 100.0)
            budget.amountLimit = 0 // Will be calculated dynamically
        } else if let amount = Decimal(string: amountString) {
            budget.amountType = .fixed(amount)
            budget.amountLimit = amount
        }
        
        // Update alerts
        budget.alertAt50 = alertAt50
        budget.alertAt80 = alertAt80
        budget.alertAt100 = alertAt100
        
        // Update category type
        budget.budgetCategoryType = budgetCategoryType
        
        // Update savings goal
        if linkSavingsGoal {
            budget.savingsGoal = selectedSavingsGoal
        } else {
            budget.savingsGoal = nil
        }
    }
}

#Preview {
    @Previewable @State var budget = Budget(amountLimit: 500, currencyCode: "USD", category: nil, month: 2, year: 2026)
    
    EditBudgetView(budget: budget)
        .modelContainer(for: [Budget.self, Category.self, CategoryGroup.self, SavingsGoal.self], inMemory: true)
}

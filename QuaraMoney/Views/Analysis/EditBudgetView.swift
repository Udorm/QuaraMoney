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
                    TextField("Budget Name (Optional)", text: $budgetName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Leave empty to use the category name")
                }
                
                // MARK: - Target Selection
                Section("What to Budget") {
                    Picker("Budget Type", selection: $targetType) {
                        ForEach(BudgetTargetType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    switch targetType {
                    case .category:
                        if categories.isEmpty {
                            Text("No categories available")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Category", selection: $selectedCategory) {
                                Text("Select Category").tag(nil as Category?)
                                ForEach(categories.filter { $0.type == .expense }) { category in
                                    Label(category.name, systemImage: category.icon)
                                        .tag(category as Category?)
                                }
                            }
                        }
                        
                    case .categoryGroup:
                        if categoryGroups.isEmpty {
                            Text("No category groups available")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Category Group", selection: $selectedCategoryGroup) {
                                Text("Select Group").tag(nil as CategoryGroup?)
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
                            Text("Budget for all expenses")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: - Budget Amount
                Section("Budget Limit") {
                    Toggle("Use Percentage of Income", isOn: $usePercentage)
                    
                    if usePercentage {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("\(Int(percentageValue))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                Spacer()
                                Text("of monthly income")
                                    .foregroundStyle(.secondary)
                            }
                            
                            Slider(value: $percentageValue, in: 5...100, step: 5)
                                .tint(.blue)
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            TextField("Amount", text: $amountString)
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
                Section("Budget Period") {
                    Picker("Period Type", selection: $periodType) {
                        ForEach(BudgetPeriodType.allCases) { period in
                            Label(period.displayName, systemImage: period.icon)
                                .tag(period)
                        }
                    }
                    
                    DatePicker(
                        "Start Date",
                        selection: $startDate,
                        displayedComponents: .date
                    )
                    
                    if periodType == .custom {
                        DatePicker(
                            "End Date",
                            selection: $customEndDate,
                            in: startDate...,
                            displayedComponents: .date
                        )
                    } else {
                        HStack {
                            Text("End Date")
                            Spacer()
                            Text(periodType.dateRange(from: startDate).end.formatted(date: .abbreviated, time: .omitted))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // MARK: - Recurring Options
                Section {
                    Toggle("Recurring Budget", isOn: $isRecurring)
                    
                    if isRecurring {
                        Toggle("Rollover Unused Amount", isOn: $rolloverExcess)
                    }
                } header: {
                    Text("Recurring")
                } footer: {
                    if isRecurring {
                        Text(rolloverExcess 
                             ? "Unused budget will carry over to the next period"
                             : "Budget resets to the limit each period")
                    }
                }
                
                // MARK: - Advanced Options
                DisclosureGroup("Advanced Options", isExpanded: $showAdvancedOptions) {
                    // Alert Settings
                    Section {
                        Toggle("Alert at 50%", isOn: $alertAt50)
                        Toggle("Alert at 80%", isOn: $alertAt80)
                        Toggle("Alert at 100%", isOn: $alertAt100)
                    } header: {
                        Label("Notifications", systemImage: "bell.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Budget Category Type
                    Picker("Budget Category", selection: $budgetCategoryType) {
                        Text("None").tag(nil as BudgetCategoryType?)
                        ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as BudgetCategoryType?)
                        }
                    }
                    
                    // Savings Goal Link
                    if !savingsGoals.isEmpty {
                        Toggle("Link to Savings Goal", isOn: $linkSavingsGoal)
                        
                        if linkSavingsGoal {
                            Picker("Savings Goal", selection: $selectedSavingsGoal) {
                                Text("Select Goal").tag(nil as SavingsGoal?)
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
                    Section("Current Period") {
                        HStack {
                            Text("Rollover Amount")
                            Spacer()
                            Text(budget.rolloverAmount.formatted(.currency(code: budget.currencyCode)))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle("Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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

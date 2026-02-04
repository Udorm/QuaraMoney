import SwiftUI
import SwiftData

struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \CategoryGroup.name) private var categoryGroups: [CategoryGroup]
    @Query(sort: \SavingsGoal.name) private var savingsGoals: [SavingsGoal]
    
    // MARK: - Form State
    
    @State private var budgetName: String = ""
    @State private var amountString: String = ""
    @State private var selectedCurrency: String = CurrencyManager.shared.preferredCurrencyCode
    
    // Target selection
    @State private var targetType: BudgetTargetType = .category
    @State private var selectedCategory: Category?
    @State private var selectedCategoryGroup: CategoryGroup?
    
    // Period configuration
    @State private var periodType: BudgetPeriodType = .monthly
    @State private var startDate: Date = Date()
    @State private var customEndDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    
    // Recurring options
    @State private var isRecurring: Bool = true
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
    
    // Budget category type (for templates)
    @State private var budgetCategoryType: BudgetCategoryType?
    
    // UI State
    @State private var showAdvancedOptions: Bool = false
    
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
                            Button("Create Category Group") {
                                // TODO: Navigate to create group
                            }
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
                            
                            // Quick presets
                            HStack(spacing: 8) {
                                ForEach([10, 20, 30, 50], id: \.self) { percent in
                                    Button("\(percent)%") {
                                        percentageValue = Double(percent)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(percentageValue == Double(percent) ? .blue : .gray)
                                }
                            }
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
            }
            .navigationTitle("New Budget")
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
        // Determine the amount
        let amount: Decimal
        if usePercentage {
            // For percentage, store a placeholder; actual limit calculated dynamically
            amount = 0
        } else {
            guard let parsedAmount = Decimal(string: amountString) else { return }
            amount = parsedAmount
        }
        
        // Create the budget
        let budget = Budget(
            name: budgetName.isEmpty ? nil : budgetName,
            amountLimit: usePercentage ? 0 : amount,
            currencyCode: selectedCurrency,
            periodType: periodType,
            startDate: startDate,
            customEndDate: periodType == .custom ? customEndDate : nil,
            category: targetType == .category ? selectedCategory : nil,
            categoryGroup: targetType == .categoryGroup ? selectedCategoryGroup : nil,
            isRecurring: isRecurring,
            rolloverExcess: rolloverExcess,
            alertAt50: alertAt50,
            alertAt80: alertAt80,
            alertAt100: alertAt100,
            budgetCategoryType: budgetCategoryType
        )
        
        // Set amount type
        if usePercentage {
            budget.amountType = .percentOfIncome(percentageValue / 100.0)
        } else {
            budget.amountType = .fixed(amount)
        }
        
        // Link savings goal if selected
        if linkSavingsGoal, let goal = selectedSavingsGoal {
            budget.savingsGoal = goal
        }
        
        modelContext.insert(budget)
    }
}

// MARK: - Budget Target Type

enum BudgetTargetType: String, CaseIterable, Identifiable {
    case category
    case categoryGroup
    case total
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .category: return "Single Category"
        case .categoryGroup: return "Category Group"
        case .total: return "Total Spending"
        }
    }
    
    var icon: String {
        switch self {
        case .category: return "folder"
        case .categoryGroup: return "folder.fill.badge.gearshape"
        case .total: return "sum"
        }
    }
}

#Preview {
    AddBudgetView()
        .modelContainer(for: [Budget.self, Category.self, CategoryGroup.self, SavingsGoal.self], inMemory: true)
}

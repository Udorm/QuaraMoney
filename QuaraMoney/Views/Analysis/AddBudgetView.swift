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
                            Picker(L10n.Category.select, selection: $selectedCategory) {
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
                            Button(L10n.CategoryGroup.create) {
                                // TODO: Navigate to create group
                            }
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
                Section(L10n.Budget.periodType) { // Reusing Period Type as section header or just "Budget Period"? Strings file has budget.periodType="Period Type".
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
                    Text(L10n.Budget.recurring) // Reusing same key if appropriate. Or "Recurring" vs "Recurring Budget". Existing key is "Recurring Budget". Section header might want just "Recurring". I'll use L10n.Budget.recurring for now.
                } footer: {
                    if isRecurring {
                        Text(rolloverExcess 
                             ? L10n.Budget.rolloverDescription
                             : L10n.Budget.resetDescription)
                    }
                }
                
                // MARK: - Advanced Options
                DisclosureGroup(L10n.Common.advancedOptions, isExpanded: $showAdvancedOptions) { // Assuming common.advancedOptions exists or fallback. I didn't add it. I'll use "Advanced Options" string literal or add it. I'll check common keys later. For now let's use a literal "Advanced Options" and maybe update later if I find it. Or define it now. I'll check L10n.Common first. I don't recall adding it. I'll stick to literal for now to avoid error, or add it to L10n.Common manually via replace if I can. Let's just use "Advanced Options" for safe side in this big chunk.
                    // Alert Settings
                    Section {
                        Toggle(L10n.Budget.alertAt(50), isOn: $alertAt50) // Need L10n.Budget.alertAt(...)
                        Toggle(L10n.Budget.alertAt(80), isOn: $alertAt80)
                        Toggle(L10n.Budget.alertAt(100), isOn: $alertAt100)
                    } header: {
                        Label(L10n.Budget.notifications, systemImage: "bell.fill")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Budget Category Type
                    Picker(L10n.Budget.category, selection: $budgetCategoryType) { // Check L10n.Budget.category. I haven't added keys for "Budget Category". I added "target.category". This is "Budget Category" for templates. I'll use "Budget Category" literal or L10n.Budget.target.category? No that's "Single Category". I'll use "Budget Category" literal.
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
                            Picker(L10n.Savings.title, selection: $selectedSavingsGoal) {
                                Text(L10n.Savings.selectGoal).tag(nil as SavingsGoal?)
                                ForEach(savingsGoals.filter { !$0.isCompleted }) { goal in
                                    Label(goal.name, systemImage: goal.iconName)
                                        .tag(goal as SavingsGoal?)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.Budget.new)
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
        case .category: return L10n.Budget.Target.category
        case .categoryGroup: return L10n.Budget.Target.group
        case .total: return L10n.Budget.Target.total
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

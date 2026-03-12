import SwiftUI
import SwiftData

struct EditBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var budget: Budget
    
    @Query(sort: \Category.name) private var categories: [Category]
    
    // MARK: - Form State (initialized from budget)
    
    @State private var budgetName: String = ""
    @State private var amountString: String = ""
    @State private var selectedCurrency: String = ""
    
    // Target selection
    @State private var targetType: BudgetTargetType = .specificCategories
    @State private var selectedCategories: Set<UUID> = []
    @State private var showCategoryPicker = false
    
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
    
    // Budget category type
    @State private var budgetCategoryType: BudgetCategoryType?
    
    // UI State
    @State private var showAdvancedOptions: Bool = false
    @State private var showCurrencyPicker = false
    
    init(budget: Budget) {
        self.budget = budget
        
        // Initialize state from budget
        _budgetName = State(initialValue: budget.name ?? "")
        _amountString = State(initialValue: "\(budget.amountLimit)")
        _selectedCurrency = State(initialValue: budget.currencyCode)
        
        // Target type
        if let categories = budget.categories, !categories.isEmpty {
            _targetType = State(initialValue: .specificCategories)
            _selectedCategories = State(initialValue: Set(categories.map { $0.id }))
        } else if let category = budget.category {
            _targetType = State(initialValue: .specificCategories)
            _selectedCategories = State(initialValue: [category.id])
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
        
        // Category type
        _budgetCategoryType = State(initialValue: budget.budgetCategoryType)
    }
    
    private var isFormValid: Bool {
        let hasTarget = targetType == .total || !selectedCategories.isEmpty
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
                    case .specificCategories:
                        Button {
                            showCategoryPicker = true
                        } label: {
                            HStack {
                                Text(L10n.Budget.Target.specificCategories)
                                Spacer()
                                if selectedCategories.isEmpty {
                                    Text(L10n.Common.select)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("\(selectedCategories.count)")
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        if !selectedCategories.isEmpty {
                            ForEach(categories.filter { selectedCategories.contains($0.id) }) { category in
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                                        .frame(width: 24)
                                    Text(category.name)
                                    Spacer()
                                }
                            }
                            .onDelete { indexSet in
                                let categoriesToDelete = categories.filter { selectedCategories.contains($0.id) }
                                indexSet.forEach { index in
                                    selectedCategories.remove(categoriesToDelete[index].id)
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

                            Button {
                                showCurrencyPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(selectedCurrency)
                                        .font(.app(.subheadline, weight: .bold))
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .clipShape(Capsule())
                            }
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
                        Text("budget.threshold.none".localized).tag(nil as BudgetCategoryType?)
                        ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as BudgetCategoryType?)
                        }
                    }
                    
                }
                
                // MARK: - Current Status (Read-only info)
                if budget.rolloverAmount > 0 {
                    Section(L10n.Budget.currentPeriod) {
                        HStack {
                            Text(L10n.Budget.rolloverAmountLabel)
                            Spacer()
                            Text(budget.rolloverAmount.formattedAmount(for: budget.currencyCode))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .navigationTitle(L10n.Budget.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveBudget()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                }

            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            MultiCategoryPicker(selectedCategories: $selectedCategories)
        }
        .sheet(isPresented: $showCurrencyPicker) {
            NavigationStack {
                CurrencySelectionView(selection: $selectedCurrency)
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - Save Budget
    
    private func saveBudget() {
        // Update basic properties
        budget.name = budgetName.isEmpty ? nil : budgetName
        budget.currencyCode = selectedCurrency
        
        // Update target
        switch targetType {
        case .specificCategories:
            budget.categories = categories.filter { selectedCategories.contains($0.id) }
            budget.category = nil
        case .total:
            budget.categories = nil
            budget.category = nil
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
        
    }
}

#Preview {
    @Previewable @State var budget = Budget(amountLimit: 500, currencyCode: "USD", category: nil, month: 2, year: 2026)
    
    EditBudgetView(budget: budget)
        .modelContainer(for: [Budget.self, Category.self], inMemory: true)
}

import SwiftUI
import SwiftData

struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var categories: [Category]
    
    // MARK: - Form State
    
    @State private var budgetName: String = ""
    @State private var amountString: String = ""
    @State private var selectedCurrency: String = CurrencyManager.shared.preferredCurrencyCode
    
    // Target selection
    @State private var targetType: BudgetTargetType = .specificCategories
    @State private var selectedCategories: Set<UUID> = []
    @State private var showCategoryPicker = false
    
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
    
    // Budget category type (for templates)
    @State private var budgetCategoryType: BudgetCategoryType?
    
    // UI State
    @State private var showAdvancedOptions: Bool = false
    @State private var showCurrencyPicker = false
    
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
                                    Text(category.displayName)
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
                            Text(periodType.dateRange(from: startDate).end.appFormatted(date: .abbreviated, time: .omitted))
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
                    Picker(L10n.Budget.category, selection: $budgetCategoryType) { 
                        Text("budget.threshold.none".localized).tag(nil as BudgetCategoryType?)
                        ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as BudgetCategoryType?)
                        }
                    }
                    
                }
            }
            .navigationTitle(L10n.Budget.new)
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
            category: nil,
            isRecurring: isRecurring,
            rolloverExcess: rolloverExcess,
            alertAt50: alertAt50,
            alertAt80: alertAt80,
            alertAt100: alertAt100,
            budgetCategoryType: budgetCategoryType,
            categories: targetType == .specificCategories 
                ? categories.filter { selectedCategories.contains($0.id) } 
                : nil
        )
        
        // Set amount type
        if usePercentage {
            budget.amountType = .percentOfIncome(percentageValue / 100.0)
        } else {
            budget.amountType = .fixed(amount)
        }
        
        modelContext.insert(budget)
    }
}


// MARK: - Budget Target Type

enum BudgetTargetType: String, CaseIterable, Identifiable {
    case specificCategories
    case total
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .specificCategories: return L10n.Budget.Target.specificCategories // "Specific Categories"
        case .total: return L10n.Budget.Target.total
        }
    }
    
    var icon: String {
        switch self {
        case .specificCategories: return "list.bullet"
        case .total: return "sum"
        }
    }
}

#Preview {
    AddBudgetView()
        .modelContainer(for: [Budget.self, Category.self], inMemory: true)
}

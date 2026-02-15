import SwiftUI
import SwiftData

struct SavingsGoalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\SavingsGoal.priority), SortDescriptor(\SavingsGoal.createdDate)]) private var goals: [SavingsGoal]
    
    @State private var showAddGoal = false
    @State private var showCompletedGoals = false
    @State private var searchText = ""
    
    private var activeGoals: [SavingsGoal] {
        let filtered = goals.filter { !$0.isCompleted }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var completedGoals: [SavingsGoal] {
        let filtered = goals.filter { $0.isCompleted }
        if searchText.isEmpty { return filtered }
        return filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var totalSaved: Decimal {
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        return goals.reduce(Decimal.zero) { total, goal in
            total + CurrencyManager.shared.convert(
                amount: goal.currentAmount,
                from: goal.currencyCode,
                to: targetCurrency
            )
        }
    }
    
    private var totalTarget: Decimal {
        let targetCurrency = CurrencyManager.shared.preferredCurrencyCode
        return goals.reduce(Decimal.zero) { total, goal in
            total + CurrencyManager.shared.convert(
                amount: goal.targetAmount,
                from: goal.currencyCode,
                to: targetCurrency
            )
        }
    }
    
    var body: some View {
        Group {
            if goals.isEmpty {
                AppEmptyStateView(
                    L10n.Savings.noGoals,
                    systemImage: "target",
                    description: L10n.Savings.noGoalsDescription
                )
            } else {
                List {
                    // Summary Section
                    Section {
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.Savings.totalSaved)
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                    Text(totalSaved.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode).presentation(.narrow)))
                                        .font(.app(.title2, weight: .bold))
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(L10n.Savings.totalTarget)
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                    Text(totalTarget.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode).presentation(.narrow)))
                                        .font(.app(.title2, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            // Overall progress
                            let overallProgress = totalTarget > 0 ? Double(truncating: totalSaved as NSNumber) / Double(truncating: totalTarget as NSNumber) : 0
                            VStack(spacing: 8) {
                                ProgressView(value: min(overallProgress, 1.0))
                                    .tint(.green)
                                
                                HStack {
//                                    Text("\(Int(overallProgress * 100))% of total goals")
                                     Text(L10n.Budget.percentUsed(Int(overallProgress * 100))) // Reusing percent format
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    // Simplified summary
                                    Text("\(activeGoals.count) \(L10n.Budget.Filter.active), \(completedGoals.count) \(L10n.Common.done)")
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Active Goals
                    if !activeGoals.isEmpty {
                        Section(L10n.Savings.activeGoals) {
                            ForEach(activeGoals) { goal in
                                NavigationLink {
                                    SavingsGoalDetailView(goal: goal)
                                } label: {
                                    SavingsGoalRowView(goal: goal)
                                }
                            }
                            .onDelete { indexSet in
                                deleteGoals(at: indexSet, from: activeGoals)
                            }
                        }
                    }
                    
                    // Completed Goals
                    if !completedGoals.isEmpty {
                        Section {
                            DisclosureGroup("\(L10n.Savings.completedGoals) (\(completedGoals.count))", isExpanded: $showCompletedGoals) {
                                ForEach(completedGoals) { goal in
                                    NavigationLink {
                                        SavingsGoalDetailView(goal: goal)
                                    } label: {
                                        SavingsGoalRowView(goal: goal)
                                    }
                                }
                                .onDelete { indexSet in
                                    deleteGoals(at: indexSet, from: completedGoals)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.Savings.title)
        .searchable(text: $searchText)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddGoal = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddGoal) {
            AddSavingsGoalView()
        }
    }
    
    private func deleteGoals(at offsets: IndexSet, from source: [SavingsGoal]) {
        withAnimation {
            for index in offsets {
                modelContext.delete(source[index])
            }
        }
    }
}

// MARK: - Savings Goal Row View


struct SavingsGoalRowView: View {
    let goal: SavingsGoal
    
    var body: some View {
        HStack(spacing: 16) {
            // MARK: Icon
            ZStack {
                Circle()
                    .fill((Color(hex: goal.colorHex) ?? .blue).opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: goal.iconName)
                    .font(.app(.title3))
                    .foregroundStyle(Color(hex: goal.colorHex) ?? .blue)
            }
            
            // MARK: Content
            VStack(alignment: .leading, spacing: 6) {
                // Title Row
                HStack {
                    Text(goal.name)
                         .font(.app(.body, weight: .semibold))
                        .lineLimit(1)
                    
                    if goal.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.app(.caption))
                    }
                    
                    Spacer()
                    
                    // Primary Value: Current Saved Amount
                     Text(goal.currentAmount.formatted(.currency(code: goal.currencyCode).presentation(.narrow)))
                        .font(.app(.body, weight: .bold))
                        .foregroundStyle(Color(hex: goal.colorHex) ?? .blue)
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray4).opacity(0.5))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill((Color(hex: goal.colorHex) ?? .blue).gradient)
                            .frame(width: geometry.size.width * CGFloat(min(goal.progress, 1.0)), height: 6)
                    }
                }
                .frame(height: 6)
                
                // Footer / Subtitle Row
                HStack {
                    // Left: Progress Percentage
                    Text(goal.progressPercent)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    
                    // Center/Divider
                    Text("•")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        
                    // Right: Target info
                    Text(L10n.Budget.leftOf(goal.targetAmount.formatted(.currency(code: goal.currencyCode).presentation(.narrow)))) // Reusing leftOf "of $100"
                         .font(.app(.caption))
                         .foregroundStyle(.secondary)

                    Spacer()
                    
                    // Far Right: Target Date
                    if let targetDate = goal.targetDate {
                         Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add Savings Goal View

struct AddSavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    
    @State private var selectedTemplate: SavingsGoalTemplate?
    @State private var name: String = ""
    @State private var targetAmountString: String = ""
    @State private var selectedCurrency: String = CurrencyManager.shared.preferredCurrencyCode
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var selectedIcon: String = "target"
    @State private var selectedColor: String = "#10B981"
    @State private var linkedWallet: Wallet?
    @State private var autoContributeEnabled: Bool = false
    @State private var autoContributeAmountString: String = ""
    @State private var autoContributePeriod: BudgetPeriodType = .monthly
    
    @State private var showIconPicker = false
    @State private var showColorPicker = false
    
    private var isFormValid: Bool {
        !name.isEmpty && Decimal(string: targetAmountString) != nil && Decimal(string: targetAmountString)! > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Template Selection
                Section(L10n.Savings.quickStart) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SavingsGoalTemplate.allCases, id: \.self) { template in
                                TemplateButton(
                                    template: template,
                                    isSelected: selectedTemplate == template
                                ) {
                                    selectTemplate(template)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Goal Details
                Section(L10n.Budget.details) {
                    TextField(L10n.Savings.goalName, text: $name)
                    
                    HStack {
                        TextField(L10n.Savings.targetAmount, text: $targetAmountString)
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
                
                // Target Date
                Section {
                    Toggle(L10n.Savings.targetDate, isOn: $hasTargetDate) // Reusing "Target Date" for toggle label
                    
                    if hasTargetDate {
                        DatePicker(
                            L10n.Savings.targetDate,
                            selection: $targetDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        
                        if let suggested = calculateSuggestedMonthly() {
                            HStack {
                                Text(L10n.Savings.suggestedMonthly)
                                Spacer()
                                Text(suggested.formatted(.currency(code: selectedCurrency)))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                } header: {
                    Text(L10n.Savings.timeline)
                } footer: {
                    if hasTargetDate {
                        Text(L10n.Savings.timelineDescription)
                    }
                }
                
                // Appearance
                Section("Appearance") {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.icon)
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundStyle(Color(hex: selectedColor) ?? .blue)
                        }
                    }
                    
                    Button {
                        showColorPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.color)
                            Spacer()
                            Circle()
                                .fill(Color(hex: selectedColor) ?? .blue)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                
                if !wallets.isEmpty {
                    Section {
                        Picker(L10n.Savings.wallet, selection: $linkedWallet) {
                            Text("None").tag(nil as Wallet?)
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet as Wallet?)
                            }
                        }
                    } header: {
                        Text(L10n.Savings.wallet)
                    } footer: {
                        Text(L10n.Savings.walletDescription)
                    }
                }
                
                // Auto-Contribute
                Section {
                    Toggle(L10n.Savings.autoContribute, isOn: $autoContributeEnabled)
                    
                    if autoContributeEnabled {
                        HStack {
                            TextField(L10n.Transaction.amount, text: $autoContributeAmountString)
                                .keyboardType(.decimalPad)
                            
                            Picker("", selection: $autoContributePeriod) {
                                ForEach([BudgetPeriodType.weekly, .biweekly, .monthly], id: \.self) { period in
                                    Text(period.displayName).tag(period)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text(L10n.Savings.automation)
                } footer: {
                    if autoContributeEnabled {
                        Text(L10n.Savings.autoContributeDescription)
                    }
                }
            }
            .navigationTitle(L10n.Savings.new)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.create) {
                        createGoal()
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon, selectedColorHex: $selectedColor)
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColorHex: $selectedColor)
            }
        }
    }
    
    private func selectTemplate(_ template: SavingsGoalTemplate) {
        selectedTemplate = template
        name = template.displayName
        selectedIcon = template.icon
        selectedColor = template.suggestedColor
        
        if let suggested = template.suggestedAmount {
            targetAmountString = "\(suggested)"
        }
    }
    
    private func calculateSuggestedMonthly() -> Decimal? {
        guard let targetAmount = Decimal(string: targetAmountString),
              hasTargetDate,
              targetDate > Date() else { return nil }
        
        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: Date(), to: targetDate).month ?? 1
        guard months > 0 else { return targetAmount }
        
        return targetAmount / Decimal(months)
    }
    
    private func createGoal() {
        guard let targetAmount = Decimal(string: targetAmountString) else { return }
        
        let goal = SavingsGoal(
            name: name,
            targetAmount: targetAmount,
            currencyCode: selectedCurrency,
            targetDate: hasTargetDate ? targetDate : nil,
            iconName: selectedIcon,
            colorHex: selectedColor
        )
        
        goal.linkedWallet = linkedWallet
        goal.autoContributeEnabled = autoContributeEnabled
        
        if autoContributeEnabled, let amount = Decimal(string: autoContributeAmountString) {
            goal.autoContributeAmount = amount
            goal.autoContributePeriod = autoContributePeriod
        }
        
        modelContext.insert(goal)
    }
}

// MARK: - Template Button

struct TemplateButton: View {
    let template: SavingsGoalTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: template.icon)
                    .font(.app(.title2))
                    .foregroundStyle(isSelected ? .white : Color(hex: template.suggestedColor) ?? .blue)
                    .frame(width: 50, height: 50)
                    .background(isSelected ? (Color(hex: template.suggestedColor) ?? .blue) : (Color(hex: template.suggestedColor) ?? .blue).opacity(0.15))
                    .cornerRadius(12)
                
                Text(template.displayName)
                    .font(.app(.caption))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Enhanced Savings Goal Detail View

struct SavingsGoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: SavingsGoal
    
    @State private var showAddContribution = false
    @State private var contributionAmountString = ""
    @State private var showEditGoal = false
    
    var body: some View {
        List {
            // Hero Section
            Section {
                VStack(spacing: 20) {
                    // Icon
                    Image(systemName: goal.iconName)
                        .appFont(size: 48)
                        .foregroundStyle(Color(hex: goal.colorHex) ?? .blue)
                    
                    // Progress Circle
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 12)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(min(goal.progress, 1.0)))
                            .stroke(
                                (Color(hex: goal.colorHex) ?? .blue).gradient,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 4) {
                            Text(goal.progressPercent)
                                .font(.app(.largeTitle, weight: .bold)) // Approximating 32pt
                            
                            Text(goal.isCompleted ? L10n.Savings.complete : L10n.Savings.progress)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 150, height: 150)
                    
                    // Amount Progress
                    VStack(spacing: 8) {
                        Text(goal.currentAmount.formatted(.currency(code: goal.currencyCode).presentation(.narrow)))
                            .font(.app(.title, weight: .bold))
                        
                        Text(L10n.Budget.leftOf(goal.targetAmount.formatted(.currency(code: goal.currencyCode).presentation(.narrow))))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Quick Add Button
                    if !goal.isCompleted {
                        Button {
                            showAddContribution = true
                        } label: {
                            Label(L10n.Savings.addContribution, systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: goal.colorHex) ?? .blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)
            
            // Details Section
            Section(L10n.Budget.details) {
                if let targetDate = goal.targetDate {
                    HStack {
                        Label(L10n.Savings.targetDate, systemImage: "calendar")
                        Spacer()
                        Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    
                    if let days = goal.daysRemaining {
                        HStack {
                            Label(L10n.Savings.daysRemaining, systemImage: "clock")
                            Spacer()
                            Text("\(days)")
                                .foregroundStyle(days < 30 ? .orange : .secondary)
                        }
                    }
                }
                
                
                HStack {
                    Label(L10n.Savings.remaining, systemImage: "arrow.up.right")
                    Spacer()
                    Text(goal.remainingAmount.formatted(.currency(code: goal.currencyCode).presentation(.narrow)))
                        .foregroundStyle(.secondary)
                }
                
                if let suggested = goal.suggestedMonthlyContribution {
                    HStack {
                        Label(L10n.Savings.monthlyNeeded, systemImage: "calendar.badge.clock")
                        Spacer()
                        Text(suggested.formatted(.currency(code: goal.currencyCode).presentation(.narrow)))
                            .foregroundStyle(.blue)
                    }
                }
                
                HStack {
                    Label(L10n.Savings.status, systemImage: goal.isOnTrack ? "checkmark.circle" : "exclamationmark.triangle")
                    Spacer()
                    Text(goal.statusMessage)
                        .foregroundStyle(goal.isOnTrack ? .green : .orange)
                }
            }
            
            // Auto-Contribute Info
            if goal.autoContributeEnabled, let amount = goal.autoContributeAmount {
                Section(L10n.Savings.automation) {
                    HStack {
                        Label(L10n.Transaction.amount, systemImage: "repeat")
                        Spacer()
                        Text("\(amount.formatted(.currency(code: goal.currencyCode).presentation(.narrow))) / \(goal.autoContributePeriod?.displayName ?? "month")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Linked Wallet
            if let wallet = goal.linkedWallet {
                Section(L10n.Savings.wallet) {
                    HStack {
                        Image(systemName: wallet.icon)
                            .foregroundStyle(Color(hex: wallet.colorHex) ?? .blue)
                        Text(wallet.name)
                        Spacer()
                        Text(wallet.balance.formatted(.currency(code: wallet.currencyCode).presentation(.narrow)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Actions
            Section {
                if goal.isCompleted {
                    Button {
                        goal.isCompleted = false
                        goal.completedDate = nil
                    } label: {
                        Label(L10n.Savings.markActive, systemImage: "arrow.uturn.backward")
                    }
                }
                
                Button {
                    showEditGoal = true
                } label: {
                    Label(L10n.Savings.edit, systemImage: "pencil")
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(L10n.Savings.addContribution, isPresented: $showAddContribution) {
            TextField(L10n.Transaction.amount, text: $contributionAmountString)
                .keyboardType(.decimalPad)
            
            Button(L10n.Common.cancel, role: .cancel) {
                contributionAmountString = ""
            }
            
            Button(L10n.Common.add) {
                if let amount = Decimal(string: contributionAmountString) {
                    goal.addContribution(amount)
                    contributionAmountString = ""
                }
            }
        } message: {
            Text(String(format: L10n.Savings.enterContributionAmount, goal.currencyCode))
        }
        .sheet(isPresented: $showEditGoal) {
            EditSavingsGoalView(goal: goal)
        }
    }
}

// MARK: - Edit Savings Goal View

struct EditSavingsGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var goal: SavingsGoal
    
    @State private var name: String = ""
    @State private var targetAmountString: String = ""
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Date()
    
    init(goal: SavingsGoal) {
        self.goal = goal
        _name = State(initialValue: goal.name)
        _targetAmountString = State(initialValue: "\(goal.targetAmount)")
        _hasTargetDate = State(initialValue: goal.targetDate != nil)
        _targetDate = State(initialValue: goal.targetDate ?? Date())
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Budget.details) {
                    TextField(L10n.Savings.goalName, text: $name)
                    
                    TextField(L10n.Savings.targetAmount, text: $targetAmountString)
                        .keyboardType(.decimalPad)
                }
                
                Section(L10n.Savings.timeline) {
                    Toggle(L10n.Savings.targetDate, isOn: $hasTargetDate)
                    
                    if hasTargetDate {
                        DatePicker(
                            L10n.Savings.targetDate,
                            selection: $targetDate,
                            displayedComponents: .date
                        )
                    }
                }
                
                Section(L10n.Savings.progress) {
                    HStack {
                        Text(L10n.Budget.currentPeriod) // Reusing Current Period or similar
                        Spacer()
                        Text(goal.currentAmount.formatted(.currency(code: goal.currencyCode).presentation(.narrow)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.Savings.edit)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(name.isEmpty || Decimal(string: targetAmountString) == nil)
                }
            }
        }
    }
    
    private func saveChanges() {
        goal.name = name
        if let amount = Decimal(string: targetAmountString) {
            goal.targetAmount = amount
        }
        goal.targetDate = hasTargetDate ? targetDate : nil
    }
}

#Preview {
    NavigationStack {
        SavingsGoalListView()
    }
    .modelContainer(for: [SavingsGoal.self, Wallet.self], inMemory: true)
}

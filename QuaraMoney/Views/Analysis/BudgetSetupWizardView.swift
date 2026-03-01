import SwiftUI
import SwiftData

/// Guided budget setup wizard with template selection
struct BudgetSetupWizardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Category.name) private var categories: [Category]
    
    // Wizard state
    @State private var currentStep: WizardStep = .welcome
    @State private var selectedTemplate: BudgetTemplate?
    @State private var monthlyIncome: String = ""
    @State private var selectedCategories: [BudgetCategoryType: [Category]] = [:]
    @State private var customAllocations: [BudgetCategoryType: Double] = [
        .needs: 0.50,
        .wants: 0.30,
        .savings: 0.20
    ]
    @State private var budgetsToCreate: [BudgetDraft] = []
    @State private var isCreating = false
    
    enum WizardStep: Int, CaseIterable {
        case welcome
        case selectTemplate
        case enterIncome
        case assignCategories
        case customizeAllocations
        case review
        case complete
        
        var title: String {
            switch self {
            case .welcome: return L10n.Wizard.Start.title
            case .selectTemplate: return L10n.Wizard.SelectTemplate.title
            case .enterIncome: return L10n.Wizard.EnterIncome.title
            case .assignCategories: return L10n.Wizard.AssignCategories.title
            case .customizeAllocations: return L10n.Wizard.Customize.title
            case .review: return L10n.Wizard.Review.title
            case .complete: return L10n.Wizard.Complete.title
            }
        }
        
        var subtitle: String {
            switch self {
            case .welcome: return L10n.Wizard.Start.subtitle
            case .selectTemplate: return L10n.Wizard.SelectTemplate.subtitle
            case .enterIncome: return L10n.Wizard.EnterIncome.subtitle
            case .assignCategories: return L10n.Wizard.AssignCategories.subtitle
            case .customizeAllocations: return L10n.Wizard.Customize.subtitle
            case .review: return L10n.Wizard.Review.subtitle
            case .complete: return L10n.Wizard.Complete.subtitle
            }
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .welcome: return true
        case .selectTemplate: return selectedTemplate != nil
        case .enterIncome: return Decimal(string: monthlyIncome) != nil && Decimal(string: monthlyIncome)! > 0
        case .assignCategories: return !selectedCategories.isEmpty
        case .customizeAllocations: return true
        case .review: return !budgetsToCreate.isEmpty
        case .complete: return true
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: Double(currentStep.rawValue), total: Double(WizardStep.allCases.count - 1))
                    .tint(.blue)
                    .padding(.horizontal)
                    .padding(.top)
                
                // Step indicator
                HStack {
                    Text(L10n.Wizard.step(currentStep.rawValue + 1, WizardStep.allCases.count))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(currentStep.title)
                                .font(.app(.largeTitle, weight: .bold))
                            
                            Text(currentStep.subtitle)
                                .font(.app(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                        
                        // Step content
                        stepContent
                            .padding(.horizontal)
                    }
                    .padding(.bottom, 100)
                }
                
                // Navigation buttons
                navigationButtons
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeContent
        case .selectTemplate:
            templateSelectionContent
        case .enterIncome:
            incomeEntryContent
        case .assignCategories:
            categoryAssignmentContent
        case .customizeAllocations:
            allocationCustomizationContent
        case .review:
            reviewContent
        case .complete:
            completeContent
        }
    }
    
    private var welcomeContent: some View {
        VStack(spacing: 32) {
            Image(systemName: "chart.pie.fill")
                .appFont(size: 80) // Keep size 80, but could wrap in Font.app if we had a size variant, but system is fine for icon
                .foregroundStyle(.blue.gradient)
                .padding(.top, 40)
            
            VStack(spacing: 16) {
                FeatureRow(
                    icon: "target",
                    title: L10n.Wizard.Start.limitsTitle,
                    description: L10n.Wizard.Start.limitsDesc
                )
                
                FeatureRow(
                    icon: "bell.badge",
                    title: L10n.Wizard.Start.alertsTitle,
                    description: L10n.Wizard.Start.alertsDesc
                )
                
                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: L10n.Wizard.Start.trackTitle,
                    description: L10n.Wizard.Start.trackDesc
                )
                
                FeatureRow(
                    icon: "repeat",
                    title: L10n.Wizard.Start.autoRenewTitle,
                    description: L10n.Wizard.Start.autoRenewDesc
                )
            }
            .padding(.vertical)
        }
    }
    
    private var templateSelectionContent: some View {
        VStack(spacing: 16) {
            ForEach(BudgetTemplate.allCases, id: \.self) { template in
                TemplateCard(
                    template: template,
                    isSelected: selectedTemplate == template
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTemplate = template
                        customAllocations = template.allocations
                    }
                }
            }
        }
    }
    
    private var incomeEntryContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L10n.Wizard.incomePrompt)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
            
            HStack(alignment: .center, spacing: 8) {
                Text(CurrencyManager.shared.preferredCurrencyCode)
                    .font(.app(.title2))
                    .foregroundStyle(.secondary)
                
                TextField("0", text: $monthlyIncome)
                    .font(.app(.largeTitle, weight: .bold)) // 48 is roughly largeTitle++ but largeTitle (34) is consistent
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            
            if let income = Decimal(string: monthlyIncome), income > 0, let template = selectedTemplate {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Wizard.basedOn(template.displayName))
                        .font(.app(.headline))
                    
                    ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                        if let allocation = template.allocations[type] {
                            HStack {
                                Label(type.displayName, systemImage: type.icon)
                                    .foregroundStyle(Color(hex: type.color) ?? .gray)
                                Spacer()
                                Text((income * Decimal(allocation)).formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                                    .font(.app(.body, weight: .semibold))
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
            }
        }
    }
    
    private var categoryAssignmentContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.Wizard.assignPrompt)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
            
            ForEach(BudgetCategoryType.allCases, id: \.self) { budgetType in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: budgetType.icon)
                            .foregroundStyle(Color(hex: budgetType.color) ?? .gray)
                        Text(budgetType.displayName)
                            .font(.app(.headline))
                        Spacer()
                        Text(L10n.Wizard.selectedCount(selectedCategories[budgetType]?.count ?? 0))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(budgetType.description)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(categories.filter { $0.type == .expense }) { category in
                            CategoryChip(
                                category: category,
                                isSelected: selectedCategories[budgetType]?.contains(where: { $0.id == category.id }) ?? false,
                                color: Color(hex: budgetType.color) ?? .gray
                            ) {
                                toggleCategory(category, for: budgetType)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
            }
        }
    }
    
    private var allocationCustomizationContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let income = Decimal(string: monthlyIncome) {
                ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(type.displayName, systemImage: type.icon)
                                .foregroundStyle(Color(hex: type.color) ?? .gray)
                            Spacer()
                            Text("\(Int(customAllocations[type, default: 0] * 100))%")
                                .font(.app(.title3, weight: .bold))
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { customAllocations[type, default: 0] },
                                set: { customAllocations[type] = $0 }
                            ),
                            in: 0...1,
                            step: 0.05
                        )
                        .tint(Color(hex: type.color) ?? .blue)
                        
                        Text((income * Decimal(customAllocations[type, default: 0])).formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                }
                
                // Total check
                let total = customAllocations.values.reduce(0, +)
                HStack {
                    Text(L10n.Wizard.totalAllocation)
                        .font(.app(.headline))
                    Spacer()
                    Text("\(Int(total * 100))%")
                        .font(.app(.title3, weight: .bold))
                        .foregroundStyle(abs(total - 1.0) < 0.01 ? .green : .orange)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
            }
        }
    }
    
    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let income = Decimal(string: monthlyIncome) {
                ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                    let amount = income * Decimal(customAllocations[type, default: 0])
                    let categoryCount = selectedCategories[type]?.count ?? 0
                    
                    if amount > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(type.displayName, systemImage: type.icon)
                                    .font(.app(.headline))
                                    .foregroundStyle(Color(hex: type.color) ?? .gray)
                                
                                Text("\(categoryCount) categories")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(amount.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                                    .font(.app(.title3, weight: .bold))
                                
                                Text(L10n.Budget.ofIncome)
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    }
                }
                
                Divider()
                    .padding(.vertical)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Wizard.budgetsToCreate)
                        .font(.app(.headline))
                    
                    Text(L10n.Wizard.Review.point1)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    
                    Text(L10n.Wizard.Review.point2)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    
                    Text(L10n.Wizard.Review.point3)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(16)
            }
        }
        .onAppear {
            prepareBudgetDrafts()
        }
    }
    
    private var completeContent: some View {
        VStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .appFont(size: 80)
                .foregroundStyle(.green.gradient)
                .padding(.top, 40)
            
            VStack(spacing: 12) {
                Text(L10n.Wizard.Complete.allSetTitle)
                    .font(.app(.title, weight: .bold))
                
                Text(L10n.Wizard.Complete.allSetMessage)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                Label(L10n.Wizard.Complete.point1, systemImage: "chart.bar.fill")
                Label(L10n.Wizard.Complete.point2, systemImage: "bell.badge.fill")
                Label(L10n.Wizard.Complete.point3, systemImage: "calendar.badge.clock")
            }
            .font(.app(.subheadline))
            .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Navigation
    
    private var navigationButtons: some View {
        VStack(spacing: 12) {
            Divider()
            
            HStack(spacing: 16) {
                if currentStep != .welcome && currentStep != .complete {
                    Button {
                        withAnimation {
                            goBack()
                        }
                    } label: {
                        Text(L10n.Wizard.back)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button {
                    withAnimation {
                        goNext()
                    }
                } label: {
                    if isCreating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(currentStep == .review ? L10n.Wizard.createBudgets : (currentStep == .complete ? L10n.Wizard.Complete.title : L10n.Wizard.continueAction))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed || isCreating)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemBackground))
    }
    
    private func goBack() {
        if let currentIndex = WizardStep.allCases.firstIndex(of: currentStep), currentIndex > 0 {
            currentStep = WizardStep.allCases[currentIndex - 1]
        }
    }
    
    private func goNext() {
        if currentStep == .review {
            createBudgets()
        } else if currentStep == .complete {
            dismiss()
        } else if let currentIndex = WizardStep.allCases.firstIndex(of: currentStep), currentIndex < WizardStep.allCases.count - 1 {
            currentStep = WizardStep.allCases[currentIndex + 1]
        }
    }
    
    // MARK: - Helpers
    
    private func toggleCategory(_ category: Category, for budgetType: BudgetCategoryType) {
        // Remove from other types first
        for type in BudgetCategoryType.allCases {
            selectedCategories[type]?.removeAll { $0.id == category.id }
        }
        
        // Add to selected type
        if selectedCategories[budgetType] == nil {
            selectedCategories[budgetType] = []
        }
        
        if !(selectedCategories[budgetType]?.contains(where: { $0.id == category.id }) ?? false) {
            selectedCategories[budgetType]?.append(category)
        }
    }
    
    private func prepareBudgetDrafts() {
        guard let income = Decimal(string: monthlyIncome) else { return }
        
        budgetsToCreate = BudgetCategoryType.allCases.compactMap { type in
            let allocation = customAllocations[type, default: 0]
            let amount = income * Decimal(allocation)
            
            guard amount > 0 else { return nil }
            
            return BudgetDraft(
                budgetCategoryType: type,
                amount: amount,
                categories: selectedCategories[type] ?? []
            )
        }
    }
    
    private func createBudgets() {
        guard let income = Decimal(string: monthlyIncome) else { return }
        
        isCreating = true
        
        // Create category groups and budgets for each type
        for type in BudgetCategoryType.allCases {
            let allocation = customAllocations[type, default: 0]
            let amount = income * Decimal(allocation)
            
            guard amount > 0 else { continue }
            
            // Create budget
            let budget = Budget(
                name: type.displayName,
                amountLimit: amount,
                currencyCode: CurrencyManager.shared.preferredCurrencyCode,
                periodType: .monthly,
                startDate: Date(),
                isRecurring: true,
                rolloverExcess: false,
                alertAt50: false,
                alertAt80: true,
                alertAt100: true,
                budgetCategoryType: type,
                categories: selectedCategories[type]
            )
            
            modelContext.insert(budget)
        }
        
        // Move to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isCreating = false
            currentStep = .complete
        }
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.app(.title2))
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.headline))
                Text(description)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct TemplateCard: View {
    let template: BudgetTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: template.icon)
                        .font(.app(.title2))
                        .foregroundStyle(isSelected ? .white : .blue)
                        .frame(width: 44, height: 44)
                        .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1))
                        .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.displayName)
                            .font(.app(.headline))
                            .foregroundStyle(isSelected ? .white : .primary)
                        
                        Text(template.description)
                            .font(.app(.caption))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                    }
                }
                
                // Allocation preview
                HStack(spacing: 4) {
                    ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                        if let allocation = template.allocations[type] {
                            Text("\(Int(allocation * 100))% \(type.displayName)")
                                .font(.app(.caption2))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? Color(.systemBackground).opacity(0.2) : Color(hex: type.color)?.opacity(0.15))
                                .foregroundStyle(isSelected ? .white : Color(hex: type.color) ?? .gray)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CategoryChip: View {
    let category: Category
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.app(.caption))
                Text(category.name)
                    .font(.app(.caption))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                
                self.size.width = max(self.size.width, x)
            }
            
            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Budget Draft

struct BudgetDraft {
    let budgetCategoryType: BudgetCategoryType
    let amount: Decimal
    let categories: [Category]
}

#Preview {
    BudgetSetupWizardView()
        .modelContainer(for: [Budget.self, Category.self], inMemory: true)
}

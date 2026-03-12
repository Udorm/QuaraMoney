import SwiftUI
import SwiftData
import Charts

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
                amount: goal.totalSaved(converter: CurrencyManager.shared.convert),
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

    private var overallProgress: Double {
        totalTarget > 0 ? Double(truncating: totalSaved as NSNumber) / Double(truncating: totalTarget as NSNumber) : 0
    }

    private var dominantColor: Color {
        if let first = activeGoals.first {
            return Color(hex: first.colorHex) ?? .blue
        }
        return .blue
    }

    private let convert = CurrencyManager.shared.convert

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
                    // MARK: Summary Section
                    Section {
                        VStack(spacing: 16) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.Savings.totalSaved)
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                    Text(totalSaved.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                                        .font(.app(.title2, weight: .bold))
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(L10n.Savings.totalTarget)
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                    Text(totalTarget.formattedAmount(for: CurrencyManager.shared.preferredCurrencyCode))
                                        .font(.app(.title2, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // Overall progress
                            VStack(spacing: 8) {
                                ProgressView(value: min(overallProgress, 1.0))
                                    .tint(dominantColor)

                                HStack {
                                    Text(L10n.Budget.percentUsed(Int(overallProgress * 100)))
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(activeGoals.count) \(L10n.Budget.Filter.active), \(completedGoals.count) \(L10n.Common.done)")
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // MARK: Active Goals
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

                    // MARK: Completed Goals
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

    private var goalColor: Color {
        Color(hex: goal.colorHex) ?? .blue
    }

    var body: some View {
        HStack(spacing: 14) {
            // MARK: Icon
            ZStack {
                Circle()
                    .fill(goalColor.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: goal.iconName)
                    .font(.app(.title3))
                    .foregroundStyle(goalColor)
            }

            // MARK: Content
            VStack(alignment: .leading, spacing: 6) {
                // Title + status badge
                HStack(spacing: 6) {
                    Text(goal.name)
                        .font(.app(.body, weight: .semibold))
                        .lineLimit(1)

                    if goal.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.app(.caption))
                    } else if !goal.isOnTrack(converter: CurrencyManager.shared.convert) {
                        Text("Behind")
                            .font(.app(.caption2, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                // Progress Bar with gradient fill
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(.systemGray5))
                            .frame(height: 6)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [goalColor, goalColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * CGFloat(min(goal.progress(converter: CurrencyManager.shared.convert), 1.0)),
                                height: 6
                            )
                            .animation(.spring(duration: 0.6), value: goal.progress(converter: CurrencyManager.shared.convert))
                    }
                }
                .frame(height: 6)

                // Footer row
                HStack(spacing: 0) {
                    Text(goal.progressPercent(converter: CurrencyManager.shared.convert))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)

                    Text(" \u{2022} ")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)

                    Text(goal.totalSaved(converter: CurrencyManager.shared.convert).formattedAmount(for: goal.currencyCode))
                        .font(.app(.caption, weight: .medium))
                        .foregroundStyle(goalColor)

                    Text(L10n.Budget.leftOf(goal.targetAmount.formattedAmount(for: goal.currencyCode)))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    // Days remaining pill or Complete tag
                    if goal.isCompleted {
                        Text(L10n.Savings.complete)
                            .font(.app(.caption2, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.12), in: Capsule())
                    } else if let days = goal.daysRemaining {
                        Text(days > 0 ? "\(days)d" : L10n.Savings.Status.pastDate)
                            .font(.app(.caption2, weight: .medium))
                            .foregroundStyle(days < 30 ? .orange : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (days < 30 ? Color.orange : Color(.systemGray4)).opacity(0.12),
                                in: Capsule()
                            )
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Enhanced Savings Goal Detail View

struct SavingsGoalDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var goal: SavingsGoal

    @State private var showAddContribution = false
    @State private var showEditGoal = false

    private var goalColor: Color {
        Color(hex: goal.colorHex) ?? .blue
    }

    var body: some View {
        List {
            // MARK: - Header Section with Donut Chart
            Section {
                VStack(spacing: 24) {
                    // Header Info
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.name)
                                .font(.app(.title2, weight: .bold))

                            if let targetDate = goal.targetDate {
                                Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.app(.subheadline))
                                    .foregroundStyle(.secondary)
                            }

                            if let days = goal.daysRemaining, days > 0 {
                                Text(L10n.Budget.daysLeft(days))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: goal.iconName)
                            .font(.app(.title2))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(goalColor.gradient)
                            .clipShape(Circle())
                            .shadow(color: goalColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 4)

                    // Donut Chart
                    ZStack {
                        Chart {
                            if goal.isCompleted {
                                SectorMark(
                                    angle: .value("Saved", 100),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(goalColor.gradient)
                            } else {
                                SectorMark(
                                    angle: .value("Saved", Double(truncating: goal.totalSaved(converter: CurrencyManager.shared.convert) as NSNumber)),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(goalColor.gradient)
                                .cornerRadius(4)

                                SectorMark(
                                    angle: .value("Remaining", max(0, Double(truncating: goal.remainingAmount(converter: CurrencyManager.shared.convert) as NSNumber))),
                                    innerRadius: .ratio(0.65),
                                    angularInset: 2
                                )
                                .foregroundStyle(Color(.systemGray5))
                                .cornerRadius(4)
                            }
                        }
                        .frame(height: 220)

                        // Center Label
                        VStack(spacing: 4) {
                            Text(goal.progressPercent(converter: CurrencyManager.shared.convert))
                                .font(.app(.largeTitle, weight: .bold))
                                .foregroundStyle(goal.isCompleted ? goalColor : .primary)

                            Text(goal.isCompleted ? L10n.Savings.complete : L10n.Savings.progress)
                                .font(.app(.subheadline, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))

            // MARK: - Goal Progress Section
            Section(L10n.Budget.summary) {
                HStack {
                    Text(L10n.Savings.totalSaved)
                    Spacer()
                    Text(goal.totalSaved(converter: CurrencyManager.shared.convert).formattedAmount(for: goal.currencyCode))
                        .font(.app(.body, weight: .medium))
                        .foregroundStyle(goalColor)
                }

                HStack {
                    Text(L10n.Savings.targetAmount)
                    Spacer()
                    Text(goal.targetAmount.formattedAmount(for: goal.currencyCode))
                        .foregroundStyle(.secondary)
                }

                if goal.currentAmount > 0 || goal.transactionContributedAmount(converter: CurrencyManager.shared.convert) > 0 {
                    HStack {
                        Text(L10n.Savings.manualContributions)
                        Spacer()
                        Text(goal.currentAmount.formattedAmount(for: goal.currencyCode))
                            .foregroundStyle(.secondary)
                            .font(.app(.caption))
                    }

                    HStack {
                        Text(L10n.Savings.transferContributions)
                        Spacer()
                        Text(goal.transactionContributedAmount(converter: CurrencyManager.shared.convert).formattedAmount(for: goal.currencyCode))
                            .foregroundStyle(.secondary)
                            .font(.app(.caption))
                    }
                }

                if let suggested = goal.suggestedMonthlyContribution(converter: CurrencyManager.shared.convert) {
                    HStack {
                        Text(L10n.Savings.monthlyNeeded)
                        Spacer()
                        Text(suggested.formattedAmount(for: goal.currencyCode))
                            .foregroundStyle(.blue)
                    }
                }

                HStack {
                    Text(L10n.Savings.status)
                    Spacer()
                    Text(goal.statusMessage)
                        .foregroundStyle(goal.isOnTrack(converter: CurrencyManager.shared.convert) ? .green : .orange)
                        .font(.app(.subheadline, weight: .medium))
                }

                if goal.autoContributeEnabled, let amount = goal.autoContributeAmount {
                    HStack {
                        Text(L10n.Savings.autoContribute)
                        Spacer()
                        Text("\(amount.formattedAmount(for: goal.currencyCode)) / \(goal.autoContributePeriod?.displayName ?? "")")
                            .foregroundStyle(.secondary)
                    }
                }

                if let wallet = goal.linkedWallet {
                    HStack {
                        Text(L10n.Savings.wallet)
                        Spacer()
                        Label(wallet.name, systemImage: wallet.icon)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Contribution History
            if let transactions = goal.linkedTransactions, !transactions.isEmpty {
                Section(L10n.Savings.contributionHistory) {
                    ForEach(transactions.sorted(by: { $0.date > $1.date })) { txn in
                        TransactionRowView(transaction: txn, contextWallet: goal.linkedWallet)
                    }
                }
            } else {
                Section(L10n.Savings.contributionHistory) {
                    ContentUnavailableView(
                        L10n.Savings.noLinkedTransactions,
                        systemImage: "tray",
                        description: Text(L10n.Savings.noGoalsDescription)
                    )
                    .listRowBackground(Color.clear)
                }
            }

            // MARK: Actions
            if goal.isCompleted {
                Section {
                    Button {
                        goal.isCompleted = false
                        goal.completedDate = nil
                    } label: {
                        Label(L10n.Savings.markActive, systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !goal.isCompleted {
                    Button {
                        showAddContribution = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.Savings.recordContribution)
                }

                Button {
                    showEditGoal = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(L10n.Savings.edit)
            }
        }
        .sheet(isPresented: $showAddContribution) {
            SavingsContributionSheet(goal: goal)
        }
        .sheet(isPresented: $showEditGoal) {
            EditSavingsGoalView(goal: goal)
        }
    }

    private var daysColor: Color {
        guard let days = goal.daysRemaining else { return .secondary }
        if days < 14 { return .red }
        if days < 30 { return .orange }
        return .green
    }
}

// MARK: - Savings Contribution Sheet (wraps AddTransactionView)

/// Presents the standard AddTransactionView pre-configured as a transfer
/// to the savings goal's linked wallet, with the goal name as note.
private struct SavingsContributionSheet: View {
    @Environment(\.modelContext) private var modelContext
    let goal: SavingsGoal

    var body: some View {
        let vm = AddTransactionViewModel(
            dataService: SwiftDataService(modelContext: modelContext),
            initialWallet: nil
        )
        let _ = configureSavingsTransfer(vm)
        AddTransactionView(viewModel: vm, isNewTransaction: true)
    }

    private func configureSavingsTransfer(_ vm: AddTransactionViewModel) {
        vm.type = .transfer
        vm.note = goal.name
        vm.selectedSavingsGoal = goal
        if let wallet = goal.linkedWallet {
            vm.destinationWallet = wallet
        }
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
    @State private var showCurrencyPicker = false

    private var goalColor: Color {
        Color(hex: selectedColor) ?? .blue
    }

    private var isFormValid: Bool {
        !name.isEmpty && Decimal(string: targetAmountString) != nil && Decimal(string: targetAmountString)! > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                // Goal preview
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(goalColor.opacity(0.12))
                                .frame(width: 52, height: 52)
                            Image(systemName: selectedIcon)
                                .font(.app(.title3))
                                .foregroundStyle(goalColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name.isEmpty ? L10n.Savings.goalName : name)
                                .font(.app(.body, weight: .semibold))
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)

                            if let amount = Decimal(string: targetAmountString), amount > 0 {
                                Text(amount.formattedAmount(for: selectedCurrency))
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // Template Selection
                Section(L10n.Savings.quickStart) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SavingsGoalTemplate.allCases, id: \.self) { template in
                                SavingsTemplateCard(
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

                // Target Date
                Section {
                    Toggle(L10n.Savings.targetDate, isOn: $hasTargetDate)

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
                                Text(suggested.formattedAmount(for: selectedCurrency))
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
                Section("category.appearance".localized) {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.icon)
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundStyle(goalColor)
                        }
                    }

                    Button {
                        showColorPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.color)
                            Spacer()
                            Circle()
                                .fill(goalColor)
                                .frame(width: 24, height: 24)
                        }
                    }
                }

                if !wallets.isEmpty {
                    Section {
                        Picker(L10n.Savings.wallet, selection: $linkedWallet) {
                            Text("budget.threshold.none".localized).tag(nil as Wallet?)
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
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    CurrencySelectionView(selection: $selectedCurrency)
                }
                .presentationDetents([.medium, .large])
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

// MARK: - Savings Template Card (larger with description tooltip)

private struct SavingsTemplateCard: View {
    let template: SavingsGoalTemplate
    let isSelected: Bool
    let action: () -> Void

    private var templateColor: Color {
        Color(hex: template.suggestedColor) ?? .blue
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: template.icon)
                    .font(.app(.title2))
                    .foregroundStyle(isSelected ? .white : templateColor)
                    .frame(width: 56, height: 56)
                    .background(
                        isSelected ? templateColor : templateColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )

                Text(template.displayName)
                    .font(.app(.caption, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Savings Goal View

struct EditSavingsGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var goal: SavingsGoal

    @State private var name: String = ""
    @State private var targetAmountString: String = ""
    @State private var selectedCurrency: String
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Date()
    @State private var selectedIcon: String = "target"
    @State private var selectedColor: String = "#10B981"

    @State private var showIconPicker = false
    @State private var showColorPicker = false
    @State private var showCurrencyPicker = false

    private var goalColor: Color {
        Color(hex: selectedColor) ?? .blue
    }

    init(goal: SavingsGoal) {
        self.goal = goal
        _name = State(initialValue: goal.name)
        _targetAmountString = State(initialValue: "\(goal.targetAmount)")
        _selectedCurrency = State(initialValue: goal.currencyCode)
        _hasTargetDate = State(initialValue: goal.targetDate != nil)
        _targetDate = State(initialValue: goal.targetDate ?? Date())
        _selectedIcon = State(initialValue: goal.iconName)
        _selectedColor = State(initialValue: goal.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Preview
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(goalColor.opacity(0.12))
                                .frame(width: 48, height: 48)
                            Image(systemName: selectedIcon)
                                .font(.app(.title3))
                                .foregroundStyle(goalColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(name.isEmpty ? L10n.Savings.goalName : name)
                                .font(.app(.body, weight: .semibold))
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)

                            Text(goal.progressPercent(converter: CurrencyManager.shared.convert))
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.Budget.details) {
                    TextField(L10n.Savings.goalName, text: $name)

                    HStack {
                        TextField(L10n.Savings.targetAmount, text: $targetAmountString)
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

                // Appearance (icon + color editing)
                Section("category.appearance".localized) {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.icon)
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundStyle(goalColor)
                        }
                    }

                    Button {
                        showColorPicker = true
                    } label: {
                        HStack {
                            Text(L10n.Wallet.color)
                            Spacer()
                            Circle()
                                .fill(goalColor)
                                .frame(width: 24, height: 24)
                        }
                    }
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
                        Text(L10n.Budget.currentPeriod)
                        Spacer()
                        Text(goal.currentAmount.formattedAmount(for: goal.currencyCode))
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
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon, selectedColorHex: $selectedColor)
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColorHex: $selectedColor)
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    CurrencySelectionView(selection: $selectedCurrency)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func saveChanges() {
        goal.name = name
        if let amount = Decimal(string: targetAmountString) {
            goal.targetAmount = amount
        }
        goal.currencyCode = selectedCurrency
        goal.targetDate = hasTargetDate ? targetDate : nil
        goal.iconName = selectedIcon
        goal.colorHex = selectedColor
    }
}


#Preview {
    NavigationStack {
        SavingsGoalListView()
    }
    .modelContainer(for: [SavingsGoal.self, Wallet.self], inMemory: true)
}

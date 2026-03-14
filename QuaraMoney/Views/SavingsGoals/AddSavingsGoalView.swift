import SwiftUI
import SwiftData

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

// MARK: - Savings Template Card

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

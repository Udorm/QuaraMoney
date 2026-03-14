import SwiftUI

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

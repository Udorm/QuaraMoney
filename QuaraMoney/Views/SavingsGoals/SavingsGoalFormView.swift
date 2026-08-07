import SwiftData
import SwiftUI

/// Plan-facing editor for a savings wallet. The Plan path consistently calls
/// the model a Goal; Wallets exposes the same object through its own form.
struct SavingsGoalFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let existing: Wallet?
    private let onDeleted: () -> Void

    @State private var selectedTemplate: SavingsGoalTemplate?
    @State private var name: String
    @State private var targetAmount: String
    @State private var currencyCode: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var iconName: String
    @State private var colorHex: String
    @State private var priority: Int
    @State private var showCurrencyPicker = false
    @State private var showIconPicker = false
    @State private var showColorPicker = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    @MainActor
    init(existing: Wallet? = nil, onDeleted: @escaping () -> Void = {}) {
        self.existing = existing
        self.onDeleted = onDeleted
        let currency = existing?.currencyCode ?? CurrencyManager.shared.preferredCurrencyCode
        _name = State(initialValue: existing?.name ?? "")
        _targetAmount = State(initialValue: existing?.targetAmount.map {
            NSDecimalNumber(decimal: $0).stringValue
        } ?? "")
        _currencyCode = State(initialValue: currency)
        _hasTargetDate = State(initialValue: existing?.targetDate != nil)
        _targetDate = State(initialValue: existing?.targetDate
            ?? Calendar.current.date(byAdding: .year, value: 1, to: Date())
            ?? Date())
        _iconName = State(initialValue: existing?.icon ?? "target")
        _colorHex = State(initialValue: existing?.colorHex ?? "#10B981")
        _priority = State(initialValue: existing?.priority ?? 0)
    }

    private var parsedTarget: Decimal? { Decimal(string: targetAmount) }
    private var color: Color { Color(hex: colorHex) ?? .green }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (parsedTarget ?? 0) > 0
    }
    private var canEditCurrency: Bool {
        guard let existing else { return true }
        return !existing.hasAnyLedgerTransaction
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("savings.quickStart".localized) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(SavingsGoalTemplate.allCases) { template in
                                    templateButton(template)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("common.details".localized) {
                    TextField("savings.goalName".localized, text: $name)
                    HStack {
                        Text(currencyCode)
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.secondary)
                        TextField("savings.targetAmount".localized, text: $targetAmount)
                            .keyboardType(.decimalPad)
                            .appFont(size: 28, weight: .bold)
                            .multilineTextAlignment(.trailing)
                    }
                    Button {
                        showCurrencyPicker = true
                    } label: {
                        LabeledContent("currency.title".localized, value: currencyCode)
                    }
                    .disabled(!canEditCurrency)
                }

                Section("savings.timeline".localized) {
                    Toggle("savings.targetDate".localized, isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker(
                            "savings.targetDate".localized,
                            selection: $targetDate,
                            displayedComponents: .date
                        )
                    }
                    Stepper("savings.priorityValue".localized(with: priority), value: $priority, in: 0...99)
                }

                Section("category.appearance".localized) {
                    Button {
                        showIconPicker = true
                    } label: {
                        LabeledContent("wallet.icon".localized) {
                            Image(systemName: iconName).foregroundStyle(color)
                        }
                    }
                    Button {
                        showColorPicker = true
                    } label: {
                        LabeledContent("wallet.color".localized) {
                            Circle().fill(color).frame(width: 24, height: 24)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("plan.delete_goal".localized, role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil
                ? "plan.new_saving_goal".localized
                : "plan.edit_saving_goal".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save".localized) { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack { CurrencySelectionView(selection: $currencyCode) }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $iconName, selectedColorHex: $colorHex)
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColorHex: $colorHex)
            }
            .confirmationDialog(
                "plan.delete_goal_title".localized,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if existing?.balance == 0 {
                    Button("common.delete".localized, role: .destructive) { deleteGoal() }
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text(existing?.balance == 0
                     ? "plan.delete_goal_message".localized
                     : "savings.deleteBalanceFirst".localized)
            }
            .alert(
                "common.error".localized,
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("common.ok".localized) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func templateButton(_ template: SavingsGoalTemplate) -> some View {
        let selected = selectedTemplate == template
        let templateColor = Color(hex: template.suggestedColor) ?? .green
        return Button {
            selectedTemplate = template
            name = template.displayName
            iconName = template.icon
            colorHex = template.suggestedColor
            if let amount = template.suggestedAmount {
                targetAmount = NSDecimalNumber(decimal: amount).stringValue
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: template.icon)
                    .appFont(.title2)
                    .foregroundStyle(selected ? .white : templateColor)
                    .frame(width: 54, height: 54)
                    .background(
                        selected ? templateColor : templateColor.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    )
                Text(template.displayName)
                    .appFont(.caption, weight: selected ? .semibold : .regular)
                    .lineLimit(1)
            }
            .frame(width: 84)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let target = parsedTarget, canSave else { return }
        do {
            try WalletLedgerRules.validateSavingsConfiguration(kind: .savings, targetAmount: target)
            let wallet: Wallet
            if let existing {
                try WalletLedgerRules.validateWalletUpdate(
                    wallet: existing,
                    proposedKind: .savings,
                    proposedCurrencyCode: currencyCode,
                    proposedTargetAmount: target,
                    proposedArchived: existing.isArchived
                )
                wallet = existing
            } else {
                wallet = Wallet(name: name, currencyCode: currencyCode, icon: iconName, colorHex: colorHex)
                modelContext.insert(wallet)
            }
            wallet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            wallet.currencyCode = currencyCode
            wallet.icon = iconName
            wallet.colorHex = colorHex
            wallet.kind = .savings
            wallet.targetAmount = target
            wallet.targetDate = hasTargetDate ? targetDate : nil
            wallet.priority = priority
            wallet.updatedAt = Date()
            wallet.needsSync = true
            wallet.invalidateBalanceCache()
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            HapticManager.shared.success()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    private func deleteGoal() {
        guard let existing else { return }
        do {
            try SoftDeleteService.deleteWallet(existing, strategy: .deleteTransactions)
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            dismiss()
            onDeleted()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SavingsGoalFormView()
        .modelContainer(for: [Wallet.self, Transaction.self], inMemory: true)
}

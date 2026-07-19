import SwiftUI
import SwiftData

struct SavingsGoalFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Wallet> { $0.deletedAt == nil }, sort: \Wallet.name)
    private var wallets: [Wallet]

    private let existing: SavingsGoal?
    private let onDeleted: () -> Void
    private let mutationExecutor: PlanMutationExecutor

    @State private var selectedTemplate: SavingsGoalTemplate?
    @State private var name: String
    @State private var targetAmount: String
    @State private var currencyCode: String
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var iconName: String
    @State private var colorHex: String
    @State private var linkedWalletID: UUID?

    @State private var showIconPicker = false
    @State private var showColorPicker = false
    @State private var showCurrencyPicker = false
    @State private var currencyPickerSelection: String
    @State private var pendingCurrencyCode: String?
    @State private var showCurrencyDecision = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    @MainActor
    init(
        existing: SavingsGoal? = nil,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.existing = existing
        self.onDeleted = onDeleted
        self.mutationExecutor = PlanMutationExecutor()

        let initialCurrency = existing?.currencyCode ?? CurrencyManager.shared.preferredCurrencyCode
        let defaultDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        _name = State(initialValue: existing?.name ?? "")
        _targetAmount = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.targetAmount).stringValue } ?? "")
        _currencyCode = State(initialValue: initialCurrency)
        _currencyPickerSelection = State(initialValue: initialCurrency)
        _hasTargetDate = State(initialValue: existing?.targetDate != nil)
        _targetDate = State(initialValue: existing?.targetDate ?? defaultDate)
        _iconName = State(initialValue: existing?.iconName ?? "target")
        _colorHex = State(initialValue: existing?.colorHex ?? "#10B981")
        _linkedWalletID = State(initialValue: existing?.linkedWallet?.id)
    }

    private var goalColor: Color { Color(hex: colorHex) ?? .green }
    private var parsedTarget: Decimal? { Decimal(string: targetAmount) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parsedTarget ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Section("savings.quickStart".localized) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(SavingsGoalTemplate.allCases) { template in
                                    PlanSavingsTemplateButton(
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
                }

                Section("common.details".localized) {
                    TextField("savings.goalName".localized, text: $name)

                    HStack {
                        Text(currencyCode)
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $targetAmount)
                            .keyboardType(.decimalPad)
                            .appFont(size: 28, weight: .bold)
                            .multilineTextAlignment(.trailing)
                    }

                    Button {
                        currencyPickerSelection = currencyCode
                        showCurrencyPicker = true
                    } label: {
                        HStack {
                            Text("currency.title".localized)
                            Spacer()
                            Text(currencyCode).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .appFont(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                }

                Section("category.appearance".localized) {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text("wallet.icon".localized)
                            Spacer()
                            Image(systemName: iconName).foregroundStyle(goalColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showColorPicker = true
                    } label: {
                        HStack {
                            Text("wallet.color".localized)
                            Spacer()
                            Circle().fill(goalColor).frame(width: 24, height: 24)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Picker("savings.wallet".localized, selection: $linkedWalletID) {
                        Text("common.none".localized).tag(nil as UUID?)
                        ForEach(wallets) { wallet in
                            Label(wallet.name, systemImage: wallet.icon).tag(wallet.id as UUID?)
                        }
                    }
                } header: {
                    Text("savings.wallet".localized)
                } footer: {
                    Text("savings.walletDescription".localized)
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
            .navigationTitle(existing == nil ? "plan.new_saving_goal".localized : "plan.edit_saving_goal".localized)
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
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $iconName, selectedColorHex: $colorHex)
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColorHex: $colorHex)
            }
            .sheet(isPresented: $showCurrencyPicker, onDismiss: handleCurrencyPickerDismiss) {
                NavigationStack {
                    CurrencySelectionView(selection: $currencyPickerSelection)
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "plan.currency_change_title".localized,
                isPresented: $showCurrencyDecision,
                titleVisibility: .visible
            ) {
                Button("plan.currency_convert".localized) { applyCurrencyChange(.convert) }
                    .disabled(convertedPendingAmount == nil)
                Button("plan.currency_keep_number".localized) { applyCurrencyChange(.keepNumber) }
                Button("common.cancel".localized, role: .cancel) { applyCurrencyChange(.cancel) }
            } message: {
                Text(convertedPendingAmount == nil
                     ? "plan.currency_rate_unavailable".localized
                     : "plan.currency_change_message".localized)
            }
            .confirmationDialog(
                "plan.delete_goal_title".localized,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("common.delete".localized, role: .destructive) { deleteGoal() }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("plan.delete_goal_message".localized)
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

    private func selectTemplate(_ template: SavingsGoalTemplate) {
        selectedTemplate = template
        name = template.displayName
        iconName = template.icon
        colorHex = template.suggestedColor
        if let amount = template.suggestedAmount {
            targetAmount = NSDecimalNumber(decimal: amount).stringValue
        }
    }

    private var convertedPendingAmount: Decimal? {
        guard let pendingCurrencyCode, let parsedTarget else { return nil }
        return PlanCurrencyChangeResolver.convertedAmount(
            parsedTarget,
            from: currencyCode,
            to: pendingCurrencyCode,
            rates: CurrencyManager.shared.rates
        )
    }

    private func handleCurrencyPickerDismiss() {
        guard currencyPickerSelection != currencyCode else { return }
        guard let parsedTarget, parsedTarget != 0 else {
            currencyCode = currencyPickerSelection
            return
        }
        pendingCurrencyCode = currencyPickerSelection
        showCurrencyDecision = true
    }

    private func applyCurrencyChange(_ decision: PlanCurrencyChangeDecision) {
        defer {
            pendingCurrencyCode = nil
            currencyPickerSelection = currencyCode
        }
        guard let pendingCurrencyCode, let parsedTarget else { return }
        switch decision {
        case .convert:
            guard let converted = PlanCurrencyChangeResolver.resolve(
                amount: parsedTarget,
                from: currencyCode,
                to: pendingCurrencyCode,
                rates: CurrencyManager.shared.rates,
                decision: .convert
            ) else { return }
            targetAmount = NSDecimalNumber(decimal: converted).stringValue
            currencyCode = pendingCurrencyCode
        case .keepNumber:
            currencyCode = pendingCurrencyCode
        case .cancel:
            break
        }
    }

    private func save() {
        guard let parsedTarget, canSave else { return }
        let linkedWallet = wallets.first { $0.id == linkedWalletID }
        let now = Date()

        do {
            if let existing {
                let snapshot = SavingsGoalFormModelSnapshot(existing)
                try mutationExecutor.perform(
                    in: modelContext,
                    apply: {
                        applyFormValues(
                            to: existing,
                            target: parsedTarget,
                            linkedWallet: linkedWallet,
                            now: now
                        )
                    },
                    rollback: { snapshot.restore(existing) }
                )
            } else {
                var inserted: SavingsGoal?
                try mutationExecutor.perform(
                    in: modelContext,
                    apply: {
                        let goal = SavingsGoal(
                            name: name,
                            targetAmount: parsedTarget,
                            currencyCode: currencyCode,
                            targetDate: hasTargetDate ? targetDate : nil,
                            iconName: iconName,
                            colorHex: colorHex
                        )
                        modelContext.insert(goal)
                        inserted = goal
                        applyFormValues(
                            to: goal,
                            target: parsedTarget,
                            linkedWallet: linkedWallet,
                            now: now
                        )
                    },
                    rollback: {
                        if let inserted { modelContext.delete(inserted) }
                    }
                )
            }
            HapticManager.shared.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }

    private func applyFormValues(
        to goal: SavingsGoal,
        target: Decimal,
        linkedWallet: Wallet?,
        now: Date
    ) {
        let oldCurrency = goal.currencyCode
        if goal.currentAmount != 0, goal.startingBalanceCurrencyCode == nil, oldCurrency != currencyCode {
            goal.startingBalanceCurrencyCode = oldCurrency
        }
        goal.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.targetAmount = target
        goal.currencyCode = currencyCode
        goal.targetDate = hasTargetDate ? targetDate : nil
        goal.iconName = iconName
        goal.colorHex = colorHex
        goal.linkedWallet = linkedWallet
        goal.updatedAt = now
        goal.needsSync = true
        _ = SavingsGoalReconciler.reconcile(goal, at: now)
    }

    private func deleteGoal() {
        guard let existing else { return }
        do {
            try mutationExecutor.softDelete(existing, in: modelContext)
            HapticManager.shared.success()
            dismiss()
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.shared.error()
        }
    }
}

private struct PlanSavingsTemplateButton: View {
    let template: SavingsGoalTemplate
    let isSelected: Bool
    let action: () -> Void

    private var color: Color { Color(hex: template.suggestedColor) ?? .green }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: template.icon)
                    .appFont(.title2)
                    .foregroundStyle(isSelected ? .white : color)
                    .frame(width: 54, height: 54)
                    .background(
                        isSelected ? color : color.opacity(0.13),
                        in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    )
                Text(template.displayName)
                    .appFont(.caption, weight: isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 84)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct SavingsGoalFormModelSnapshot {
    let name: String
    let targetAmount: Decimal
    let currencyCode: String
    let startingBalanceCurrencyCode: String?
    let targetDate: Date?
    let iconName: String
    let colorHex: String
    let linkedWallet: Wallet?
    let isCompleted: Bool
    let completedDate: Date?
    let updatedAt: Date
    let needsSync: Bool

    init(_ goal: SavingsGoal) {
        name = goal.name
        targetAmount = goal.targetAmount
        currencyCode = goal.currencyCode
        startingBalanceCurrencyCode = goal.startingBalanceCurrencyCode
        targetDate = goal.targetDate
        iconName = goal.iconName
        colorHex = goal.colorHex
        linkedWallet = goal.linkedWallet
        isCompleted = goal.isCompleted
        completedDate = goal.completedDate
        updatedAt = goal.updatedAt
        needsSync = goal.needsSync
    }

    func restore(_ goal: SavingsGoal) {
        goal.name = name
        goal.targetAmount = targetAmount
        goal.currencyCode = currencyCode
        goal.startingBalanceCurrencyCode = startingBalanceCurrencyCode
        goal.targetDate = targetDate
        goal.iconName = iconName
        goal.colorHex = colorHex
        goal.linkedWallet = linkedWallet
        goal.isCompleted = isCompleted
        goal.completedDate = completedDate
        goal.updatedAt = updatedAt
        goal.needsSync = needsSync
    }
}

#Preview {
    SavingsGoalFormView()
        .modelContainer(for: [SavingsGoal.self, Wallet.self, Transaction.self], inMemory: true)
}

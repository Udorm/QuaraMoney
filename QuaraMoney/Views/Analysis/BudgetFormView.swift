import SwiftUI
import SwiftData

struct BudgetFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name)
    private var categories: [Category]
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }, sort: \Budget.createdAt)
    private var budgets: [Budget]

    private let existing: Budget?
    private let onDeleted: () -> Void
    private let mutationExecutor: PlanMutationExecutor

    @State private var targetKind: BudgetTargetKind
    @State private var selectedCategoryIDs: Set<UUID>
    @State private var amount: String
    @State private var currencyCode: String
    @State private var name: String
    @State private var periodType: BudgetPeriodType
    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var alertMode: BudgetAlertMode

    @State private var showCategoryPicker = false
    @State private var showCurrencyPicker = false
    @State private var currencyPickerSelection: String
    @State private var pendingCurrencyCode: String?
    @State private var showCurrencyDecision = false
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?

    @State private var suggestion: BudgetSuggestion?
    @State private var isLoadingSuggestion = false
    @State private var suggestionGeneration = 0

    @MainActor
    init(
        existing: Budget? = nil,
        onDeleted: @escaping () -> Void = {}
    ) {
        self.existing = existing
        self.onDeleted = onDeleted
        self.mutationExecutor = PlanMutationExecutor()

        let categoryIDs = Set(existing?.effectiveTrackedCategories.map(\.id) ?? [])
        let initialCurrency = existing?.currencyCode ?? CurrencyManager.shared.preferredCurrencyCode
        let initialStart = existing?.startDate ?? Date()

        _targetKind = State(initialValue: existing?.targetKind ?? .categories)
        _selectedCategoryIDs = State(initialValue: categoryIDs)
        _amount = State(initialValue: existing.map { NSDecimalNumber(decimal: $0.amountLimit).stringValue } ?? "")
        _currencyCode = State(initialValue: initialCurrency)
        _currencyPickerSelection = State(initialValue: initialCurrency)
        _name = State(initialValue: existing?.name ?? "")
        _periodType = State(initialValue: existing?.periodType ?? .monthly)
        _customStart = State(initialValue: initialStart)
        _customEnd = State(initialValue: existing?.customEndDate ?? initialStart)
        _alertMode = State(initialValue: existing?.alertMode ?? .nearingOver)
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    private var selectedExpenseCategories: [Category] {
        expenseCategories.filter { selectedCategoryIDs.contains($0.id) }
    }

    private var parsedAmount: Decimal? { Decimal(string: amount) }

    private var isDuplicateTotal: Bool {
        guard targetKind == .total, periodType != .custom else { return false }
        return budgets.contains {
            $0.id != existing?.id && $0.targetKind == .total && $0.periodType == periodType && $0.periodType != .custom
        }
    }

    private var canSave: Bool {
        guard let parsedAmount, parsedAmount > 0, !isDuplicateTotal else { return false }
        return targetKind == .total || !selectedCategoryIDs.isEmpty
    }

    private var suggestionRequest: PlanBudgetSuggestionRequest {
        PlanBudgetSuggestionRequest(
            targetKind: targetKind,
            categoryIDs: selectedCategoryIDs.sorted { $0.uuidString < $1.uuidString },
            periodType: periodType,
            currencyCode: currencyCode
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("plan.target".localized) {
                    Picker("plan.target".localized, selection: $targetKind) {
                        Text("plan.total".localized).tag(BudgetTargetKind.total)
                        Text("plan.categories".localized).tag(BudgetTargetKind.categories)
                    }
                    .pickerStyle(.segmented)

                    if targetKind == .categories {
                        Button {
                            showCategoryPicker = true
                        } label: {
                            HStack {
                                Label("budget.selectCategories".localized, systemImage: "square.grid.2x2")
                                Spacer()
                                Text(selectedCategoryIDs.isEmpty
                                     ? "common.select".localized
                                     : "\(selectedCategoryIDs.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .appFont(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !selectedExpenseCategories.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(selectedExpenseCategories) { category in
                                    CategoryChip(
                                        category: category,
                                        isSelected: true,
                                        isHighlighted: false
                                    ) {
                                        selectedCategoryIDs.remove(category.id)
                                    }
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } else {
                        Label("budget.allExpenses".localized, systemImage: "sum")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("transaction.amount".localized) {
                    HStack {
                        Text(currencyCode)
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $amount)
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

                    if existing == nil {
                        suggestionRow
                    }
                }

                Section("common.details".localized) {
                    TextField("plan.name_optional".localized, text: $name)

                    Picker("period.title".localized, selection: $periodType) {
                        ForEach(BudgetPeriodType.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }

                    if periodType == .custom {
                        DatePicker(
                            "plan.starts".localized,
                            selection: $customStart,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "plan.ends_inclusive".localized,
                            selection: $customEnd,
                            in: customStart...,
                            displayedComponents: .date
                        )
                    }
                }

                Section("plan.alerts".localized) {
                    Picker("plan.alerts".localized, selection: $alertMode) {
                        Text("plan.alert_off".localized).tag(BudgetAlertMode.off)
                        Text("plan.alert_nearing".localized).tag(BudgetAlertMode.nearing)
                        Text("plan.alert_over".localized).tag(BudgetAlertMode.overOnly)
                        Text("plan.alert_nearing_over".localized).tag(BudgetAlertMode.nearingOver)
                    }
                }

                if isDuplicateTotal {
                    Section {
                        Label("plan.duplicate_total".localized, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if existing != nil {
                    Section {
                        Button("plan.delete_budget".localized, role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "plan.new_budget".localized : "plan.edit_budget".localized)
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
            .sheet(isPresented: $showCategoryPicker) {
                MultiCategoryPicker(selectedCategories: $selectedCategoryIDs)
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
                Button("plan.currency_convert".localized) {
                    applyCurrencyChange(.convert)
                }
                .disabled(convertedPendingAmount == nil)
                Button("plan.currency_keep_number".localized) {
                    applyCurrencyChange(.keepNumber)
                }
                Button("common.cancel".localized, role: .cancel) {
                    applyCurrencyChange(.cancel)
                }
            } message: {
                Text(convertedPendingAmount == nil
                     ? "plan.currency_rate_unavailable".localized
                     : "plan.currency_change_message".localized)
            }
            .confirmationDialog(
                "plan.delete_budget_title".localized,
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("common.delete".localized, role: .destructive) { deleteBudget() }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("plan.delete_budget_message".localized)
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
            .task(id: suggestionRequest) {
                await loadSuggestion(for: suggestionRequest)
            }
        }
    }

    @ViewBuilder
    private var suggestionRow: some View {
        if isLoadingSuggestion {
            HStack {
                ProgressView().controlSize(.small)
                Text("plan.loading_suggestion".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let suggestion, let suggestedAmount = suggestion.suggestedAmount {
            Button {
                amount = roundedAmountString(suggestedAmount)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("plan.you_averaged".localized(with:
                            suggestion.averageSpending.formattedAmount(for: currencyCode), periodUnit))
                            .appFont(.subheadline, weight: .medium)
                        Spacer()
                        Text("plan.use_suggestion".localized)
                            .appFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    Text(confidenceCopy(suggestion.confidence))
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func roundedAmountString(_ value: Decimal) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private var periodUnit: String {
        switch periodType {
        case .weekly: "plan.per_week".localized
        case .biweekly: "plan.per_two_weeks".localized
        case .monthly: "plan.per_month".localized
        case .quarterly: "plan.per_quarter".localized
        case .yearly: "plan.per_year".localized
        case .custom: ""
        }
    }

    private func confidenceCopy(_ confidence: SuggestionConfidence) -> String {
        switch confidence {
        case .high: "plan.confidence_high".localized
        case .medium: "plan.confidence_medium".localized
        case .low: "plan.confidence_low".localized
        case .noData: ""
        }
    }

    private func loadSuggestion(for request: PlanBudgetSuggestionRequest) async {
        suggestionGeneration += 1
        let generation = suggestionGeneration
        guard existing == nil,
              request.periodType != .custom,
              request.targetKind == .total || !request.categoryIDs.isEmpty else {
            suggestion = nil
            isLoadingSuggestion = false
            return
        }
        isLoadingSuggestion = true
        let engine = BudgetSuggestionEngine(modelContext: modelContext)
        let result = await engine.suggestion(
            targetKind: request.targetKind,
            categoryIDs: Set(request.categoryIDs),
            periodType: request.periodType,
            currencyCode: request.currencyCode,
            rates: CurrencyManager.shared.rates
        )
        guard generation == suggestionGeneration, request == suggestionRequest else { return }
        suggestion = result
        isLoadingSuggestion = false
    }

    private var convertedPendingAmount: Decimal? {
        guard let pendingCurrencyCode, let parsedAmount else { return nil }
        return PlanCurrencyChangeResolver.convertedAmount(
            parsedAmount,
            from: currencyCode,
            to: pendingCurrencyCode,
            rates: CurrencyManager.shared.rates
        )
    }

    private func handleCurrencyPickerDismiss() {
        guard currencyPickerSelection != currencyCode else { return }
        guard let parsedAmount, parsedAmount != 0 else {
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
        guard let pendingCurrencyCode, let parsedAmount else { return }
        switch decision {
        case .convert:
            guard let converted = PlanCurrencyChangeResolver.resolve(
                amount: parsedAmount,
                from: currencyCode,
                to: pendingCurrencyCode,
                rates: CurrencyManager.shared.rates,
                decision: .convert
            ) else { return }
            amount = NSDecimalNumber(decimal: converted).stringValue
            currencyCode = pendingCurrencyCode
        case .keepNumber:
            currencyCode = pendingCurrencyCode
        case .cancel:
            break
        }
    }

    private func save() {
        guard let parsedAmount, canSave else { return }
        let selectedCategories = selectedExpenseCategories
        let now = Date()

        do {
            if let existing {
                let snapshot = BudgetFormModelSnapshot(existing)
                try mutationExecutor.perform(
                    in: modelContext,
                    apply: {
                        applyFormValues(
                            to: existing,
                            amount: parsedAmount,
                            selectedCategories: selectedCategories,
                            now: now
                        )
                    },
                    rollback: { snapshot.restore(existing) }
                )
            } else {
                var inserted: Budget?
                try mutationExecutor.perform(
                    in: modelContext,
                    apply: {
                        let budget = Budget(
                            amountLimit: parsedAmount,
                            currencyCode: currencyCode,
                            periodType: periodType,
                            startDate: periodType == .custom ? customStart : now,
                            customEndDate: periodType == .custom ? customEnd : nil
                        )
                        modelContext.insert(budget)
                        inserted = budget
                        applyFormValues(
                            to: budget,
                            amount: parsedAmount,
                            selectedCategories: selectedCategories,
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
        to budget: Budget,
        amount: Decimal,
        selectedCategories: [Category],
        now: Date
    ) {
        Self.applyFormValues(
            to: budget,
            name: name,
            amount: amount,
            currencyCode: currencyCode,
            selectedCategories: selectedCategories,
            targetKind: targetKind,
            periodType: periodType,
            customStart: customStart,
            customEnd: customEnd,
            alertMode: alertMode,
            isNewBudget: existing == nil,
            now: now
        )
    }

    /// Shared by the production save closure and category-link regression tests.
    /// Keep the category setter unconditional: its own normalized change
    /// detection is what makes a name-only save safe.
    @MainActor
    static func applyFormValues(
        to budget: Budget,
        name: String,
        amount: Decimal,
        currencyCode: String,
        selectedCategories: [Category],
        targetKind: BudgetTargetKind,
        periodType: BudgetPeriodType,
        customStart: Date,
        customEnd: Date,
        alertMode: BudgetAlertMode,
        isNewBudget: Bool,
        now: Date
    ) {
        budget.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
        budget.amountType = .fixed(amount)
        budget.amountLimit = amount
        budget.currencyCode = currencyCode
        budget.setTrackedCategories(selectedCategories, targetKind: targetKind)
        budget.periodType = periodType
        if periodType == .custom {
            budget.startDate = customStart
            budget.customEndDate = customEnd
        } else if isNewBudget {
            budget.startDate = now
            budget.customEndDate = nil
        } else {
            budget.customEndDate = nil
        }
        budget.isRecurring = periodType != .custom
        budget.weekStartDay = periodType == .weekly ? (budget.weekStartDay ?? Calendar.current.firstWeekday) : nil
        budget.alertMode = alertMode
        budget.alertAt80 = alertMode.thresholds.contains(80)
        budget.alertAt100 = alertMode.thresholds.contains(100)
        budget.month = Calendar.current.component(.month, from: budget.startDate)
        budget.year = Calendar.current.component(.year, from: budget.startDate)
        budget.updatedAt = now
        budget.needsSync = true
    }

    private func deleteBudget() {
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

private struct PlanBudgetSuggestionRequest: Hashable {
    let targetKind: BudgetTargetKind
    let categoryIDs: [UUID]
    let periodType: BudgetPeriodType
    let currencyCode: String
}

@MainActor
private struct BudgetFormModelSnapshot {
    let name: String?
    let amountLimit: Decimal
    let amountType: BudgetAmountType
    let currencyCode: String
    let targetKind: BudgetTargetKind
    let category: Category?
    let categories: [Category]?
    let periodType: BudgetPeriodType
    let startDate: Date
    let customEndDate: Date?
    let isRecurring: Bool
    let weekStartDay: Int?
    let alertMode: BudgetAlertMode
    let alertAt80: Bool
    let alertAt100: Bool
    let month: Int
    let year: Int
    let updatedAt: Date
    let needsSync: Bool
    let categorySetDirty: Bool

    init(_ budget: Budget) {
        name = budget.name
        amountLimit = budget.amountLimit
        amountType = budget.amountType
        currencyCode = budget.currencyCode
        targetKind = budget.targetKind
        category = budget.category
        categories = budget.categories
        periodType = budget.periodType
        startDate = budget.startDate
        customEndDate = budget.customEndDate
        isRecurring = budget.isRecurring
        weekStartDay = budget.weekStartDay
        alertMode = budget.alertMode
        alertAt80 = budget.alertAt80
        alertAt100 = budget.alertAt100
        month = budget.month
        year = budget.year
        updatedAt = budget.updatedAt
        needsSync = budget.needsSync
        categorySetDirty = budget.categorySetDirty
    }

    func restore(_ budget: Budget) {
        budget.name = name
        budget.amountLimit = amountLimit
        budget.amountType = amountType
        budget.currencyCode = currencyCode
        budget.targetKind = targetKind
        budget.category = category
        budget.categories = categories
        budget.periodType = periodType
        budget.startDate = startDate
        budget.customEndDate = customEndDate
        budget.isRecurring = isRecurring
        budget.weekStartDay = weekStartDay
        budget.alertMode = alertMode
        budget.alertAt80 = alertAt80
        budget.alertAt100 = alertAt100
        budget.month = month
        budget.year = year
        budget.updatedAt = updatedAt
        budget.needsSync = needsSync
        budget.categorySetDirty = categorySetDirty
    }
}

#Preview {
    BudgetFormView()
        .modelContainer(for: [Budget.self, Category.self, Transaction.self, Wallet.self], inMemory: true)
}

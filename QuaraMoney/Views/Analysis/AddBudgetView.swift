import SwiftUI
import SwiftData

struct AddBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }) private var categories: [Category]
    @Query(filter: #Predicate<Budget> { $0.deletedAt == nil }) private var budgets: [Budget]

    @State private var targetKind: BudgetTargetKind = .categories
    @State private var selectedCategories = Set<UUID>()
    @State private var amount = ""
    @State private var name = ""
    @State private var currencyCode = CurrencyManager.shared.preferredCurrencyCode
    @State private var periodType: BudgetPeriodType = .monthly
    @State private var alertMode: BudgetAlertMode = .nearingOver
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var showOptions = false
    @State private var errorMessage: String?
    @State private var suggestion: BudgetSuggestion?
    @State private var isLoadingSuggestion = false
    @State private var showCurrencyPicker = false

    private var expenseCategories: [Category] { categories.filter { $0.type == .expense } }
    private var parsedAmount: Decimal? { Decimal(string: amount) }
    private var isDuplicateTotal: Bool {
        targetKind == .total && periodType != .custom && budgets.contains {
            $0.targetKind == .total && $0.periodType == periodType
        }
    }
    private var canSave: Bool {
        (parsedAmount ?? 0) > 0 && (targetKind == .total || !selectedCategories.isEmpty) && !isDuplicateTotal
    }
    private var suggestionRequest: SuggestionRequest {
        SuggestionRequest(targetKind: targetKind, categoryIDs: selectedCategories.sorted { $0.uuidString < $1.uuidString },
                          periodType: periodType, currencyCode: currencyCode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("plan.target".localized) {
                    Picker("plan.target".localized, selection: $targetKind) {
                        Text("plan.total".localized).tag(BudgetTargetKind.total)
                        Text("plan.categories".localized).tag(BudgetTargetKind.categories)
                    }.pickerStyle(.segmented)
                    if targetKind == .categories {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(expenseCategories) { category in
                                    Button {
                                        if selectedCategories.contains(category.id) { selectedCategories.remove(category.id) }
                                        else { selectedCategories.insert(category.id) }
                                    } label: {
                                        Label(category.displayName, systemImage: category.icon)
                                            .appFont(size: 14, weight: .medium).padding(.horizontal, 12).padding(.vertical, 8)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(selectedCategories.contains(category.id) ? .accentColor : .secondary)
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                }

                Section("transaction.amount".localized) {
                    HStack {
                        Text(currencyCode).foregroundStyle(.secondary)
                        TextField("0", text: $amount).keyboardType(.decimalPad)
                            .appFont(size: 28, weight: .bold).multilineTextAlignment(.trailing)
                    }
                    if isLoadingSuggestion { ProgressView().controlSize(.small) }
                    if let suggestion, let suggestedAmount = suggestion.suggestedAmount {
                        Button {
                            amount = NSDecimalNumber(decimal: suggestedAmount).stringValue
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("plan.you_averaged".localized(with:
                                        suggestion.averageSpending.formattedAmount(for: currencyCode), periodUnit))
                                        .appFont(size: 14, weight: .medium)
                                    Text(confidenceCopy(suggestion.confidence))
                                        .appFont(size: 12, weight: .regular).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("plan.use_suggestion".localized).appFont(size: 14, weight: .semibold)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }

                DisclosureGroup("plan.options".localized, isExpanded: $showOptions) {
                    TextField("plan.name_optional".localized, text: $name)
                    Picker("period.title".localized, selection: $periodType) {
                        ForEach([BudgetPeriodType.weekly, .monthly, .quarterly, .yearly, .custom]) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    if periodType == .custom {
                        DatePicker("plan.starts".localized, selection: $customStart, displayedComponents: .date)
                        DatePicker("plan.ends_inclusive".localized, selection: $customEnd,
                                   in: customStart..., displayedComponents: .date)
                    }
                    Button {
                        showCurrencyPicker = true
                    } label: {
                        HStack { Text("currency.title".localized); Spacer(); Text(currencyCode); Image(systemName: "chevron.right") }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Picker("plan.alerts".localized, selection: $alertMode) {
                        Text("plan.alert_off".localized).tag(BudgetAlertMode.off)
                        Text("plan.alert_nearing".localized).tag(BudgetAlertMode.nearing)
                        Text("plan.alert_over".localized).tag(BudgetAlertMode.overOnly)
                        Text("plan.alert_nearing_over".localized).tag(BudgetAlertMode.nearingOver)
                    }
                }

                if isDuplicateTotal {
                    Section { Label("plan.duplicate_total".localized, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("plan.new_budget".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel".localized) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save".localized) { save() }.disabled(!canSave) }
            }
            .alert("common.error".localized, isPresented: .constant(errorMessage != nil)) {
                Button("common.ok".localized) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack { CurrencySelectionView(selection: $currencyCode) }
                    .presentationDetents([.medium, .large])
            }
            .task(id: suggestionRequest) { await loadSuggestion() }
        }
    }

    private var periodUnit: String {
        switch periodType {
        case .weekly: return "plan.per_week".localized
        case .monthly: return "plan.per_month".localized
        case .quarterly: return "plan.per_quarter".localized
        case .yearly: return "plan.per_year".localized
        case .biweekly: return "plan.per_two_weeks".localized
        case .custom: return ""
        }
    }

    private func confidenceCopy(_ confidence: SuggestionConfidence) -> String {
        switch confidence {
        case .high: return "plan.confidence_high".localized
        case .medium: return "plan.confidence_medium".localized
        case .low: return "plan.confidence_low".localized
        case .noData: return ""
        }
    }

    private func loadSuggestion() async {
        guard periodType != .custom, targetKind == .total || !selectedCategories.isEmpty else {
            suggestion = nil; isLoadingSuggestion = false; return
        }
        isLoadingSuggestion = true
        let engine = BudgetSuggestionEngine(modelContext: modelContext)
        suggestion = await engine.suggestion(targetKind: targetKind, categoryIDs: selectedCategories,
            periodType: periodType, currencyCode: currencyCode, rates: CurrencyManager.shared.rates)
        isLoadingSuggestion = false
    }

    private func save() {
        guard let parsedAmount else { return }
        let chosen = expenseCategories.filter { selectedCategories.contains($0.id) }
        let budget = Budget(name: name.isEmpty ? nil : name, amountLimit: parsedAmount,
                            currencyCode: currencyCode, periodType: periodType,
                            startDate: periodType == .custom ? customStart : Date(),
                            customEndDate: periodType == .custom ? customEnd : nil,
                            category: nil, isRecurring: periodType != .custom,
                            alertAt80: alertMode.thresholds.contains(80),
                            alertAt100: alertMode.thresholds.contains(100),
                            categories: targetKind == .categories ? chosen : nil)
        budget.targetKind = targetKind
        budget.alertMode = alertMode
        modelContext.insert(budget)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            HapticManager.shared.success()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SuggestionRequest: Hashable {
    let targetKind: BudgetTargetKind
    let categoryIDs: [UUID]
    let periodType: BudgetPeriodType
    let currencyCode: String
}

#Preview {
    AddBudgetView().modelContainer(for: [Budget.self, Category.self], inMemory: true)
}

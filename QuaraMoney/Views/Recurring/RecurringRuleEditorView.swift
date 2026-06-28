import SwiftUI
import SwiftData

/// Add **or** edit a recurring rule. `rule == nil` creates a new rule;
/// otherwise the passed rule is edited in place.
///
/// Editing only ever changes how *future* occurrences are generated — already
/// posted transactions are untouched (surfaced to the user via the footer note).
struct RecurringRuleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]
    @Query(filter: #Predicate<Category> { $0.deletedAt == nil }, sort: \Category.name) private var categories: [Category]

    private let rule: RecurringRule?

    @State private var name: String
    @State private var amountString: String
    @State private var type: TransactionType
    @State private var frequency: Frequency
    @State private var startDate: Date
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var remindersEnabled: Bool
    @State private var isActive: Bool
    @State private var selectedWallet: Wallet?
    @State private var selectedCategory: Category?
    @State private var currencyCode: String
    /// Once the user picks a currency explicitly we stop auto-following the
    /// wallet's currency (so a USD rule paid from a KHR wallet stays USD).
    @State private var currencyManuallySet: Bool = false
    @State private var showCurrencyPicker = false

    init(rule: RecurringRule? = nil) {
        self.rule = rule
        _name = State(initialValue: rule?.name ?? "")
        _amountString = State(initialValue: rule.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _type = State(initialValue: rule?.type ?? .expense)
        _frequency = State(initialValue: rule?.frequency ?? .monthly)
        _startDate = State(initialValue: rule?.startDate ?? Date())
        _hasEndDate = State(initialValue: rule?.endDate != nil)
        _endDate = State(initialValue: rule?.endDate ?? Date())
        _remindersEnabled = State(initialValue: rule?.remindersEnabled ?? true)
        _isActive = State(initialValue: rule?.isActive ?? true)
        _selectedWallet = State(initialValue: rule?.wallet)
        _selectedCategory = State(initialValue: rule?.category)
        _currencyCode = State(initialValue: rule?.currencyCode ?? rule?.wallet?.currencyCode ?? CurrencyManager.shared.preferredCurrencyCode)
        // Existing rules already carry an explicit currency; preserve it.
        _currencyManuallySet = State(initialValue: rule != nil)
    }

    private var isEditing: Bool { rule != nil }

    private var typedCategories: [Category] {
        categories.filter { $0.type == type }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.Budget.details) {
                    TextField(L10n.Recurring.name, text: $name)

                    HStack {
                        Button {
                            showCurrencyPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(currencyCode)
                                    .font(.app(.subheadline, weight: .bold))
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                    }

                    Picker(L10n.Recurring.type, selection: $type) {
                        Text(L10n.Transaction.TransactionType.expense).tag(TransactionType.expense)
                        Text(L10n.Transaction.TransactionType.income).tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)

                    Picker(L10n.Recurring.frequency, selection: $frequency) {
                        ForEach(Frequency.allCases) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }

                    DatePicker(L10n.Budget.startDate, selection: $startDate, displayedComponents: [.date])
                }

                Section(L10n.Recurring.assignments) {
                    if wallets.isEmpty {
                        Text(L10n.Recurring.createWalletFirst)
                            .foregroundStyle(.red)
                    } else {
                        Picker(L10n.Wallet.selectWallet, selection: $selectedWallet) {
                            Text(L10n.Wallet.selectWallet).tag(nil as Wallet?)
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(wallet as Wallet?)
                            }
                        }
                    }

                    Picker(L10n.Category.select, selection: $selectedCategory) {
                        Text(L10n.Category.select).tag(nil as Category?)
                        ForEach(typedCategories) { category in
                            Label(category.name, systemImage: category.icon)
                                .tag(category as Category?)
                        }
                    }
                }

                Section {
                    Toggle(L10n.Recurring.setEndDate, isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker(L10n.Recurring.endDate, selection: $endDate, in: startDate..., displayedComponents: [.date])
                    }
                }

                Section {
                    Toggle(L10n.Recurring.reminderToggle, isOn: $remindersEnabled)
                }

                if isEditing {
                    Section {
                        Toggle(L10n.Recurring.pause, isOn: Binding(get: { !isActive }, set: { isActive = !$0 }))
                    } footer: {
                        Text(L10n.Recurring.editFutureNote)
                    }
                }
            }
            .navigationTitle(isEditing ? L10n.Recurring.edit : L10n.Recurring.new)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.isEmpty || amountString.isEmpty || selectedWallet == nil)
                }
            }
            .onAppear {
                // Scalars are already seeded in init — do NOT re-assign them here.
                // onAppear can fire again (e.g. returning from a pushed picker),
                // and re-reading the stored rule would silently revert the user's
                // in-progress edits (frequency, dates, amount…).
                if let rule = rule {
                    if selectedWallet == nil {
                        selectedWallet = wallets.first { $0.id == rule.wallet?.id }
                    }
                    if selectedCategory == nil {
                        selectedCategory = categories.first { $0.id == rule.category?.id }
                    }
                } else if let firstWallet = wallets.first, selectedWallet == nil {
                    selectedWallet = firstWallet
                    if !currencyManuallySet { currencyCode = firstWallet.currencyCode }
                }
            }
            .onChange(of: type) { _, _ in
                // Selected category may belong to the other type after a toggle.
                if let selected = selectedCategory, selected.type != type {
                    selectedCategory = nil
                }
            }
            .onChange(of: selectedWallet) { _, newWallet in
                // For a new rule, default the amount currency to the chosen
                // wallet's — until the user overrides it explicitly.
                if !currencyManuallySet, let newWallet { currencyCode = newWallet.currencyCode }
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    // Mark "manual" only on an explicit pick so the wallet-follow
                    // default doesn't immediately disable itself.
                    CurrencySelectionView(selection: Binding(
                        get: { currencyCode },
                        set: { currencyCode = $0; currencyManuallySet = true }
                    ))
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func save() {
        let normalizedAmountString = amountString.replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(string: normalizedAmountString), let wallet = selectedWallet else { return }

        let cleanStartDate = Calendar.current.startOfDay(for: startDate)
        let cleanEndDate = hasEndDate ? Calendar.current.startOfDay(for: endDate) : nil

        // Evaluate if the schedule changed BEFORE mutating the target.
        // Re-anchor only when a *timing* input actually changed (or it's a new
        // rule). Editing other fields must NOT move nextDueDate — and must not
        // undo occurrences the user already skipped (skips advance nextDueDate
        // without creating a transaction, so "no transactions" ≠ "untouched").
        let expectedFirstDue = RecurringRuleService.firstDueDate(startDate: cleanStartDate, frequency: frequency)
        let scheduleChanged = !isEditing ||
                              rule?.startDate != cleanStartDate ||
                              rule?.frequency != frequency
        let isResuming = isEditing && isActive && !(rule?.isActive ?? false)

        let target: RecurringRule
        if let rule {
            target = rule
        } else {
            target = RecurringRule(name: name, amount: amount, currencyCode: currencyCode,
                                   frequency: frequency, startDate: cleanStartDate, type: type)
            modelContext.insert(target)
        }

        target.name = name
        target.amount = amount
        target.type = type
        target.currencyCode = currencyCode
        target.frequency = frequency
        target.startDate = cleanStartDate
        target.endDate = cleanEndDate
        target.remindersEnabled = remindersEnabled
        target.isActive = isActive
        target.wallet = wallet
        target.category = selectedCategory

        // Schedule: re-anchor for a new rule or a start/frequency change. Resuming
        // a paused rule skips forward past elapsed occurrences (no backfill),
        // matching the list's swipe-to-resume behavior.
        if scheduleChanged {
            target.nextDueDate = expectedFirstDue
        } else if isResuming {
            target.nextDueDate = RecurringRuleService.resumedNextDueDate(for: target)
        }

        target.updatedAt = Date()
        target.needsSync = true

        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)

        // Keep the due-date reminder in sync with the saved state.
        let ruleID = target.id
        if remindersEnabled && isActive {
            Task {
                _ = await RecurringNotificationService.requestAuthorization()
                await RecurringNotificationService.reschedule(for: target)
            }
        } else {
            RecurringNotificationService.cancel(for: ruleID)
        }
    }
}

#Preview {
    RecurringRuleEditorView()
        .modelContainer(for: [RecurringRule.self, Wallet.self, Category.self], inMemory: true)
}

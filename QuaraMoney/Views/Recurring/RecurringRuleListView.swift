import SwiftUI
import SwiftData

/// The Recurring screen: two lenses on the same rules.
/// - **Rules** (default) lists every rule exactly once, grouped by type, with
///   how many there are and what they cost per month on average.
/// - **Upcoming** shows one calendar month of dated payments and is where due
///   occurrences are posted or skipped (notification deep links land here).
struct RecurringRuleListView: View {
    enum Tab: Hashable {
        case rules, upcoming
    }

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil }, sort: \RecurringRule.nextDueDate) private var rules: [RecurringRule]

    @State private var tab: Tab
    /// Months ahead of the current one that the Upcoming tab is showing.
    @State private var monthOffset = 0
    @State private var editorTarget: EditorTarget?
    @State private var editingDueRule: RecurringRule?
    @State private var transactionToEdit: Transaction?
    @State private var lastMutation: RecurringMutation?
    @State private var confirmPostAll = false
    @State private var confirmSkipAll = false

    /// How far ahead the Upcoming tab can step.
    private static let maxMonthsAhead = 12

    init(initialTab: Tab = .rules) {
        _tab = State(initialValue: initialTab)
    }

    /// Everything the Rules tab renders, derived from `rules` in one pass.
    private struct RuleGroups {
        var expenses: [RecurringRule] = []
        var income: [RecurringRule] = []
        /// Paused rules plus rules that have run past their end date.
        var inactive: [RecurringRule] = []
        var pausedCount = 0
        var hasEndedRules = false
        var dueRuleNames: [String] = []
        /// Due occurrences, not rules — one overdue weekly rule can owe several.
        var dueOccurrences = 0
        var dueExpense: Decimal = 0
        var dueIncome: Decimal = 0
        var monthlyExpense: Decimal = 0
        var monthlyIncome: Decimal = 0
    }

    private func makeGroups(currency: String) -> RuleGroups {
        let manager = CurrencyManager.shared
        var groups = RuleGroups()
        for rule in rules {
            let pending = RecurringRuleService.pendingOccurrenceCount(for: rule)
            if pending > 0 {
                groups.dueRuleNames.append(rule.name)
                groups.dueOccurrences += pending
                let owed = manager.convert(amount: rule.amount, from: rule.currencyCode, to: currency) * Decimal(pending)
                if rule.type == .income { groups.dueIncome += owed } else { groups.dueExpense += owed }
            }

            guard rule.isActive, !RecurringRuleService.hasEnded(rule) else {
                groups.inactive.append(rule)
                if rule.isActive { groups.hasEndedRules = true } else { groups.pausedCount += 1 }
                continue
            }

            // Convert each rule's monthly average before summing — rules can mix
            // currencies (USD + KHR), so a raw sum would be meaningless.
            let monthly = manager.convert(
                amount: RecurringRuleService.monthlyEquivalent(amount: rule.amount, frequency: rule.frequency, interval: rule.interval),
                from: rule.currencyCode,
                to: currency
            )
            if rule.type == .income {
                groups.income.append(rule)
                groups.monthlyIncome += monthly
            } else {
                groups.expenses.append(rule)
                groups.monthlyExpense += monthly
            }
        }
        return groups
    }

    private var displayedMonthStart: Date {
        let calendar = Calendar.current
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        return calendar.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    var body: some View {
        let currency = CurrencyManager.shared.preferredCurrencyCode
        let groups = makeGroups(currency: currency)

        List {
            if !rules.isEmpty {
                Section {
                    Picker("recurring.screenTitle".localized, selection: $tab) {
                        Text("recurring.tab.rules".localized).tag(Tab.rules)
                        Text("recurring.tab.upcoming".localized).tag(Tab.upcoming)
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                .listRowBackground(Color.clear)

                switch tab {
                case .rules:
                    rulesSections(groups, currency: currency)
                case .upcoming:
                    RecurringUpcomingSections(
                        rules: rules,
                        monthStart: displayedMonthStart,
                        canGoBack: monthOffset > 0,
                        canGoForward: monthOffset < Self.maxMonthsAhead,
                        actions: upcomingActions
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("recurring.screenTitle".localized)
        .syncPullToRefresh(modelContext)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { editorTarget = .new }) {
                    Label(L10n.Recurring.add, systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                RecurringRuleEditorView()
            case .existing(let rule):
                RecurringRuleEditorView(rule: rule)
            }
        }
        .sheet(item: $editingDueRule) { rule in
            RecurringPostEditorView(rule: rule)
        }
        .sheet(item: $transactionToEdit) { transaction in
            AddTransactionContainer(transaction: transaction, isNewTransaction: false)
        }
        .confirmationDialog(L10n.Recurring.Review.postAll, isPresented: $confirmPostAll, titleVisibility: .visible) {
            Button(L10n.Recurring.Review.postAll) { postAll() }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Recurring.Review.postAllMessage(groups.dueOccurrences))
        }
        .confirmationDialog(L10n.Recurring.Review.skipAll, isPresented: $confirmSkipAll, titleVisibility: .visible) {
            Button(L10n.Recurring.Review.skipAll, role: .destructive) { skipAll() }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Recurring.Review.skipAllMessage(groups.dueOccurrences))
        }
        .undoToast($lastMutation, message: { $0.undoSummary }) { mutation in
            RecurringRuleService.undo(mutation, in: modelContext)
        }
        .overlay {
            if rules.isEmpty {
                AppEmptyStateView(
                    L10n.Recurring.emptyTitle,
                    systemImage: "calendar.badge.clock",
                    description: L10n.Recurring.emptyState
                )
            }
        }
    }

    // MARK: - Rules tab

    @ViewBuilder
    private func rulesSections(_ groups: RuleGroups, currency: String) -> some View {
        if groups.dueOccurrences > 0 {
            Section {
                RecurringReviewCard(
                    occurrenceCount: groups.dueOccurrences,
                    ruleNames: groups.dueRuleNames,
                    expense: groups.dueExpense,
                    income: groups.dueIncome,
                    currency: currency
                ) {
                    withAnimation {
                        monthOffset = 0
                        tab = .upcoming
                    }
                }
            }
        }

        Section {
            RecurringRulesSummaryCard(
                ruleCount: rules.count,
                pausedCount: groups.pausedCount,
                monthlyExpense: groups.monthlyExpense,
                monthlyIncome: groups.monthlyIncome,
                currency: currency
            )
            .listRowInsets(EdgeInsets()) // Full-width card — aligns with sections below
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        if !groups.expenses.isEmpty {
            Section(header: Text(RecurringFormat.sectionTitle(L10n.Recurring.expenses, count: groups.expenses.count))) {
                ForEach(groups.expenses) { rule in
                    ruleRow(for: rule, currency: currency)
                }
            }
        }

        if !groups.income.isEmpty {
            Section(header: Text(RecurringFormat.sectionTitle(L10n.Recurring.income, count: groups.income.count))) {
                ForEach(groups.income) { rule in
                    ruleRow(for: rule, currency: currency)
                }
            }
        }

        if !groups.inactive.isEmpty {
            let title = groups.hasEndedRules ? "recurring.inactive".localized : L10n.Recurring.paused
            Section(header: Text(RecurringFormat.sectionTitle(title, count: groups.inactive.count))) {
                ForEach(groups.inactive) { rule in
                    ruleRow(for: rule, currency: currency)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleRow(for rule: RecurringRule, currency: String) -> some View {
        NavigationLink {
            RecurringRuleDetailView(rule: rule)
        } label: {
            RecurringRuleRow(rule: rule, currency: currency)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(rule) } label: {
                Label(L10n.Common.delete, systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { togglePause(rule) } label: {
                Label(rule.isActive ? L10n.Recurring.pause : L10n.Recurring.resume,
                      systemImage: rule.isActive ? "pause.circle" : "play.circle")
            }
            .tint(rule.isActive ? .orange : .green)
        }
    }

    // MARK: - Upcoming tab

    private var upcomingActions: RecurringUpcomingSections.Actions {
        RecurringUpcomingSections.Actions(
            previousMonth: { withAnimation { monthOffset = max(0, monthOffset - 1) } },
            nextMonth: { withAnimation { monthOffset = min(Self.maxMonthsAhead, monthOffset + 1) } },
            post: { rule in
                let mutation = RecurringRuleService.post(rule: rule, in: modelContext)
                lastMutation = mutation
                HapticManager.shared.notification(type: mutation == nil ? .error : .success)
            },
            skip: { rule in
                lastMutation = RecurringRuleService.skip(rule: rule, in: modelContext)
            },
            edit: { rule in editingDueRule = rule },
            postAll: { confirmPostAll = true },
            skipAll: { confirmSkipAll = true },
            openTransaction: { transaction in transactionToEdit = transaction }
        )
    }

    private func postAll() {
        for rule in rules where RecurringRuleService.isDue(rule) {
            RecurringRuleService.postAllDue(rule: rule, in: modelContext)
        }
        HapticManager.shared.notification(type: .success)
    }

    private func skipAll() {
        for rule in rules where RecurringRuleService.isDue(rule) {
            RecurringRuleService.skipAllDue(rule: rule, in: modelContext)
        }
    }

    // MARK: - Rule mutations

    private func togglePause(_ rule: RecurringRule) {
        if !rule.isActive, rule.wallet?.isSavings == true {
            rule.pauseReason = .invalidSavingsWallet
            rule.updatedAt = Date()
            rule.needsSync = true
            try? modelContext.save()
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
            return
        }
        rule.isActive.toggle()
        // On resume, skip forward past any occurrences that elapsed while paused
        // rather than resurfacing them as a backlog of due payments.
        if rule.isActive {
            rule.pauseReason = nil
            rule.nextDueDate = RecurringRuleService.resumedNextDueDate(for: rule)
        }
        rule.updatedAt = Date()
        rule.needsSync = true
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        // Keep the due-date reminder in sync: a paused rule must stop reminding,
        // a resumed one must be re-armed.
        RecurringNotificationService.rescheduleDetached(for: rule)
    }

    private func delete(_ rule: RecurringRule) {
        let ruleID = rule.id
        SoftDeleteService.delete(rule)
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        // Tear down the pending reminder so a deleted rule can't still fire.
        RecurringNotificationService.cancel(for: ruleID)
    }
}

enum EditorTarget: Identifiable {
    case new
    case existing(RecurringRule)
    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let r): return r.id.uuidString
        }
    }
}

#Preview {
    NavigationStack {
        RecurringRuleListView()
    }
    .modelContainer(for: [RecurringRule.self, Wallet.self, Category.self], inMemory: true)
}

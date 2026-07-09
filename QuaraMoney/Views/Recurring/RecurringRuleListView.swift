import SwiftUI
import SwiftData

struct RecurringRuleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil }, sort: \RecurringRule.nextDueDate) private var rules: [RecurringRule]
    
    @State private var editorTarget: EditorTarget?
    
    private var dueRules: [RecurringRule] { rules.filter { RecurringRuleService.isDue($0) } }

    // Date buckets cover ACTIVE rules only — paused rules don't generate, so
    // bucketing them by "Overdue"/"This Month" is misleading. They get their own
    // section so they stay findable and resumable.
    private var activeRules: [RecurringRule] { rules.filter { $0.isActive } }
    private var paused: [RecurringRule] { rules.filter { !$0.isActive } }

    // "Overdue" means due *before today* — including earlier this month — so a
    // past-due rule never hides under "This Month".
    private var overdue: [RecurringRule] {
        let todayStart = Calendar.current.startOfDay(for: Date())
        return activeRules.filter { rule in
            rule.nextDueDate < todayStart
        }
    }

    // "This Month" is the remainder of the current month from today onward.
    private var thisMonth: [RecurringRule] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())),
              let startOfNextMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth) else { return [] }

        return activeRules.filter { rule in
            rule.nextDueDate >= todayStart && rule.nextDueDate < startOfNextMonth
        }
    }

    private var nextMonth: [RecurringRule] {
        let cal = Calendar.current
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())),
              let startOfNextMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth),
              let startOfNextNextMonth = cal.date(byAdding: .month, value: 2, to: startOfMonth) else { return [] }

        return activeRules.filter { rule in
            rule.nextDueDate >= startOfNextMonth && rule.nextDueDate < startOfNextNextMonth
        }
    }

    private var later: [RecurringRule] {
        let cal = Calendar.current
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())),
              let startOfNextNextMonth = cal.date(byAdding: .month, value: 2, to: startOfMonth) else { return [] }

        return activeRules.filter { rule in
            rule.nextDueDate >= startOfNextNextMonth
        }
    }

    var body: some View {
        List {
            Section {
                RecurringProgressHeaderView(modelContext: modelContext)
                    .listRowInsets(EdgeInsets()) // Full-width card — aligns with sections below
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            if !dueRules.isEmpty {
                Section {
                    NavigationLink(destination: RecurringReviewView(allRules: rules)) {
                        Label(L10n.Recurring.Review.banner(dueRules.count), systemImage: "tray.full")
                            .font(.app(.headline))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if !overdue.isEmpty {
                Section(header: sectionHeader(title: L10n.Recurring.overdue, rules: overdue)) {
                    ForEach(overdue) { rule in
                        ruleRow(for: rule)
                    }
                }
            }

            if !thisMonth.isEmpty {
                Section(header: sectionHeader(title: L10n.Recurring.thisMonth, rules: thisMonth)) {
                    ForEach(thisMonth) { rule in
                        ruleRow(for: rule)
                    }
                }
            }
            
            if !nextMonth.isEmpty {
                Section(header: sectionHeader(title: L10n.Recurring.nextMonth, rules: nextMonth)) {
                    ForEach(nextMonth) { rule in
                        ruleRow(for: rule)
                    }
                }
            }
            
            if !later.isEmpty {
                Section(header: sectionHeader(title: L10n.Recurring.later, rules: later)) {
                    ForEach(later) { rule in
                        ruleRow(for: rule)
                    }
                }
            }

            if !paused.isEmpty {
                Section(header: Text(L10n.Recurring.paused)) {
                    ForEach(paused) { rule in
                        ruleRow(for: rule)
                    }
                }
            }
        }
        .navigationTitle(L10n.Recurring.title)
        .navigationBarTitleDisplayMode(.inline)
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
    
    @ViewBuilder
    private func sectionHeader(title: String, rules: [RecurringRule]) -> some View {
        // Convert every rule into the preferred currency before summing — rules
        // in a section can mix currencies (USD + KHR), so a raw numeric sum and a
        // single first-rule currency label would be meaningless.
        let manager = CurrencyManager.shared
        let target = manager.preferredCurrencyCode
        let converted: (RecurringRule) -> Decimal = { rule in
            manager.convert(amount: rule.amount, from: rule.currencyCode, to: target)
        }
        let expenses = rules.filter { $0.type == .expense }.reduce(Decimal(0)) { $0 + converted($1) }
        let incomes = rules.filter { $0.type == .income }.reduce(Decimal(0)) { $0 + converted($1) }

        HStack {
            Text(title)
            Spacer()
            if expenses > 0 || incomes > 0 {
                HStack(spacing: 8) {
                    if expenses > 0 {
                        Text("-" + expenses.formattedAmount(for: target))
                            .foregroundStyle(.primary)
                    }
                    if incomes > 0 {
                        Text("+" + incomes.formattedAmount(for: target))
                            .foregroundStyle(.green)
                    }
                }
                .font(.app(.caption, weight: .semibold))
            }
        }
    }
    
    @ViewBuilder
    private func ruleRow(for rule: RecurringRule) -> some View {
        NavigationLink {
            RecurringRuleDetailView(rule: rule)
        } label: {
            RecurringRuleRow(rule: rule)
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
    
    private func togglePause(_ rule: RecurringRule) {
        rule.isActive.toggle()
        // On resume, skip forward past any occurrences that elapsed while paused
        // rather than resurfacing them as a backlog in the review inbox.
        if rule.isActive {
            rule.nextDueDate = RecurringRuleService.resumedNextDueDate(for: rule)
        }
        rule.updatedAt = Date()
        rule.needsSync = true
        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        // Keep the due-date reminder in sync: a paused rule must stop reminding,
        // a resumed one must be re-armed.
        Task { await RecurringNotificationService.reschedule(for: rule) }
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

private struct RecurringRuleRow: View {
    let rule: RecurringRule

    private var tint: Color {
        rule.type == .income ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor
    }

    private var icon: String {
        rule.category?.icon ?? (rule.type == .income ? "arrow.down.left" : "arrow.up.right")
    }

    private var signedAmount: String {
        let formatted = rule.amount.formattedAmount(for: rule.currencyCode)
        return rule.type == .income ? "+\(formatted)" : formatted
    }

    /// Relative due descriptor + color for the trailing chip.
    private var dueState: (text: String, color: Color)? {
        guard rule.isActive else { return nil }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        if rule.nextDueDate < todayStart {
            return (L10n.Recurring.overdue, .red)
        } else if cal.isDateInToday(rule.nextDueDate) {
            return (L10n.Recurring.dueToday, .orange)
        }
        return (rule.nextDueDate.appFormatted(date: .abbreviated, time: .omitted), .secondary)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Tinted icon badge
            Image(systemName: icon)
                .font(.app(.body, weight: .semibold))
                .foregroundStyle(rule.isActive ? tint : Color.secondary)
                .frame(width: 42, height: 42)
                .background(
                    (rule.isActive ? tint : Color.secondary).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.name)
                        .font(.app(.headline))
                        .lineLimit(1)
                    if !rule.isActive {
                        Text(L10n.Recurring.paused)
                            .font(.app(.caption2, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                if let due = dueState {
                    HStack(spacing: 5) {
                        Text(rule.frequency.displayName(interval: rule.interval))
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary)
                        Text(due.text)
                            .foregroundStyle(due.color)
                    }
                    .font(.app(.caption))
                    .lineLimit(1)
                } else {
                    Text(rule.frequency.displayName(interval: rule.interval))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(signedAmount)
                .font(.app(.body, weight: .semibold))
                .foregroundStyle(rule.type == .income ? tint : Color.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    RecurringRuleListView()
        .modelContainer(for: [RecurringRule.self, Wallet.self, Category.self], inMemory: true)
}

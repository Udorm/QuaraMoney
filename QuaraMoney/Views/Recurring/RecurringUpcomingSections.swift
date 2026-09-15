import SwiftUI
import SwiftData

/// The Upcoming tab: one calendar month of dated payments — due now, still
/// scheduled, and already paid — under a progress card built from the same
/// numbers. Owns the month's transaction query; every action is reported back
/// to `RecurringRuleListView`, which holds the sheets, dialogs and undo toast.
struct RecurringUpcomingSections: View {
    struct Actions {
        var previousMonth: () -> Void
        var nextMonth: () -> Void
        var post: (RecurringRule) -> Void
        var skip: (RecurringRule) -> Void
        var edit: (RecurringRule) -> Void
        var postAll: () -> Void
        var skipAll: () -> Void
        var openTransaction: (Transaction) -> Void
    }

    let rules: [RecurringRule]
    let monthStart: Date
    let canGoBack: Bool
    let canGoForward: Bool
    let actions: Actions

    // Month-bounded fetch; the summary keeps only recurring transactions
    // (SwiftData can't predicate the optional `recurringRule` relationship).
    @Query private var monthTransactions: [Transaction]

    init(rules: [RecurringRule], monthStart: Date, canGoBack: Bool, canGoForward: Bool, actions: Actions) {
        self.rules = rules
        self.monthStart = monthStart
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.actions = actions
        let start = monthStart
        let end = Calendar.current.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        _monthTransactions = Query(filter: #Predicate<Transaction> { txn in
            txn.deletedAt == nil && txn.date >= start && txn.date < end
        })
    }

    var body: some View {
        let currency = CurrencyManager.shared.preferredCurrencyCode
        let summary = RecurringMonthSummary.build(
            rules: rules,
            transactions: monthTransactions,
            monthStart: monthStart,
            rates: CurrencyManager.shared.rates,
            currency: currency
        )

        Section {
            RecurringMonthProgressCard(
                monthStart: monthStart,
                paid: summary.paidTotals,
                expected: summary.expectedTotals,
                currency: currency,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                onBack: actions.previousMonth,
                onForward: actions.nextMonth
            )
            .listRowInsets(EdgeInsets()) // Full-width card — aligns with sections below
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        if !summary.due.isEmpty {
            Section {
                ForEach(summary.due) { item in
                    RecurringDueRow(
                        rule: item.rule,
                        onPost: { actions.post(item.rule) },
                        onSkip: { actions.skip(item.rule) },
                        onEdit: { actions.edit(item.rule) },
                        showsDateTile: true
                    )
                }
            } header: {
                HStack {
                    Text(RecurringFormat.sectionTitle("recurring.upcoming.due".localized, count: summary.dueOccurrenceCount))
                    Spacer()
                    if summary.dueOccurrenceCount > 1 {
                        // Tap posts everything; long-press offers Skip All.
                        Menu {
                            Button(L10n.Recurring.Review.skipAll, systemImage: "forward.end", role: .destructive, action: actions.skipAll)
                        } label: {
                            Text(L10n.Recurring.Review.postAll)
                                .appFont(.subheadline, weight: .semibold)
                        } primaryAction: {
                            actions.postAll()
                        }
                    }
                }
            }
        }

        if !summary.upcoming.isEmpty {
            Section {
                ForEach(summary.upcoming) { occurrence in
                    NavigationLink {
                        LazyView(RecurringRuleDetailView(rule: occurrence.rule))
                    } label: {
                        RecurringOccurrenceRow(rule: occurrence.rule, date: occurrence.date, currency: currency)
                    }
                }
            } header: {
                RecurringSectionHeader(
                    title: RecurringFormat.sectionTitle("recurring.upcoming.scheduled".localized, count: summary.upcoming.count),
                    totals: summary.upcomingTotals,
                    currency: currency
                )
            }
        }

        if !summary.paid.isEmpty {
            Section {
                ForEach(summary.paid) { transaction in
                    Button {
                        actions.openTransaction(transaction)
                    } label: {
                        RecurringPaidRow(transaction: transaction)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                RecurringSectionHeader(
                    title: RecurringFormat.sectionTitle("recurring.upcoming.paid".localized, count: summary.paid.count),
                    totals: summary.paidTotals,
                    currency: currency
                )
            }
        }

        if rules.contains(where: { !$0.isActive }) {
            Section {
            } footer: {
                Text("recurring.upcoming.pausedFootnote".localized)
            }
        }
    }
}

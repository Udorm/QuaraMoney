import SwiftUI
import SwiftData

struct EventDetailViewV3: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    
    // -- Query Data --
    @Query(sort: [SortDescriptor(\EventMember.sortOrder), SortDescriptor(\EventMember.name)]) private var allMembers: [EventMember]
    @Query(sort: \EventLedgerTransaction.date, order: .reverse) private var allLedgerTransactions: [EventLedgerTransaction]
    @Query(sort: \EventLedgerParticipant.orderIndex) private var allParticipantLinks: [EventLedgerParticipant]
    
    // -- UI State --
    @State private var showingAddMember = false
    @State private var showingAddTransaction = false
    @State private var showingEditEvent = false
    @State private var showingSettlement = false
    
    @State private var memberToEdit: EventMember?
    @State private var transactionToEdit: EventLedgerTransaction?
    @State private var errorMessage: String?
    
    // -- Computed Business Logic --
    private var service: EventLedgerService {
        EventLedgerService(modelContext: modelContext)
    }
    
    private var members: [EventMember] {
        allMembers.filter { $0.event?.id == event.id }
    }
    
    // Members specifically for settlement (excluding virtual budget pool users)
    private var settlementMembers: [EventMember] {
        members.filter { !$0.isBudgetPool }
    }
    
    private var budgetPoolMemberIds: Set<UUID> {
        Set(members.filter(\.isBudgetPool).map(\.id))
    }
    
    private var ledgerTransactions: [EventLedgerTransaction] {
        allLedgerTransactions.filter { $0.event?.id == event.id }
    }
    
    private var activeTransactions: [EventLedgerTransaction] {
        ledgerTransactions.filter { !$0.isDeleted }
    }
    
    private var participantLinks: [EventLedgerParticipant] {
        allParticipantLinks.filter { $0.transaction?.event?.id == event.id }
    }
    
    private var linksByTransactionId: [UUID: [EventLedgerParticipant]] {
        var map: [UUID: [EventLedgerParticipant]] = [:]
        for link in participantLinks {
            guard let transactionId = link.transaction?.id else { continue }
            map[transactionId, default: []].append(link)
        }
        return map
    }
    
    private var settlementResult: EventSettlementResult {
        EventSettlementEngine.compute(
            memberIds: settlementMembers.map(\.id),
            transactions: activeTransactions,
            participantLinks: linksByTransactionId,
            budgetPoolMemberIds: budgetPoolMemberIds
        )
    }
    
    private var balanceByMemberId: [UUID: EventMemberLedgerBalance] {
        Dictionary(uniqueKeysWithValues: settlementResult.balances.map { ($0.memberId, $0) })
    }
    
    private var memberById: [UUID: EventMember] {
        Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
    }
    
    private var localMember: EventMember? {
        settlementMembers.first(where: { $0.isLocalUser })
    }
    
    private var localNetMinor: Int64 {
        guard let localMember else { return 0 }
        return balanceByMemberId[localMember.id]?.netMinor ?? 0
    }
    
    private var eventColor: Color {
        Color(hex: event.colorHex) ?? .blue
    }
    
    private var settlementStatus: EventSettlementStatus {
        guard settlementResult.totalCostMinor > 0 else { return .active }
        if event.confirmedSettlementRevision == event.ledgerRevision { return .settled }
        return .readyToSettle
    }
    
    var body: some View {
        List {
            // 1. Map Header Section
            Section {
                EventMapHeaderView(event: event, members: settlementMembers)
                    .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            
            // 2. Settlement Action Card (Replaces the one in Summary Card)
            Section {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Expenses")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                            Text(formatMinor(settlementResult.totalCostMinor))
                                .font(.app(.headline, weight: .bold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Your Status")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                            Text(formatMinor(localNetBalance()))
                                .font(.app(.headline, weight: .bold))
                                .foregroundStyle(localNetBalance() >= 0 ? .green : .red)
                        }
                    }
                    .padding(.bottom, 16)
                    
                    HStack(spacing: 12) {
                        Button {
                            showingAddTransaction = true
                        } label: {
                            Label("Add Expense", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(eventColor)
                        
                        Button {
                            showingSettlement = true
                        } label: {
                            Label("Settle Up", systemImage: "banknote")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(eventColor)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // 3. Transactions List Sections
            EventTransactionListView(
                transactions: activeTransactions,
                linksByTransactionId: linksByTransactionId,
                memberById: memberById,
                event: event,
                onSelect: { transaction in
                     transactionToEdit = transaction
                },
                onDelete: { transaction in
                    deleteTransaction(transaction)
                }
            )
        }
        .listStyle(.grouped)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(event.title)
                    .font(.app(.headline))
                    .foregroundStyle(.primary)
            }
            
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                    
                    Button {
                        showingEditEvent = true
                    } label: {
                        Label("Edit Event", systemImage: "pencil")
                    }
                    
                    Button {
                        // Export logic
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        // Sheets
        .sheet(isPresented: $showingAddMember) {
            AddEventMemberView(event: event, memberToEdit: nil)
        }
        .sheet(item: $memberToEdit) { member in
            AddEventMemberView(event: event, memberToEdit: member)
        }
        .sheet(isPresented: $showingAddTransaction) {
            AddEventLedgerTransactionView(event: event)
        }
        .sheet(item: $transactionToEdit) { transaction in
            AddEventLedgerTransactionView(event: event, transactionToEdit: transaction)
        }
        .sheet(isPresented: $showingEditEvent) {
            AddEventView(eventToEdit: event)
        }
        .sheet(isPresented: $showingSettlement) {
            EventSettlementView(event: event)
        }

        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            prepareEventContext()
        }
    }
    
    // -- Actions --
    
    private func formatMinor(_ value: Int64) -> String {
        MoneyMinorUnitConverter
            .fromMinorUnits(value, currencyCode: event.currencyCode)
            .formatted(.currency(code: event.currencyCode))
    }
    
    private func localNetBalance() -> Int64 {
        localNetMinor
    }
    
    private func prepareEventContext() {
        do {
            if event.ledgerMode != .isolatedV1 {
                event.ledgerMode = .isolatedV1
            }
            if event.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                event.currencyCode = CurrencyManager.shared.preferredCurrencyCode
            }
            _ = try service.ensureLocalMemberExists(for: event)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func deleteTransaction(_ transaction: EventLedgerTransaction) {
        do {
            try service.deleteTransaction(transaction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

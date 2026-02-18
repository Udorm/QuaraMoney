import SwiftUI
import SwiftData

struct EventDetailViewV2: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    
    // -- Query Data --
    @Query(sort: [SortDescriptor(\EventMember.name), SortDescriptor(\EventMember.sortOrder)]) private var allMembers: [EventMember]
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
            // 1. Summary Section
            Section {
                EventSummaryCard(
                    event: event,
                    totalCost: settlementResult.totalCostMinor,
                    userNetBalance: localNetMinor,
                    remainingPool: settlementResult.walletRemainingMinor,
                    settlementStatus: settlementStatus,
                    onAddExpense: { showingAddTransaction = true },
                    onSettle: { showingSettlement = true }
                )
            }
            
            Section {
                EventMemberSnapshotRow(
                    members: settlementMembers,
                    balances: balanceByMemberId,
                    event: event,
                    onAddMember: { showingAddMember = true },
                    onSelectMember: { member in memberToEdit = member }
                )
            } header: {
                HStack {
                    Text("Members")
                        .font(.app(.headline))
                    Spacer()
                    NavigationLink {
                        EventMemberListView(
                            event: event,
                            members: settlementMembers,
                            balances: balanceByMemberId,
                            onAddMember: { showingAddMember = true },
                            onSelectMember: { member in memberToEdit = member }
                        )
                    } label: {
                        Text("Show All")
                            .font(.app(.subheadline, weight: .medium))
                            .foregroundStyle(.blue)
                            .textCase(nil)
                    }
                }
            }
            .listRowBackground(Color(.secondarySystemGroupedBackground))
            
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
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(event.title)
//        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
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
    
    private func prepareEventContext() {
        do {
            if event.ledgerMode != .isolatedV1 {
                event.ledgerMode = .isolatedV1
            }
            if event.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                event.currencyCode = CurrencyManager.shared.preferredCurrencyCode
            }
            _ = try service.ensureLocalMemberExists(for: event)
            // Save logic if needed
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

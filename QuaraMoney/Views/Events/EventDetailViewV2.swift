import SwiftUI
import SwiftData

struct EventDetailViewV2: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    
    // -- Query Data --
    @Query private var allMembers: [EventMember]
    @Query(filter: #Predicate<EventLedgerTransaction> { $0.deletedAt == nil }, sort: \EventLedgerTransaction.date, order: .reverse) private var allLedgerTransactions: [EventLedgerTransaction]
    @Query(filter: #Predicate<EventLedgerParticipant> { $0.deletedAt == nil }, sort: \EventLedgerParticipant.orderIndex) private var allParticipantLinks: [EventLedgerParticipant]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]

    init(event: Event) {
        self.event = event
        let notDeleted = #Predicate<EventMember> { $0.deletedAt == nil }
        _allMembers = Query(filter: notDeleted, sort: [SortDescriptor(\EventMember.name), SortDescriptor(\EventMember.sortOrder)])
    }
    
    // -- UI State --
    @State private var showingAddMember = false
    @State private var showingAddTransaction = false
    @State private var showingEditEvent = false
    @State private var showingSettlement = false
    @State private var showingExportSpending = false
    @State private var showingAllMembers = false
    
    @State private var memberToEdit: EventMember?
    @State private var transactionToEdit: EventLedgerTransaction?
    @State private var errorMessage: String?
    @State private var exportSuccessMessage: String?
    
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
    
    private var linksByTransactionId: [UUID: [UUID]] {
        var map: [UUID: [UUID]] = [:]
        for link in participantLinks {
            guard let transactionId = link.transaction?.id else { continue }
            map[transactionId, default: []].append(link.memberId)
        }
        // For isSplitAll transactions, override with all current non-archived settlement members
        let activeMemberIds = settlementMembers.filter { !$0.isArchived }.map(\.id)
        for transaction in activeTransactions where transaction.isSplitAll {
            map[transaction.id] = activeMemberIds
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
        var map: [UUID: EventMember] = [:]
        for member in members {
            map[member.id] = member
        }
        return map
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
        let currentSettlement = settlementResult
        let balances = balanceByMemberId
        let status = settlementStatus
        let localNet = localNetMinor
        
        List {
            // 1. Summary Section
            Section {
                EventSummaryCard(
                    event: event,
                    totalCost: currentSettlement.totalCostMinor,
                    userNetBalance: localNet,
                    remainingPool: currentSettlement.walletRemainingMinor,
                    settlementStatus: status,
                    onAddExpense: { showingAddTransaction = true },
                    onSettle: { showingSettlement = true }
                )
            }
            
            Section {
                EventMemberSnapshotRow(
                    members: settlementMembers,
                    balances: balances,
                    event: event,
                    onAddMember: { showingAddMember = true },
                    onSelectMember: { member in memberToEdit = member }
                )
            } header: {
                HStack {
                    Text(L10n.EventDetail.members)
                        .font(.app(.headline))
                    Spacer()
                    Button {
                        showingAllMembers = true
                    } label: {
                        Text(L10n.EventDetail.showAll)
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
                        Label("event.edit".localized, systemImage: "pencil")
                    }
                    Button {
                        showingExportSpending = true
                    } label: {
                        Label(L10n.EventSettlement.exportToWallet, systemImage: "square.and.arrow.up")
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
        .sheet(isPresented: $showingExportSpending) {
            ExportSpendingSheet(
                event: event,
                wallets: wallets,
                localMember: localMember,
                service: service,
                onSuccess: { message in
                    exportSuccessMessage = message
                },
                onError: { message in
                    errorMessage = message
                }
            )
        }
        .navigationDestination(isPresented: $showingAllMembers) {
            EventMemberListView(
                event: event,
                members: settlementMembers,
                balances: balanceByMemberId, // use proper balances mapping
                onAddMember: { showingAddMember = true },
                onSelectMember: { member in memberToEdit = member },
                onDeleteMember: { member in
                    removeMember(member)
                }
            )
        }

        .alert(L10n.Common.error, isPresented: Binding(
            get: { errorMessage != nil },
            set: { _ in errorMessage = nil }
        )) {
            Button(L10n.Common.ok, role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? L10n.EventDetail.unknownError)
        }
        .alert(L10n.Common.ok, isPresented: Binding(
            get: { exportSuccessMessage != nil },
            set: { _ in exportSuccessMessage = nil }
        )) {
            Button(L10n.Common.ok, role: .cancel) { exportSuccessMessage = nil }
        } message: {
            Text(exportSuccessMessage ?? "")
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
    
    private func removeMember(_ member: EventMember) {
        do {
            try service.removeOrArchiveMember(member)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Export Spending Sheet

private struct ExportSpendingSheet: View {
    let event: Event
    let wallets: [Wallet]
    let localMember: EventMember?
    let service: EventLedgerService
    let onSuccess: (String) -> Void
    let onError: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedWallet: Wallet?
    @State private var isExporting = false
    @State private var alreadyExported = false
    @State private var spendingAmount: Int64 = 0
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(L10n.EventDetail.yourSpending)
                        Spacer()
                        Text(formatMinor(spendingAmount))
                            .font(.app(.headline, weight: .bold))
                            .foregroundStyle(ThemeManager.shared.expenseColor)
                    }
                } footer: {
                    Text("This is your share of all expenses in this event.")
                }
                
                if alreadyExported {
                    Section {
                        Label("Spending already exported for this event.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else if spendingAmount > 0 {
                    Section {
                        Picker("Wallet", selection: Binding(
                            get: { selectedWallet?.id },
                            set: { newId in
                                selectedWallet = wallets.first(where: { $0.id == newId })
                            }
                        )) {
                            ForEach(wallets) { wallet in
                                Text(wallet.name).tag(Optional(wallet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    } footer: {
                        Text("One expense transaction will be added to the selected wallet.")
                    }
                } else {
                    Section {
                        Text("No expenses to export.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.EventSettlement.exportToWallet)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isExporting ? L10n.EventDetail.exporting : L10n.EventDetail.export) {
                        performExport()
                    }
                    .disabled(isExporting || alreadyExported || spendingAmount <= 0 || selectedWallet == nil)
                }
            }
            .onAppear {
                loadState()
            }
        }
    }
    
    private func loadState() {
        if selectedWallet == nil {
            selectedWallet = wallets.first
        }
        guard let localMember else { return }
        
        do {
            alreadyExported = try service.hasExportedSpending(for: event, memberId: localMember.id)
            spendingAmount = try service.spendingShareMinor(for: event, memberId: localMember.id)
        } catch {
            onError(error.localizedDescription)
        }
    }
    
    private func performExport() {
        guard let localMember, let selectedWallet else { return }
        isExporting = true
        defer { isExporting = false }
        
        do {
            let transaction = try service.exportSpendingToWallet(
                for: event,
                member: localMember,
                wallet: selectedWallet
            )
            if transaction != nil {
                dismiss()
                onSuccess("Spending exported to \(selectedWallet.name)")
            } else {
                onError("No spending to export.")
                dismiss()
            }
        } catch {
            onError(error.localizedDescription)
            dismiss()
        }
    }
    
    private func formatMinor(_ value: Int64) -> String {
        MoneyMinorUnitConverter
            .fromMinorUnits(value, currencyCode: event.currencyCode)
            .formattedAmount(for: event.currencyCode)
    }
}

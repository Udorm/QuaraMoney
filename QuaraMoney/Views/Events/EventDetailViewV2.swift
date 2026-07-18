import SwiftUI
import SwiftData

struct EventDetailViewV2: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    
    // -- Query Data --
    @Query private var members: [EventMember]
    @Query private var ledgerTransactions: [EventLedgerTransaction]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]

    init(event: Event) {
        self.event = event
        let eventID = event.id
        _members = Query(
            filter: EventScopedQuery.members(eventID: eventID),
            sort: [SortDescriptor(\EventMember.name), SortDescriptor(\EventMember.sortOrder)]
        )
        _ledgerTransactions = Query(
            filter: EventScopedQuery.transactions(eventID: eventID),
            sort: [SortDescriptor(\EventLedgerTransaction.date, order: .reverse), SortDescriptor(\EventLedgerTransaction.id)]
        )
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
    @State private var recentlyDeletedTransaction: EventLedgerTransaction?
    
    // -- Computed Business Logic --
    private var service: EventLedgerService {
        EventLedgerService(modelContext: modelContext)
    }
    
    private struct DerivedState {
        let settlementMembers: [EventMember]
        let activeTransactions: [EventLedgerTransaction]
        let linksByTransactionID: [UUID: [UUID]]
        let settlement: EventSettlementResult
        let balancesByMemberID: [UUID: EventMemberLedgerBalance]
        let membersByID: [UUID: EventMember]
        let localMember: EventMember?
        let localNetMinor: Int64
        let status: EventSettlementStatus
    }

    /// One settlement pass per body evaluation. Previously four sibling
    /// computed properties each invoked the engine independently.
    private var derivedState: DerivedState {
        let settlementMembers = members.filter { !$0.isBudgetPool }
        let activeTransactions = ledgerTransactions.filter { !$0.isDeleted }
        let participantLinks = ledgerTransactions
            .flatMap { $0.participants ?? [] }
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.orderIndex == $1.orderIndex {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.orderIndex < $1.orderIndex
            }
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
        let budgetPoolMemberIDs = Set(members.filter(\.isBudgetPool).map(\.id))
        let settlement = EventSettlementEngine.compute(
            memberIds: settlementMembers.map(\.id),
            transactions: activeTransactions,
            participantLinks: map,
            budgetPoolMemberIds: budgetPoolMemberIDs
        )
        let balances = Dictionary(uniqueKeysWithValues: settlement.balances.map { ($0.memberId, $0) })
        var membersByID: [UUID: EventMember] = [:]
        for member in members {
            membersByID[member.id] = member
        }
        let localMember = settlementMembers.first(where: { $0.isLocalUser })
        let localNet = localMember.flatMap { balances[$0.id]?.netMinor } ?? 0
        let status: EventSettlementStatus
        if settlement.totalCostMinor <= 0 {
            status = .active
        } else if event.confirmedSettlementRevision == event.ledgerRevision {
            status = .settled
        } else {
            status = .readyToSettle
        }
        return DerivedState(
            settlementMembers: settlementMembers,
            activeTransactions: activeTransactions,
            linksByTransactionID: map,
            settlement: settlement,
            balancesByMemberID: balances,
            membersByID: membersByID,
            localMember: localMember,
            localNetMinor: localNet,
            status: status
        )
    }
    
    private var eventColor: Color {
        Color(hex: event.colorHex) ?? .blue
    }
    
    var body: some View {
        let state = derivedState
        
        List {
            // 1. Summary Section
            Section {
                EventSummaryCard(
                    event: event,
                    totalCost: state.settlement.totalCostMinor,
                    userNetBalance: state.localNetMinor,
                    remainingPool: state.settlement.walletRemainingMinor,
                    settlementStatus: state.status,
                    onAddExpense: { showingAddTransaction = true },
                    onSettle: { showingSettlement = true }
                )
            }
            
            Section {
                EventMemberSnapshotRow(
                    members: state.settlementMembers,
                    balances: state.balancesByMemberID,
                    event: event,
                    onAddMember: { showingAddMember = true },
                    onSelectMember: { member in memberToEdit = member }
                )
            } header: {
                HStack {
                    Text(L10n.EventDetail.members)
                        .appFont(.headline)
                    Spacer()
                    Button {
                        showingAllMembers = true
                    } label: {
                        Text(L10n.EventDetail.showAll)
                            .appFont(.subheadline, weight: .medium)
                            .foregroundStyle(.blue)
                            .textCase(nil)
                    }
                }
            }
            .listRowBackground(Color(.secondarySystemGroupedBackground))
            
            // 3. Transactions List Sections
            EventTransactionListView(
                transactions: state.activeTransactions,
                linksByTransactionId: state.linksByTransactionID,
                memberById: state.membersByID,
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
                    Image(systemName: "ellipsis")
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
                localMember: state.localMember,
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
                members: state.settlementMembers,
                balances: state.balancesByMemberID,
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
        .alert("common.success".localized, isPresented: Binding(
            get: { exportSuccessMessage != nil },
            set: { _ in exportSuccessMessage = nil }
        )) {
            Button(L10n.Common.ok, role: .cancel) { exportSuccessMessage = nil }
        } message: {
            Text(exportSuccessMessage ?? "")
        }
        .undoToast($recentlyDeletedTransaction, message: { _ in
            "event.transaction.deleted".localized
        }, onUndo: { transaction in
            restoreTransaction(transaction)
        })
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
            HapticManager.shared.warning()
            // Offer a transient Undo — the tombstone makes restore trivial.
            recentlyDeletedTransaction = transaction
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreTransaction(_ transaction: EventLedgerTransaction) {
        do {
            try service.restoreTransaction(transaction)
            HapticManager.shared.selection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func removeMember(_ member: EventMember) {
        do {
            try service.removeOrArchiveMember(member)
            HapticManager.shared.warning()
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
                            .appFont(.headline, weight: .bold)
                            .foregroundStyle(ThemeManager.shared.expenseColor)
                    }
                } footer: {
                    Text("event.detail.yourShareHint".localized)
                }

                if alreadyExported {
                    Section {
                        Label("event.detail.alreadyExported".localized, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(ThemeManager.shared.incomeColor)
                    }
                } else if spendingAmount > 0 {
                    Section {
                        Picker(L10n.EventSettlement.wallet, selection: Binding(
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
                        Text("event.detail.exportHint".localized)
                    }
                } else {
                    Section {
                        Text("event.detail.noExpensesToExport".localized)
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
                onSuccess("event.detail.exportedToFormat".localized(with: selectedWallet.name))
            } else {
                onError("event.detail.noSpendingToExport".localized)
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

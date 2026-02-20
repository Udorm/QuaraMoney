import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingAddMember = false
    @State private var memberToEdit: EventMember?
    @State private var showingAddTransaction = false
    @State private var transactionToEdit: EventLedgerTransaction?
    @State private var showingEditEvent = false
    @State private var showingSettlement = false
    @State private var errorMessage: String?
    
    @Query(sort: [SortDescriptor(\EventMember.sortOrder), SortDescriptor(\EventMember.name)]) private var allMembers: [EventMember]
    @Query(sort: \EventLedgerTransaction.date, order: .reverse) private var allLedgerTransactions: [EventLedgerTransaction]
    @Query(sort: \EventLedgerParticipant.orderIndex) private var allParticipantLinks: [EventLedgerParticipant]
    
    private var service: EventLedgerService {
        EventLedgerService(modelContext: modelContext)
    }
    
    private var members: [EventMember] {
        allMembers.filter { $0.event?.id == event.id }
    }
    
    private var budgetPoolMemberIds: Set<UUID> {
        Set(members.filter(\.isBudgetPool).map(\.id))
    }
    
    private var settlementMembers: [EventMember] {
        members.filter { !budgetPoolMemberIds.contains($0.id) }
    }
    
    private var ledgerTransactions: [EventLedgerTransaction] {
        allLedgerTransactions.filter { $0.event?.id == event.id }
    }
    
    private var participantLinks: [EventLedgerParticipant] {
        allParticipantLinks.filter { $0.transaction?.event?.id == event.id }
    }
    
    private var activeTransactions: [EventLedgerTransaction] {
        ledgerTransactions.filter { !$0.isDeleted }
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
        var map: [UUID: EventMemberLedgerBalance] = [:]
        for balance in settlementResult.balances {
            map[balance.memberId] = balance
        }
        return map
    }
    
    private var memberById: [UUID: EventMember] {
        var map: [UUID: EventMember] = [:]
        for member in members {
            map[member.id] = member
        }
        return map
    }
    
    private var totalCostMinor: Int64 {
        settlementResult.totalCostMinor
    }
    
    private var totalContributionMinor: Int64 {
        settlementResult.totalContributionMinor
    }
    
    private var walletRemainingMinor: Int64 {
        settlementResult.walletRemainingMinor
    }
    
    private var perPersonShareMinor: Int64 {
        guard !settlementMembers.isEmpty else { return 0 }
        return totalCostMinor / Int64(settlementMembers.count)
    }
    
    private var localMember: EventMember? {
        settlementMembers.first(where: { $0.isLocalUser })
    }
    
    private var localNetMinor: Int64 {
        guard let localMember else { return 0 }
        return balanceByMemberId[localMember.id]?.netMinor ?? 0
    }
    
    private var settlementStatus: EventSettlementStatus {
        guard totalCostMinor > 0 else {
            return .active
        }
        if event.confirmedSettlementRevision == event.ledgerRevision {
            return .settled
        }
        return .readyToSettle
    }
    
    private var eventColor: Color {
        Color(hex: event.colorHex) ?? .blue
    }
    
    var body: some View {
        let currentSettlement = settlementResult
        let balances = balanceByMemberId
        let status = settlementStatus
        let localNet = localNetMinor
        
        List {
            Section {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(eventColor.opacity(0.12))
                            .frame(width: 72, height: 72)
                        Image(systemName: event.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(eventColor)
                    }
                    
                    VStack(spacing: 6) {
                        Text(event.title)
                            .font(.app(.title2, weight: .bold))
                        
                        if let location = event.location {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.app(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(formatDateRange(start: event.startDate, end: event.endDate))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            
            Section("Summary") {
                HStack {
                    Text("Status")
                    Spacer()
                    EventSettlementStatusBadge(status: status)
                }
                
                HStack {
                    Text("Total Cost")
                    Spacer()
                    Text(formatMinor(currentSettlement.totalCostMinor))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Total Contribution")
                    Spacer()
                    Text(formatMinor(currentSettlement.totalContributionMinor))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Remaining Pool")
                    Spacer()
                    Text(formatMinor(currentSettlement.walletRemainingMinor))
                    .foregroundStyle(currentSettlement.walletRemainingMinor >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                }
                
                HStack {
                    Text("Per-person Share")
                    Spacer()
                    Text(formatMinor(perPersonShareMinor))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text(localMember?.name ?? "You")
                    Spacer()
                    Text(localNetLabel(for: localNet))
                        .foregroundStyle(netColor(for: localNet))
                }
                
                if let confirmedRevision = event.confirmedSettlementRevision,
                   confirmedRevision != event.ledgerRevision {
                    Text("Settlement is outdated because transactions changed after confirmation.")
                        .font(.app(.caption))
                        .foregroundStyle(.orange)
                }
            }
            
            Section {
                ForEach(settlementMembers) { member in
                    EventMemberRow(
                        member: member,
                        balance: balances[member.id],
                        currencyCode: event.currencyCode
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            memberToEdit = member
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                        
                        Button(role: .destructive) {
                            removeMember(member)
                        } label: {
                            Label(member.isArchived ? "Remove" : "Archive", systemImage: "person.crop.circle.badge.xmark")
                        }
                    }
                }
                
                Button {
                    showingAddMember = true
                } label: {
                    Label("Add Member", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Members")
            }
            
            Section {
                if activeTransactions.isEmpty {
                    Text("No event transactions yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeTransactions) { transaction in
                        TransactionRowView(
                            eventTransaction: transaction,
                            paidByName: paidByName(for: transaction),
                            participantCount: linksByTransactionId[transaction.id]?.count ?? 0,
                            currencyCode: event.currencyCode
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            transactionToEdit = transaction
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                transactionToEdit = transaction
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                            
                            Button(role: .destructive) {
                                deleteTransaction(transaction)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                transactionToEdit = transaction
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTransaction(transaction)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                
                Button {
                    showingAddTransaction = true
                } label: {
                    Label("Add Event Entry", systemImage: "plus")
                }
                .disabled(settlementMembers.filter { !$0.isArchived }.isEmpty)
            } header: {
                Text("Entries")
            }
            
            Section {
                Button {
                    showingSettlement = true
                } label: {
                    HStack {
                        Text("Settle Up")
                        Spacer()
                        if status == .settled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .disabled(status == .active)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditEvent = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditEvent) {
            AddEventView(eventToEdit: event)
        }
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
        .sheet(isPresented: $showingSettlement) {
            EventSettlementView(event: event)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            prepareEventContext()
        }
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
            try modelContext.save()
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
    
    private func formatDateRange(start: Date, end: Date?) -> String {
        if let end {
            if Calendar.current.isDate(start, inSameDayAs: end) {
                return start.formatted(date: .long, time: .shortened) + " - " + end.formatted(date: .omitted, time: .shortened)
            }
            return start.formatted(date: .abbreviated, time: .omitted) + " - " + end.formatted(date: .abbreviated, time: .omitted)
        }
        return start.formatted(date: .long, time: .shortened)
    }
    
    private func formatMinor(_ value: Int64) -> String {
        MoneyMinorUnitConverter
            .fromMinorUnits(value, currencyCode: event.currencyCode)
            .formatted(.currency(code: event.currencyCode))
    }
    
    private func localNetLabel(for value: Int64) -> String {
        if value > 0 {
            return "Receive \(formatMinor(value))"
        }
        if value < 0 {
            return "Pay \(formatMinor(abs(value)))"
        }
        return "Settled"
    }
    
    private func netColor(for value: Int64) -> Color {
        if value > 0 { return ThemeManager.shared.incomeColor }
        if value < 0 { return ThemeManager.shared.expenseColor }
        return .secondary
    }
    
    private func paidByName(for transaction: EventLedgerTransaction) -> String {
        if transaction.kind == .contribution {
            guard let payerId = transaction.paidByMemberId else { return "Unknown" }
            return memberById[payerId]?.name ?? "Unknown"
        }
        
        let payerIsBudgetPool = transaction.paidByMemberId.map { budgetPoolMemberIds.contains($0) } ?? false
        if transaction.paidSource == .eventWallet || transaction.paidByMemberId == nil || payerIsBudgetPool {
            return "Event Wallet"
        }
        
        guard let payerId = transaction.paidByMemberId else { return "Unknown" }
        return memberById[payerId]?.name ?? "Unknown"
    }
}

private struct EventSettlementStatusBadge: View {
    let status: EventSettlementStatus
    
    private var label: String {
        switch status {
        case .active: return "Active"
        case .readyToSettle: return "Ready to Settle"
        case .settled: return "Settled"
        }
    }
    
    private var color: Color {
        switch status {
        case .active: return .secondary
        case .readyToSettle: return .orange
        case .settled: return .green
        }
    }
    
    var body: some View {
        Text(label)
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct EventMemberRow: View {
    let member: EventMember
    let balance: EventMemberLedgerBalance?
    let currencyCode: String
    
    private var balanceText: String {
        MoneyMinorUnitConverter
            .fromMinorUnits(balance?.netMinor ?? 0, currencyCode: currencyCode)
            .formatted(.currency(code: currencyCode))
    }
    
    private var balanceColor: Color {
        let net = balance?.netMinor ?? 0
        if net > 0 { return ThemeManager.shared.incomeColor }
        if net < 0 { return ThemeManager.shared.expenseColor }
        return .secondary
    }
    
    private func money(_ value: Int64) -> String {
        MoneyMinorUnitConverter
            .fromMinorUnits(value, currencyCode: currencyCode)
            .formatted(.currency(code: currencyCode))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 34, height: 34)
                    Image(systemName: member.isLocalUser ? "person.fill.checkmark" : "person.fill")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.app(.body, weight: .medium))
                        
                        if member.isArchived {
                            Text("Archived")
                                .font(.app(.caption2))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.secondarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                    
                    if member.isLocalUser {
                        Text("You")
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text(balanceText)
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(balanceColor)
            }
            
            HStack {
                Text("Deposited")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(money(balance?.contributionMinor ?? 0))
            }
            .font(.app(.caption))
            
            HStack {
                Text("Paid personally")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(money(balance?.personalPaidMinor ?? 0))
            }
            .font(.app(.caption))
            
            HStack {
                Text("Share")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(money(balance?.shareMinor ?? 0))
            }
            .font(.app(.caption))
        }
    }
}

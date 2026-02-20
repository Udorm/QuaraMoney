import SwiftUI
import SwiftData

struct EventSettlementView: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: [SortDescriptor(\EventMember.sortOrder), SortDescriptor(\EventMember.name)]) private var allMembers: [EventMember]
    @Query(sort: \EventLedgerTransaction.date, order: .reverse) private var allLedgerTransactions: [EventLedgerTransaction]
    @Query(sort: \EventLedgerParticipant.orderIndex) private var allParticipantLinks: [EventLedgerParticipant]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived }, sort: \Wallet.name) private var wallets: [Wallet]
    
    @State private var exportToWallet = false
    @State private var selectedWallet: Wallet?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var useSingleCoordinator = false
    @State private var selectedCoordinatorMemberId: UUID?
    
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
    
    private var coordinatorCandidates: [EventMember] {
        settlementMembers.filter { !$0.isArchived || $0.isLocalUser }
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
            budgetPoolMemberIds: budgetPoolMemberIds,
            options: EventSettlementOptions(strategy: settlementStrategy)
        )
    }
    
    private var memberById: [UUID: EventMember] {
        var map: [UUID: EventMember] = [:]
        for member in settlementMembers {
            map[member.id] = member
        }
        return map
    }
    
    private var localMember: EventMember? {
        settlementMembers.first(where: { $0.isLocalUser })
    }
    
    private var localNetMinor: Int64 {
        guard let localMember else { return 0 }
        return settlementResult.balances.first(where: { $0.memberId == localMember.id })?.netMinor ?? 0
    }
    
    private var effectiveCoordinatorMemberId: UUID? {
        if let selectedCoordinatorMemberId,
           coordinatorCandidates.contains(where: { $0.id == selectedCoordinatorMemberId }) {
            return selectedCoordinatorMemberId
        }
        if let localMemberId = localMember?.id {
            return localMemberId
        }
        return coordinatorCandidates.first?.id
    }
    
    private var settlementStrategy: EventSettlementRoutingStrategy {
        if useSingleCoordinator, let coordinatorId = effectiveCoordinatorMemberId {
            return .singleCoordinator(coordinatorMemberId: coordinatorId)
        }
        return .minimalGreedy
    }
    
    private var walletIncomingInstructions: [EventWalletSettlementInstruction] {
        settlementResult.walletInstructions
            .filter { $0.direction == .receiveFromWallet }
            .sorted { $0.sequence < $1.sequence }
    }
    
    private var walletOutgoingInstructions: [EventWalletSettlementInstruction] {
        settlementResult.walletInstructions
            .filter { $0.direction == .payToWallet }
            .sorted { $0.sequence < $1.sequence }
    }
    
    var body: some View {
        let currentSettlement = settlementResult
        
        NavigationStack {
            List {
                Section("Summary") {
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
                    
                    if let localMember {
                        HStack {
                            Text(localMember.name)
                            Spacer()
                            Text(localNetLabel(for: localNetMinor))
                                .foregroundStyle(localNetColor(for: localNetMinor))
                        }
                    }
                }
                
                Section("Settlement Mode") {
                    Toggle("One-counterparty mode (organizer)", isOn: $useSingleCoordinator)
                    if useSingleCoordinator {
                        Picker("Organizer", selection: Binding(
                            get: { effectiveCoordinatorMemberId },
                            set: { selectedCoordinatorMemberId = $0 }
                        )) {
                            ForEach(coordinatorCandidates) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Text("Each member settles through one organizer.")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("From Event Wallet") {
                    if walletIncomingInstructions.isEmpty && walletOutgoingInstructions.isEmpty {
                        Text("No direct wallet settlement transfer.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(walletIncomingInstructions) { instruction in
                            HStack {
                                Text("Event Wallet pays")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(memberName(for: instruction.memberId))
                                        .font(.app(.subheadline, weight: .medium))
                                    Text(formatMinor(instruction.amountMinor))
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        ForEach(walletOutgoingInstructions) { instruction in
                            HStack {
                                Text("\(memberName(for: instruction.memberId)) pays")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Event Wallet")
                                        .font(.app(.subheadline, weight: .medium))
                                    Text(formatMinor(instruction.amountMinor))
                                        .font(.app(.caption))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section("Member Transfers") {
                    if currentSettlement.instructions.isEmpty {
                        Text("No member-to-member transfer needed.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(currentSettlement.instructions.sorted(by: { $0.sequence < $1.sequence })) { instruction in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(memberName(for: instruction.fromMemberId)) pays \(memberName(for: instruction.toMemberId))")
                                    .font(.app(.body, weight: .medium))
                                Text(formatMinor(instruction.amountMinor))
                                    .font(.app(.subheadline))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section("Balances") {
                    ForEach(currentSettlement.balances) { balance in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(memberName(for: balance.memberId))
                                Spacer()
                                Text(memberNetLabel(for: balance.netMinor))
                                    .foregroundStyle(localNetColor(for: balance.netMinor))
                            }
                            HStack(spacing: 12) {
                                Text("Deposited \(formatMinor(balance.contributionMinor))")
                                Text("Paid \(formatMinor(balance.personalPaidMinor))")
                                Text("Share \(formatMinor(balance.shareMinor))")
                            }
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Section("Export to Wallet") {
                    Toggle("Export my net balance as one wallet transaction", isOn: $exportToWallet)
                    if exportToWallet {
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
                        
                        Text("Only one transaction is exported. Individual event entries remain isolated.")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.app(.caption))
                    }
                }
            }
            .navigationTitle("Settle Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isProcessing ? "Saving..." : "Confirm") {
                        confirmSettlement()
                    }
                    .disabled(
                        isProcessing
                        || currentSettlement.totalCostMinor == 0
                        || (exportToWallet && selectedWallet == nil)
                        || (useSingleCoordinator && effectiveCoordinatorMemberId == nil)
                    )
                }
            }
            .onAppear {
                if selectedWallet == nil {
                    selectedWallet = wallets.first
                }
                if selectedCoordinatorMemberId == nil {
                    selectedCoordinatorMemberId = localMember?.id ?? coordinatorCandidates.first?.id
                }
            }
        }
    }
    
    private func confirmSettlement() {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let snapshot = try service.confirmSettlement(
                for: event,
                strategy: settlementStrategy,
                budgetPoolMemberId: budgetPoolMemberIds.first
            )
            if exportToWallet {
                guard let localMember else {
                    throw EventLedgerServiceError.missingLocalMember
                }
                guard let selectedWallet else {
                    return
                }
                _ = try service.exportNetBalanceToWallet(
                    for: event,
                    snapshot: snapshot,
                    member: localMember,
                    wallet: selectedWallet,
                    excludeFromReports: true
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func memberName(for memberId: UUID) -> String {
        memberById[memberId]?.name ?? "Unknown"
    }
    
    private func localNetLabel(for value: Int64) -> String {
        if value > 0 {
            return "You receive \(formatMinor(value))"
        }
        if value < 0 {
            return "You pay \(formatMinor(abs(value)))"
        }
        return "Settled"
    }
    
    private func memberNetLabel(for value: Int64) -> String {
        if value > 0 {
            return "Receive \(formatMinor(value))"
        }
        if value < 0 {
            return "Pay \(formatMinor(abs(value)))"
        }
        return "Settled"
    }
    
    private func localNetColor(for value: Int64) -> Color {
        if value > 0 { return ThemeManager.shared.incomeColor }
        if value < 0 { return ThemeManager.shared.expenseColor }
        return .secondary
    }
    
    private func formatMinor(_ value: Int64) -> String {
        MoneyMinorUnitConverter
            .fromMinorUnits(value, currencyCode: event.currencyCode)
            .formatted(.currency(code: event.currencyCode))
    }
}

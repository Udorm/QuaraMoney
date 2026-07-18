import SwiftUI
import SwiftData

struct EventSettlementView: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var members: [EventMember]
    @Query private var ledgerTransactions: [EventLedgerTransaction]
    @Query(filter: #Predicate<Wallet> { !$0.isArchived && $0.deletedAt == nil }, sort: \Wallet.name) private var wallets: [Wallet]

    init(event: Event) {
        self.event = event
        let eventID = event.id
        _members = Query(
            filter: EventScopedQuery.members(eventID: eventID),
            sort: [SortDescriptor(\EventMember.sortOrder), SortDescriptor(\EventMember.name)]
        )
        _ledgerTransactions = Query(
            filter: EventScopedQuery.transactions(eventID: eventID),
            sort: [SortDescriptor(\EventLedgerTransaction.date, order: .reverse), SortDescriptor(\EventLedgerTransaction.id)]
        )
    }
    
    @State private var exportToWallet = false
    @State private var selectedWallet: Wallet?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var useSingleCoordinator = false
    @State private var selectedCoordinatorMemberId: UUID?
    
    private var service: EventLedgerService {
        EventLedgerService(modelContext: modelContext)
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
    
    private var participantLinks: [EventLedgerParticipant] {
        ledgerTransactions
            .flatMap { $0.participants ?? [] }
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.orderIndex == $1.orderIndex {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.orderIndex < $1.orderIndex
            }
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
                // Lead with the answer the user opened this screen for.
                if let localMember {
                    Section("event.settlement.yourResult".localized) {
                        HStack {
                            Text(localMember.name)
                            Spacer()
                            Text(localNetLabel(for: localNetMinor))
                                .appFont(.body, weight: .semibold)
                                .foregroundStyle(localNetColor(for: localNetMinor))
                        }
                    }
                }

                Section("event.settlement.whoPaysWhom".localized) {
                    let hasAnyTransfer = !currentSettlement.instructions.isEmpty
                        || !walletIncomingInstructions.isEmpty
                        || !walletOutgoingInstructions.isEmpty
                    if !hasAnyTransfer {
                        Text("event.settlement.allSettledUp".localized)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(currentSettlement.instructions.sorted(by: { $0.sequence < $1.sequence })) { instruction in
                            transferRow(
                                from: memberName(for: instruction.fromMemberId),
                                to: memberName(for: instruction.toMemberId),
                                amountMinor: instruction.amountMinor
                            )
                        }
                        ForEach(walletIncomingInstructions) { instruction in
                            transferRow(
                                from: L10n.EventSettlement.wallet,
                                to: memberName(for: instruction.memberId),
                                amountMinor: instruction.amountMinor
                            )
                        }
                        ForEach(walletOutgoingInstructions) { instruction in
                            transferRow(
                                from: memberName(for: instruction.memberId),
                                to: L10n.EventSettlement.wallet,
                                amountMinor: instruction.amountMinor
                            )
                        }
                    }
                }

                Section {
                    Toggle("event.settlement.settleThroughOne".localized, isOn: $useSingleCoordinator)
                    if useSingleCoordinator {
                        Picker("event.settlement.whoSettles".localized, selection: Binding(
                            get: { effectiveCoordinatorMemberId },
                            set: { selectedCoordinatorMemberId = $0 }
                        )) {
                            ForEach(coordinatorCandidates) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } footer: {
                    Text("event.settlement.settleThroughOneHint".localized)
                }

                Section {
                    Toggle("event.settlement.addShareToWallet".localized, isOn: $exportToWallet)
                    if exportToWallet {
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
                    }
                } footer: {
                    if exportToWallet {
                        Text("event.settlement.addShareToWalletHint".localized)
                    }
                }

                Section("event.settlement.totals".localized) {
                    HStack {
                        Text(L10n.EventSettlement.totalCost)
                        Spacer()
                        Text(formatMinor(currentSettlement.totalCostMinor))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(L10n.EventSettlement.totalContribution)
                        Spacer()
                        Text(formatMinor(currentSettlement.totalContributionMinor))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("event.settlement.moneyLeftInWallet".localized)
                        Spacer()
                        Text(formatMinor(currentSettlement.walletRemainingMinor))
                            .foregroundStyle(currentSettlement.walletRemainingMinor >= 0 ? ThemeManager.shared.incomeColor : ThemeManager.shared.expenseColor)
                    }
                }

                Section {
                    DisclosureGroup("event.settlement.memberBreakdown".localized) {
                        ForEach(currentSettlement.balances) { balance in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(memberName(for: balance.memberId))
                                    Spacer()
                                    Text(memberNetLabel(for: balance.netMinor))
                                        .foregroundStyle(localNetColor(for: balance.netMinor))
                                }
                                HStack(spacing: 12) {
                                    Text("\("event.settlement.deposited".localized) \(formatMinor(balance.contributionMinor))")
                                    Text("\("event.settlement.paid".localized) \(formatMinor(balance.personalPaidMinor))")
                                    Text("\("event.settlement.share".localized) \(formatMinor(balance.shareMinor))")
                                }
                                .appFont(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .appFont(.caption)
                    }
                }
            }
            .navigationTitle(L10n.EventSettlement.settleEvent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isProcessing ? L10n.EventSettlement.saving : L10n.EventSettlement.confirm) {
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
            HapticManager.shared.success()
            dismiss()
        } catch {
            HapticManager.shared.error()
            errorMessage = error.localizedDescription
        }
    }
    
    /// A single "payer → payee : amount" row shared by member and wallet transfers.
    private func transferRow(from: String, to: String, amountMinor: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("event.settlement.paysFormat".localized(with: from, to))
                .appFont(.body, weight: .medium)
            Text(formatMinor(amountMinor))
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func memberName(for memberId: UUID) -> String {
        memberById[memberId]?.name ?? "event.settlement.unknownMember".localized
    }

    private func localNetLabel(for value: Int64) -> String {
        if value > 0 {
            return "event.settlement.youReceiveFormat".localized(with: formatMinor(value))
        }
        if value < 0 {
            return "event.settlement.youPayFormat".localized(with: formatMinor(abs(value)))
        }
        return "event.settlement.settled".localized
    }

    private func memberNetLabel(for value: Int64) -> String {
        if value > 0 {
            return "event.settlement.receiveFormat".localized(with: formatMinor(value))
        }
        if value < 0 {
            return "event.settlement.payFormat".localized(with: formatMinor(abs(value)))
        }
        return "event.settlement.settled".localized
    }
    
    private func localNetColor(for value: Int64) -> Color {
        if value > 0 { return ThemeManager.shared.incomeColor }
        if value < 0 { return ThemeManager.shared.expenseColor }
        return .secondary
    }
    
    private func formatMinor(_ value: Int64) -> String {
        MoneyMinorUnitConverter
            .fromMinorUnits(value, currencyCode: event.currencyCode)
            .formattedAmount(for: event.currencyCode)
    }
}

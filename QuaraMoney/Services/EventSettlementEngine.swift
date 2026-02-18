import Foundation

struct EventMemberLedgerBalance: Identifiable {
    var id: UUID { memberId }
    let memberId: UUID
    let contributionMinor: Int64
    let personalPaidMinor: Int64
    let shareMinor: Int64
    let netMinor: Int64
    let walletSettlementMinor: Int64
    let transferNetMinor: Int64
}

struct EventSettlementInstruction: Identifiable {
    let id: UUID
    let fromMemberId: UUID
    let toMemberId: UUID
    let amountMinor: Int64
    let sequence: Int
    
    init(fromMemberId: UUID, toMemberId: UUID, amountMinor: Int64, sequence: Int) {
        self.id = UUID()
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.amountMinor = amountMinor
        self.sequence = sequence
    }
}

enum EventWalletSettlementDirection: Equatable {
    case receiveFromWallet
    case payToWallet
}

struct EventWalletSettlementInstruction: Identifiable {
    let id: UUID
    let memberId: UUID
    let amountMinor: Int64
    let direction: EventWalletSettlementDirection
    let sequence: Int
    
    init(memberId: UUID, amountMinor: Int64, direction: EventWalletSettlementDirection, sequence: Int) {
        self.id = UUID()
        self.memberId = memberId
        self.amountMinor = amountMinor
        self.direction = direction
        self.sequence = sequence
    }
}

struct EventSettlementResult {
    let balances: [EventMemberLedgerBalance]
    let instructions: [EventSettlementInstruction]
    let walletInstructions: [EventWalletSettlementInstruction]
    let totalCostMinor: Int64
    let totalContributionMinor: Int64
    let walletExpensesMinor: Int64
    let walletRemainingMinor: Int64
}

enum EventSettlementRoutingStrategy: Equatable {
    case minimalGreedy
    case singleCoordinator(coordinatorMemberId: UUID)
}

struct EventSettlementOptions: Equatable {
    var strategy: EventSettlementRoutingStrategy = .minimalGreedy
    var memberIdSubstitutions: [UUID: UUID] = [:]
    
    static var `default`: EventSettlementOptions { EventSettlementOptions() }
}

enum EventSettlementEngine {
    static func compute(
        memberIds: [UUID],
        transactions: [EventLedgerTransaction],
        participantLinks: [UUID: [EventLedgerParticipant]],
        budgetPoolMemberIds: Set<UUID> = [],
        options: EventSettlementOptions = .default
    ) -> EventSettlementResult {
        let memberIdSet = Set(memberIds)
        var contributionMap: [UUID: Int64] = Dictionary(uniqueKeysWithValues: memberIds.map { ($0, 0) })
        var personalPaidMap: [UUID: Int64] = Dictionary(uniqueKeysWithValues: memberIds.map { ($0, 0) })
        var shareMap: [UUID: Int64] = Dictionary(uniqueKeysWithValues: memberIds.map { ($0, 0) })
        
        var totalCostMinor: Int64 = 0
        var totalContributionMinor: Int64 = 0
        var walletExpensesMinor: Int64 = 0
        
        for transaction in transactions where !transaction.isDeleted {
            guard transaction.amountMinor > 0 else { continue }
            
            let rawParticipants = sortedParticipants(for: transaction.id, in: participantLinks)
            let rawParticipantIds = uniqueOrdered(rawParticipants.map(\.memberId))
            let payerId = transaction.paidByMemberId
            let payerIsBudgetPool = payerId.map { budgetPoolMemberIds.contains($0) } ?? false
            
            let isLegacyTopUp = transaction.kind == .expense
                && transaction.paidSource == .member
                && !payerIsBudgetPool
                && rawParticipantIds.count == 1
                && budgetPoolMemberIds.contains(rawParticipantIds[0])
            
            let effectiveKind: EventLedgerTransactionKind = isLegacyTopUp ? .contribution : transaction.kind
            
            if effectiveKind == .contribution {
                guard let payerId else { continue }
                let mappedPayer = options.memberIdSubstitutions[payerId] ?? payerId
                guard memberIdSet.contains(mappedPayer) else { continue }
                contributionMap[mappedPayer, default: 0] += transaction.amountMinor
                totalContributionMinor += transaction.amountMinor
                continue
            }
            
            totalCostMinor += transaction.amountMinor
            
            let effectivePaidSource: EventExpensePaidSource
            if transaction.paidSource == .eventWallet || payerIsBudgetPool {
                effectivePaidSource = .eventWallet
            } else {
                effectivePaidSource = .member
            }
            
            let mappedParticipants = uniqueOrdered(
                rawParticipants
                    .map { options.memberIdSubstitutions[$0.memberId] ?? $0.memberId }
                    .filter { memberIdSet.contains($0) }
            )
            
            switch effectivePaidSource {
            case .member:
                guard let payerId else { break }
                let mappedPayer = options.memberIdSubstitutions[payerId] ?? payerId
                if memberIdSet.contains(mappedPayer) {
                    personalPaidMap[mappedPayer, default: 0] += transaction.amountMinor
                }
            case .eventWallet:
                walletExpensesMinor += transaction.amountMinor
            }
            
            guard !mappedParticipants.isEmpty else { continue }
            
            let count = Int64(mappedParticipants.count)
            let baseShare = transaction.amountMinor / count
            let remainder = transaction.amountMinor % count
            
            for (index, memberId) in mappedParticipants.enumerated() {
                let extra: Int64 = Int64(index) < remainder ? 1 : 0
                shareMap[memberId, default: 0] += (baseShare + extra)
            }
        }
        
        let walletRemainingMinor = totalContributionMinor - walletExpensesMinor
        
        var netMap: [UUID: Int64] = [:]
        var balancesByMember: [UUID: EventMemberLedgerBalance] = [:]
        for memberId in memberIds {
            let contribution = contributionMap[memberId, default: 0]
            let personalPaid = personalPaidMap[memberId, default: 0]
            let share = shareMap[memberId, default: 0]
            let net = contribution + personalPaid - share
            netMap[memberId] = net
            balancesByMember[memberId] = EventMemberLedgerBalance(
                memberId: memberId,
                contributionMinor: contribution,
                personalPaidMinor: personalPaid,
                shareMinor: share,
                netMinor: net,
                walletSettlementMinor: 0,
                transferNetMinor: net
            )
        }
        
        var walletInstructions: [EventWalletSettlementInstruction] = []
        var walletSequence = 0
        
        if walletRemainingMinor > 0 {
            var creditors = netMap
                .filter { $0.value > 0 }
                .map { (memberId: $0.key, remaining: $0.value) }
                .sorted {
                    if $0.remaining == $1.remaining {
                        return $0.memberId.uuidString < $1.memberId.uuidString
                    }
                    return $0.remaining > $1.remaining
                }
            
            var remainingPool = walletRemainingMinor
            var index = 0
            while remainingPool > 0 && index < creditors.count {
                let allocation = min(creditors[index].remaining, remainingPool)
                if allocation <= 0 {
                    index += 1
                    continue
                }
                
                creditors[index].remaining -= allocation
                remainingPool -= allocation
                netMap[creditors[index].memberId, default: 0] -= allocation
                
                walletInstructions.append(
                    EventWalletSettlementInstruction(
                        memberId: creditors[index].memberId,
                        amountMinor: allocation,
                        direction: .receiveFromWallet,
                        sequence: walletSequence
                    )
                )
                walletSequence += 1
                
                if creditors[index].remaining == 0 {
                    index += 1
                }
            }
        } else if walletRemainingMinor < 0 {
            var debtors = netMap
                .filter { $0.value < 0 }
                .map { (memberId: $0.key, remaining: abs($0.value)) }
                .sorted {
                    if $0.remaining == $1.remaining {
                        return $0.memberId.uuidString < $1.memberId.uuidString
                    }
                    return $0.remaining > $1.remaining
                }
            
            var remainingDeficit = abs(walletRemainingMinor)
            var index = 0
            while remainingDeficit > 0 && index < debtors.count {
                let allocation = min(debtors[index].remaining, remainingDeficit)
                if allocation <= 0 {
                    index += 1
                    continue
                }
                
                debtors[index].remaining -= allocation
                remainingDeficit -= allocation
                netMap[debtors[index].memberId, default: 0] += allocation
                
                walletInstructions.append(
                    EventWalletSettlementInstruction(
                        memberId: debtors[index].memberId,
                        amountMinor: allocation,
                        direction: .payToWallet,
                        sequence: walletSequence
                    )
                )
                walletSequence += 1
                
                if debtors[index].remaining == 0 {
                    index += 1
                }
            }
        }
        
        var balances: [EventMemberLedgerBalance] = memberIds.compactMap { memberId in
            guard let balance = balancesByMember[memberId] else { return nil }
            let transferNet = netMap[memberId, default: balance.netMinor]
            let walletSettlement = balance.netMinor - transferNet
            return EventMemberLedgerBalance(
                memberId: memberId,
                contributionMinor: balance.contributionMinor,
                personalPaidMinor: balance.personalPaidMinor,
                shareMinor: balance.shareMinor,
                netMinor: balance.netMinor,
                walletSettlementMinor: walletSettlement,
                transferNetMinor: transferNet
            )
        }
        
        balances.sort { lhs, rhs in
            if lhs.netMinor == rhs.netMinor {
                return lhs.memberId.uuidString < rhs.memberId.uuidString
            }
            return lhs.netMinor > rhs.netMinor
        }
        
        let transferNetTotal = balances.reduce(Int64.zero) { $0 + $1.transferNetMinor }
        guard transferNetTotal == 0 else {
            return EventSettlementResult(
                balances: balances,
                instructions: [],
                walletInstructions: walletInstructions,
                totalCostMinor: totalCostMinor,
                totalContributionMinor: totalContributionMinor,
                walletExpensesMinor: walletExpensesMinor,
                walletRemainingMinor: walletRemainingMinor
            )
        }
        
        let instructions: [EventSettlementInstruction]
        switch options.strategy {
        case .minimalGreedy:
            instructions = greedyInstructions(from: balances)
        case .singleCoordinator(let coordinatorMemberId):
            instructions = singleCoordinatorInstructions(from: balances, coordinatorMemberId: coordinatorMemberId)
        }
        
        return EventSettlementResult(
            balances: balances,
            instructions: instructions,
            walletInstructions: walletInstructions,
            totalCostMinor: totalCostMinor,
            totalContributionMinor: totalContributionMinor,
            walletExpensesMinor: walletExpensesMinor,
            walletRemainingMinor: walletRemainingMinor
        )
    }
    
    private static func greedyInstructions(from balances: [EventMemberLedgerBalance]) -> [EventSettlementInstruction] {
        var creditors: [(memberId: UUID, remaining: Int64)] = balances
            .filter { $0.transferNetMinor > 0 }
            .map { ($0.memberId, $0.transferNetMinor) }
            .sorted {
                if $0.remaining == $1.remaining {
                    return $0.memberId.uuidString < $1.memberId.uuidString
                }
                return $0.remaining > $1.remaining
            }
        
        var debtors: [(memberId: UUID, remaining: Int64)] = balances
            .filter { $0.transferNetMinor < 0 }
            .map { ($0.memberId, abs($0.transferNetMinor)) }
            .sorted {
                if $0.remaining == $1.remaining {
                    return $0.memberId.uuidString < $1.memberId.uuidString
                }
                return $0.remaining > $1.remaining
            }
        
        var instructions: [EventSettlementInstruction] = []
        var creditorIndex = 0
        var debtorIndex = 0
        var sequence = 0
        
        while creditorIndex < creditors.count && debtorIndex < debtors.count {
            let transferAmount = min(creditors[creditorIndex].remaining, debtors[debtorIndex].remaining)
            
            guard transferAmount > 0 else {
                if creditors[creditorIndex].remaining == 0 { creditorIndex += 1 }
                if debtors[debtorIndex].remaining == 0 { debtorIndex += 1 }
                continue
            }
            
            instructions.append(
                EventSettlementInstruction(
                    fromMemberId: debtors[debtorIndex].memberId,
                    toMemberId: creditors[creditorIndex].memberId,
                    amountMinor: transferAmount,
                    sequence: sequence
                )
            )
            sequence += 1
            
            creditors[creditorIndex].remaining -= transferAmount
            debtors[debtorIndex].remaining -= transferAmount
            
            if creditors[creditorIndex].remaining == 0 {
                creditorIndex += 1
            }
            if debtors[debtorIndex].remaining == 0 {
                debtorIndex += 1
            }
        }
        
        return instructions
    }
    
    private static func singleCoordinatorInstructions(
        from balances: [EventMemberLedgerBalance],
        coordinatorMemberId: UUID
    ) -> [EventSettlementInstruction] {
        guard balances.contains(where: { $0.memberId == coordinatorMemberId }) else {
            return greedyInstructions(from: balances)
        }
        
        let ordered = balances
            .filter { $0.memberId != coordinatorMemberId && $0.transferNetMinor != 0 }
            .sorted { $0.memberId.uuidString < $1.memberId.uuidString }
        
        var instructions: [EventSettlementInstruction] = []
        var sequence = 0
        
        for balance in ordered {
            if balance.transferNetMinor < 0 {
                instructions.append(
                    EventSettlementInstruction(
                        fromMemberId: balance.memberId,
                        toMemberId: coordinatorMemberId,
                        amountMinor: abs(balance.transferNetMinor),
                        sequence: sequence
                    )
                )
                sequence += 1
            } else if balance.transferNetMinor > 0 {
                instructions.append(
                    EventSettlementInstruction(
                        fromMemberId: coordinatorMemberId,
                        toMemberId: balance.memberId,
                        amountMinor: balance.transferNetMinor,
                        sequence: sequence
                    )
                )
                sequence += 1
            }
        }
        
        return instructions
    }
    
    private static func uniqueOrdered(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }
    
    private static func sortedParticipants(
        for transactionId: UUID,
        in participantLinks: [UUID: [EventLedgerParticipant]]
    ) -> [EventLedgerParticipant] {
        guard let participants = participantLinks[transactionId], !participants.isEmpty else {
            return []
        }
        
        return participants.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.memberId.uuidString < $1.memberId.uuidString
            }
            return $0.orderIndex < $1.orderIndex
        }
    }
}

import Foundation
import SwiftData

enum EventLedgerServiceError: LocalizedError {
    case emptyMemberName
    case emptyTransactionTitle
    case invalidAmount
    case missingParticipants
    case missingPayer
    case missingLocalMember
    case alreadyExported
    case alreadyExportedSpending
    case invalidSnapshotRevision
    case insufficientEventWalletBalance
    
    var errorDescription: String? {
        switch self {
        case .emptyMemberName:
            return "Member name is required."
        case .emptyTransactionTitle:
            return "Transaction title is required."
        case .invalidAmount:
            return "Amount must be greater than zero."
        case .missingParticipants:
            return "At least one participant is required."
        case .missingPayer:
            return "A member must be selected."
        case .missingLocalMember:
            return "No local member found for this event."
        case .alreadyExported:
            return "This settlement has already been exported for the selected member."
        case .alreadyExportedSpending:
            return "Spending has already been exported for this event."
        case .invalidSnapshotRevision:
            return "Settlement snapshot is outdated for this event revision."
        case .insufficientEventWalletBalance:
            return "Event wallet balance is insufficient for this expense. Add contributions or choose a personal payer."
        }
    }
}

struct EventSettlementPreview {
    let members: [EventMember]
    let transactions: [EventLedgerTransaction]
    let balances: [EventMemberLedgerBalance]
    let instructions: [EventSettlementInstruction]
    let walletInstructions: [EventWalletSettlementInstruction]
    let totalCostMinor: Int64
    let totalContributionMinor: Int64
    let walletExpensesMinor: Int64
    let walletRemainingMinor: Int64
    let currencyCode: String
    let ledgerRevision: Int64
}

@MainActor
final class EventLedgerService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Members
    
    @discardableResult
    func ensureLocalMemberExists(for event: Event, preferredName: String = "Me") throws -> EventMember {
        let members = try fetchMembers(eventId: event.id)
        if let localMember = members.first(where: { $0.isLocalUser }) {
            return localMember
        }
        
        let local = EventMember(
            name: preferredName,
            event: event,
            isLocalUser: true,
            sortOrder: nextSortOrder(from: members)
        )
        modelContext.insert(local)
        try saveWithoutRevisionBump()
        return local
    }
    
    @discardableResult
    func addMember(
        to event: Event,
        name: String,
        avatarData: Data? = nil,
        avatarIcon: String? = nil,
        colorHex: String? = nil,
        isLocalUser: Bool = false,
        isBudgetPool: Bool = false
    ) throws -> EventMember {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EventLedgerServiceError.emptyMemberName
        }
        
        let existingMembers = try fetchMembers(eventId: event.id)
        if isLocalUser {
            for member in existingMembers where member.isLocalUser {
                member.isLocalUser = false
                member.updatedAt = Date()
            }
        }
        if isBudgetPool {
            for member in existingMembers where member.isBudgetPool {
                member.isBudgetPool = false
                member.updatedAt = Date()
            }
        }
        
        let member = EventMember(
            name: trimmedName,
            event: event,
            avatarData: avatarData,
            avatarIcon: avatarIcon,
            colorHex: colorHex,
            isLocalUser: isBudgetPool ? false : isLocalUser,
            isBudgetPool: isBudgetPool,
            sortOrder: nextSortOrder(from: existingMembers)
        )
        modelContext.insert(member)
        bumpLedgerRevision(for: event)
        try save()
        return member
    }
    
    func updateMember(_ member: EventMember, name: String, avatarData: Data? = nil, avatarIcon: String? = nil, colorHex: String? = nil, isLocalUser: Bool, isBudgetPool: Bool) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EventLedgerServiceError.emptyMemberName
        }
        
        guard let event = member.event else { return }
        let eventMembers = try fetchMembers(eventId: event.id)
        if isLocalUser {
            for existing in eventMembers where existing.id != member.id && existing.isLocalUser {
                existing.isLocalUser = false
                existing.updatedAt = Date()
            }
        }
        if isBudgetPool {
            for existing in eventMembers where existing.id != member.id && existing.isBudgetPool {
                existing.isBudgetPool = false
                existing.updatedAt = Date()
            }
        }
        
        member.name = trimmedName
        member.avatarData = avatarData
        member.avatarIcon = avatarIcon
        if let colorHex {
            member.colorHex = colorHex
        }
        member.isLocalUser = isBudgetPool ? false : isLocalUser
        member.isBudgetPool = isBudgetPool
        member.updatedAt = Date()
        bumpLedgerRevision(for: event)
        try save()
    }
    
    @discardableResult
    func ensureBudgetPoolMemberExists(for event: Event, preferredName: String = "Trip Budget") throws -> EventMember {
        let members = try fetchMembers(eventId: event.id)
        if let existing = members.first(where: { $0.isBudgetPool }) {
            if existing.isArchived {
                existing.isArchived = false
                existing.updatedAt = Date()
                bumpLedgerRevision(for: event)
                try save()
            }
            return existing
        }
        
        let poolMember = EventMember(
            name: preferredName,
            event: event,
            isLocalUser: false,
            isBudgetPool: true,
            sortOrder: nextSortOrder(from: members)
        )
        modelContext.insert(poolMember)
        bumpLedgerRevision(for: event)
        try save()
        return poolMember
    }
    
    func removeOrArchiveMember(_ member: EventMember) throws {
        guard let event = member.event else { return }
        
        let transactions = try fetchLedgerTransactions(eventId: event.id)
        let participantLinks = try fetchParticipantLinks(eventId: event.id)
        let isReferencedAsPayer = transactions.contains { !$0.isDeleted && $0.paidByMemberId == member.id }
        let isReferencedAsParticipant = participantLinks.contains { $0.memberId == member.id }
        
        if isReferencedAsPayer || isReferencedAsParticipant {
            member.isArchived = true
            member.updatedAt = Date()
        } else {
            member.markSoftDeleted()
        }

        bumpLedgerRevision(for: event)
        try save()
    }
    
    // MARK: - Transactions
    
    @discardableResult
    func addTransaction(
        to event: Event,
        kind: EventLedgerTransactionKind,
        title: String,
        amount: Decimal,
        category: Category?,
        paidSource: EventExpensePaidSource = .member,
        paidByMemberId: UUID?,
        participantIds: [UUID] = [],
        date: Date,
        note: String?
    ) throws -> EventLedgerTransaction {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw EventLedgerServiceError.emptyTransactionTitle
        }
        
        let amountMinor = MoneyMinorUnitConverter.toMinorUnits(amount, currencyCode: event.currencyCode)
        guard amountMinor > 0 else {
            throw EventLedgerServiceError.invalidAmount
        }
        
        let uniqueParticipantIds = uniqueOrdered(participantIds)
        let normalizedPaidByMemberId: UUID?
        switch kind {
        case .contribution:
            guard let paidByMemberId else {
                throw EventLedgerServiceError.missingPayer
            }
            normalizedPaidByMemberId = paidByMemberId
        case .expense:
            guard !uniqueParticipantIds.isEmpty else {
                throw EventLedgerServiceError.missingParticipants
            }
            switch paidSource {
            case .member:
                guard let paidByMemberId else {
                    throw EventLedgerServiceError.missingPayer
                }
                normalizedPaidByMemberId = paidByMemberId
            case .eventWallet:
                let remaining = try eventWalletRemainingMinor(for: event)
                guard remaining >= amountMinor else {
                    throw EventLedgerServiceError.insufficientEventWalletBalance
                }
                normalizedPaidByMemberId = nil
            }
        }
        
        let transaction = EventLedgerTransaction(
            kind: kind,
            title: normalizedTitle,
            amountMinor: amountMinor,
            paidSource: kind == .contribution ? .member : paidSource,
            paidByMemberId: normalizedPaidByMemberId,
            splitType: .equal,
            date: date,
            note: normalizeNote(note),
            categoryId: category?.id,
            categoryName: category?.name,
            categoryIcon: category?.icon,
            categoryColorHex: category?.colorHex,
            event: event
        )
        modelContext.insert(transaction)
        
        if kind == .expense {
            for (index, memberId) in uniqueParticipantIds.enumerated() {
                let member = try fetchMember(by: memberId)
                let link = EventLedgerParticipant(memberId: memberId, orderIndex: index, transaction: transaction, member: member)
                modelContext.insert(link)
            }
        }
        
        bumpLedgerRevision(for: event)
        try save()
        return transaction
    }
    
    @discardableResult
    func addTransaction(
        to event: Event,
        title: String,
        amount: Decimal,
        category: Category?,
        paidByMemberId: UUID,
        participantIds: [UUID],
        date: Date,
        note: String?
    ) throws -> EventLedgerTransaction {
        try addTransaction(
            to: event,
            kind: .expense,
            title: title,
            amount: amount,
            category: category,
            paidSource: .member,
            paidByMemberId: paidByMemberId,
            participantIds: participantIds,
            date: date,
            note: note
        )
    }
    
    func updateTransaction(
        _ transaction: EventLedgerTransaction,
        kind: EventLedgerTransactionKind,
        title: String,
        amount: Decimal,
        category: Category?,
        paidSource: EventExpensePaidSource = .member,
        paidByMemberId: UUID?,
        participantIds: [UUID] = [],
        date: Date,
        note: String?
    ) throws {
        guard let event = transaction.event else { return }
        
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw EventLedgerServiceError.emptyTransactionTitle
        }
        
        let amountMinor = MoneyMinorUnitConverter.toMinorUnits(amount, currencyCode: event.currencyCode)
        guard amountMinor > 0 else {
            throw EventLedgerServiceError.invalidAmount
        }
        
        let uniqueParticipantIds = uniqueOrdered(participantIds)
        let normalizedPaidByMemberId: UUID?
        switch kind {
        case .contribution:
            guard let paidByMemberId else {
                throw EventLedgerServiceError.missingPayer
            }
            normalizedPaidByMemberId = paidByMemberId
        case .expense:
            guard !uniqueParticipantIds.isEmpty else {
                throw EventLedgerServiceError.missingParticipants
            }
            switch paidSource {
            case .member:
                guard let paidByMemberId else {
                    throw EventLedgerServiceError.missingPayer
                }
                normalizedPaidByMemberId = paidByMemberId
            case .eventWallet:
                let remaining = try eventWalletRemainingMinor(for: event, excludingTransactionId: transaction.id)
                guard remaining >= amountMinor else {
                    throw EventLedgerServiceError.insufficientEventWalletBalance
                }
                normalizedPaidByMemberId = nil
            }
        }
        
        transaction.kind = kind
        transaction.title = normalizedTitle
        transaction.amountMinor = amountMinor
        transaction.paidSource = kind == .contribution ? .member : paidSource
        transaction.paidByMemberId = normalizedPaidByMemberId
        transaction.date = date
        transaction.note = normalizeNote(note)
        if kind == .expense {
            transaction.categoryId = category?.id
            transaction.categoryName = category?.name
            transaction.categoryIcon = category?.icon
            transaction.categoryColorHex = category?.colorHex
        } else {
            transaction.categoryId = nil
            transaction.categoryName = nil
            transaction.categoryIcon = nil
            transaction.categoryColorHex = nil
        }
        transaction.updatedAt = Date()
        
        let allLinks = try fetchParticipantLinks(eventId: event.id)
        for link in allLinks where link.transaction?.id == transaction.id {
            link.markSoftDeleted()
        }
        
        if kind == .expense {
            for (index, memberId) in uniqueParticipantIds.enumerated() {
                let member = try fetchMember(by: memberId)
                let link = EventLedgerParticipant(memberId: memberId, orderIndex: index, transaction: transaction, member: member)
                modelContext.insert(link)
            }
        }
        
        bumpLedgerRevision(for: event)
        try save()
    }
    
    func updateTransaction(
        _ transaction: EventLedgerTransaction,
        title: String,
        amount: Decimal,
        category: Category?,
        paidByMemberId: UUID,
        participantIds: [UUID],
        date: Date,
        note: String?
    ) throws {
        try updateTransaction(
            transaction,
            kind: .expense,
            title: title,
            amount: amount,
            category: category,
            paidSource: .member,
            paidByMemberId: paidByMemberId,
            participantIds: participantIds,
            date: date,
            note: note
        )
    }
    
    func deleteTransaction(_ transaction: EventLedgerTransaction) throws {
        guard let event = transaction.event else { return }
        transaction.participants?.forEach { $0.markSoftDeleted() }
        transaction.markSoftDeleted()
        bumpLedgerRevision(for: event)
        try save()
    }

    /// Undoes `deleteTransaction` by clearing the tombstones it set.
    func restoreTransaction(_ transaction: EventLedgerTransaction) throws {
        transaction.markRestored()
        transaction.participants?.forEach { $0.markRestored() }
        if let event = transaction.event {
            bumpLedgerRevision(for: event)
        }
        try save()
    }
    
    // MARK: - Settlement
    
    func preview(
        for event: Event,
        strategy: EventSettlementRoutingStrategy = .minimalGreedy,
        budgetPoolMemberId: UUID? = nil
    ) throws -> EventSettlementPreview {
        let members = try fetchMembers(eventId: event.id)
        let transactions = try fetchLedgerTransactions(eventId: event.id).filter { !$0.isDeleted }
        let linksByTransaction = try participantLinksByTransaction(eventId: event.id)
        
        let budgetPoolIds = Set(members.filter(\.isBudgetPool).map(\.id))
        var memberIds = members.filter { !budgetPoolIds.contains($0.id) }.map(\.id)
        var options = EventSettlementOptions(strategy: strategy)
        if case .singleCoordinator(let coordinatorId) = strategy, let budgetPoolMemberId, budgetPoolMemberId != coordinatorId {
            options.memberIdSubstitutions[budgetPoolMemberId] = coordinatorId
            memberIds.removeAll(where: { $0 == budgetPoolMemberId })
        }
        
        let result = EventSettlementEngine.compute(
            memberIds: memberIds,
            transactions: transactions,
            participantLinks: linksByTransaction,
            budgetPoolMemberIds: budgetPoolIds,
            options: options
        )
        
        return EventSettlementPreview(
            members: members,
            transactions: transactions,
            balances: result.balances,
            instructions: result.instructions,
            walletInstructions: result.walletInstructions,
            totalCostMinor: result.totalCostMinor,
            totalContributionMinor: result.totalContributionMinor,
            walletExpensesMinor: result.walletExpensesMinor,
            walletRemainingMinor: result.walletRemainingMinor,
            currencyCode: event.currencyCode,
            ledgerRevision: event.ledgerRevision
        )
    }
    
    @discardableResult
    func confirmSettlement(
        for event: Event,
        strategy: EventSettlementRoutingStrategy = .minimalGreedy,
        budgetPoolMemberId: UUID? = nil
    ) throws -> EventSettlementSnapshot {
        let preview = try preview(
            for: event,
            strategy: strategy,
            budgetPoolMemberId: budgetPoolMemberId
        )
        
        let snapshot = EventSettlementSnapshot(ledgerRevision: event.ledgerRevision, event: event)
        modelContext.insert(snapshot)
        
        for instruction in preview.instructions.sorted(by: { $0.sequence < $1.sequence }) {
            let transfer = EventSettlementTransfer(
                fromMemberId: instruction.fromMemberId,
                toMemberId: instruction.toMemberId,
                amountMinor: instruction.amountMinor,
                sequence: instruction.sequence,
                snapshot: snapshot
            )
            modelContext.insert(transfer)
        }
        
        event.confirmedSettlementRevision = event.ledgerRevision
        try save()
        return snapshot
    }
    
    @discardableResult
    func exportNetBalanceToWallet(
        for event: Event,
        snapshot: EventSettlementSnapshot,
        member: EventMember,
        wallet: Wallet,
        exportDate: Date = Date(),
        excludeFromReports: Bool = true
    ) throws -> Transaction? {
        guard snapshot.ledgerRevision == event.ledgerRevision else {
            throw EventLedgerServiceError.invalidSnapshotRevision
        }
        
        let existingRecords = try fetchExportRecords(eventId: event.id)
        if existingRecords.contains(where: { $0.snapshot?.id == snapshot.id && $0.memberId == member.id }) {
            throw EventLedgerServiceError.alreadyExported
        }
        
        let preview = try preview(for: event)
        let netMinor = preview.balances.first(where: { $0.memberId == member.id })?.netMinor ?? 0
        
        guard netMinor != 0 else {
            return nil
        }
        
        let direction: EventWalletExportDirection = netMinor > 0 ? .income : .expense
        let amountMinor = abs(netMinor)
        let amount = MoneyMinorUnitConverter.fromMinorUnits(amountMinor, currencyCode: event.currencyCode)
        
        let transaction = Transaction(
            amount: amount,
            currencyCode: event.currencyCode,
            date: exportDate,
            type: direction == .income ? .income : .expense
        )
        transaction.note = "Event Settlement: \(event.title)"
        transaction.sourceWallet = wallet
        transaction.exchangeRate = exchangeRate(from: event.currencyCode, to: wallet.currencyCode)
        transaction.excludeFromReports = excludeFromReports
        transaction.category = try fetchOrCreateSettlementCategory(type: direction == .income ? .income : .expense)
        transaction.event = nil
        modelContext.insert(transaction)
        
        let record = EventWalletExportRecord(
            memberId: member.id,
            walletTransactionId: transaction.id,
            amountMinor: amountMinor,
            direction: direction,
            event: event,
            snapshot: snapshot
        )
        modelContext.insert(record)
        
        wallet.invalidateBalanceCache()
        try save()
        return transaction
    }
    
    // MARK: - Export Spending
    
    @discardableResult
    func exportSpendingToWallet(
        for event: Event,
        member: EventMember,
        wallet: Wallet,
        exportDate: Date = Date()
    ) throws -> Transaction? {
        // Check for existing spending export
        let existingRecords = try fetchExportRecords(eventId: event.id)
        if existingRecords.contains(where: { $0.exportType == .spending && $0.memberId == member.id }) {
            throw EventLedgerServiceError.alreadyExportedSpending
        }
        
        // Compute the member's total share of expenses
        let transactions = try fetchLedgerTransactions(eventId: event.id).filter { !$0.isDeleted && $0.kind == .expense }
        let linksByTransaction = try participantLinksByTransaction(eventId: event.id)
        
        var totalShareMinor: Int64 = 0
        
        for transaction in transactions {
            guard let participantIds = linksByTransaction[transaction.id] else { continue }
            guard participantIds.contains(member.id) else { continue }
            
            let count = Int64(participantIds.count)
            guard count > 0 else { continue }
            
            let baseShare = transaction.amountMinor / count
            let remainder = transaction.amountMinor % count
            
            // Match the engine's rounding: earlier participants get +1 for remainder
            let memberIndex = participantIds.firstIndex(of: member.id) ?? 0
            let extra: Int64 = Int64(memberIndex) < remainder ? 1 : 0
            totalShareMinor += baseShare + extra
        }
        
        guard totalShareMinor > 0 else {
            return nil
        }
        
        let amount = MoneyMinorUnitConverter.fromMinorUnits(totalShareMinor, currencyCode: event.currencyCode)
        
        let walletTransaction = Transaction(
            amount: amount,
            currencyCode: event.currencyCode,
            date: exportDate,
            type: .expense
        )
        walletTransaction.note = "Event: \(event.title)"
        walletTransaction.sourceWallet = wallet
        walletTransaction.exchangeRate = exchangeRate(from: event.currencyCode, to: wallet.currencyCode)
        walletTransaction.excludeFromReports = false
        walletTransaction.category = try fetchOrCreateEventExpenseCategory()
        walletTransaction.event = nil
        modelContext.insert(walletTransaction)
        
        let record = EventWalletExportRecord(
            memberId: member.id,
            walletTransactionId: walletTransaction.id,
            amountMinor: totalShareMinor,
            direction: .expense,
            exportType: .spending,
            event: event,
            snapshot: nil
        )
        modelContext.insert(record)
        
        wallet.invalidateBalanceCache()
        try save()
        return walletTransaction
    }
    
    func hasExportedSpending(for event: Event, memberId: UUID) throws -> Bool {
        let records = try fetchExportRecords(eventId: event.id)
        return records.contains(where: { $0.exportType == .spending && $0.memberId == memberId })
    }
    
    func spendingShareMinor(for event: Event, memberId: UUID) throws -> Int64 {
        let transactions = try fetchLedgerTransactions(eventId: event.id).filter { !$0.isDeleted && $0.kind == .expense }
        let linksByTransaction = try participantLinksByTransaction(eventId: event.id)
        
        var totalShareMinor: Int64 = 0
        
        for transaction in transactions {
            guard let participantIds = linksByTransaction[transaction.id] else { continue }
            guard participantIds.contains(memberId) else { continue }
            
            let count = Int64(participantIds.count)
            guard count > 0 else { continue }
            
            let baseShare = transaction.amountMinor / count
            let remainder = transaction.amountMinor % count
            let memberIndex = participantIds.firstIndex(of: memberId) ?? 0
            let extra: Int64 = Int64(memberIndex) < remainder ? 1 : 0
            totalShareMinor += baseShare + extra
        }
        
        return totalShareMinor
    }
    
    func latestSnapshot(for event: Event) throws -> EventSettlementSnapshot? {
        let snapshots = try fetchSettlementSnapshots(eventId: event.id)
        return snapshots.sorted { $0.createdAt > $1.createdAt }.first
    }
    
    // MARK: - Fetch helpers
    
    func activeMembers(for event: Event) throws -> [EventMember] {
        try fetchMembers(eventId: event.id).filter { !$0.isArchived }
    }
    
    func allMembers(for event: Event) throws -> [EventMember] {
        try fetchMembers(eventId: event.id)
    }
    
    func activeTransactions(for event: Event) throws -> [EventLedgerTransaction] {
        try fetchLedgerTransactions(eventId: event.id).filter { !$0.isDeleted }
    }
    
    func participantIds(for transaction: EventLedgerTransaction, eventId: UUID) throws -> [UUID] {
        let links = try fetchParticipantLinks(eventId: eventId)
            .filter { $0.transaction?.id == transaction.id }
            .sorted {
                if $0.orderIndex == $1.orderIndex {
                    return $0.memberId.uuidString < $1.memberId.uuidString
                }
                return $0.orderIndex < $1.orderIndex
            }
        return links.map(\.memberId)
    }
    
    // MARK: - Private
    
    private func fetchMembers(eventId: UUID) throws -> [EventMember] {
        let descriptor = FetchDescriptor<EventMember>(
            predicate: #Predicate { $0.event?.id == eventId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func fetchMember(by id: UUID) throws -> EventMember? {
        let predicate = #Predicate<EventMember> { member in
            member.id == id && member.deletedAt == nil
        }
        let descriptor = FetchDescriptor<EventMember>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }
    
    private func fetchLedgerTransactions(eventId: UUID) throws -> [EventLedgerTransaction] {
        let descriptor = FetchDescriptor<EventLedgerTransaction>(
            predicate: #Predicate { $0.event?.id == eventId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func fetchParticipantLinks(eventId: UUID) throws -> [EventLedgerParticipant] {
        // A chained transaction?.event predicate crashes Core Data's SQL
        // generator. Fetch the already event-scoped parent rows, then traverse
        // their inverse relationship instead of materializing the global link table.
        return try fetchLedgerTransactions(eventId: eventId)
            .flatMap { $0.participants ?? [] }
            .filter { $0.deletedAt == nil }
            .sorted {
                if $0.orderIndex == $1.orderIndex {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.orderIndex < $1.orderIndex
            }
    }
    
    private func participantLinksByTransaction(eventId: UUID) throws -> [UUID: [UUID]] {
        let links = try fetchParticipantLinks(eventId: eventId)
        var linksByTransaction: [UUID: [UUID]] = [:]
        for link in links {
            guard let transactionId = link.transaction?.id else { continue }
            linksByTransaction[transactionId, default: []].append(link.memberId)
        }
        // For isSplitAll transactions, override with all current non-archived members (excluding budget pool)
        let allMembers = try fetchMembers(eventId: eventId)
        let budgetPoolIds = Set(allMembers.filter(\.isBudgetPool).map(\.id))
        let activeMemberIds = allMembers.filter { !$0.isArchived && !budgetPoolIds.contains($0.id) }.map(\.id)
        let transactions = try fetchLedgerTransactions(eventId: eventId)
        for transaction in transactions where transaction.isSplitAll && !transaction.isDeleted {
            linksByTransaction[transaction.id] = activeMemberIds
        }
        return linksByTransaction
    }
    
    private func fetchSettlementSnapshots(eventId: UUID) throws -> [EventSettlementSnapshot] {
        let descriptor = FetchDescriptor<EventSettlementSnapshot>(
            predicate: #Predicate { $0.event?.id == eventId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func fetchSettlementTransfers(snapshotId: UUID) throws -> [EventSettlementTransfer] {
        let descriptor = FetchDescriptor<EventSettlementTransfer>(
            predicate: #Predicate { $0.snapshot?.id == snapshotId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sequence)]
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func fetchExportRecords(eventId: UUID) throws -> [EventWalletExportRecord] {
        let descriptor = FetchDescriptor<EventWalletExportRecord>(
            predicate: #Predicate { $0.event?.id == eventId && $0.deletedAt == nil }
        )
        return try modelContext.fetch(descriptor)
    }
    
    private func fetchOrCreateSettlementCategory(type: TransactionType) throws -> Category {
        let allCategories = try modelContext.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.deletedAt == nil }))
        if let existing = allCategories.first(where: { $0.isSystem && $0.type == type && $0.name == "Event Settlement" }) {
            return existing
        }
        
        if let existingLoose = allCategories.first(where: { $0.type == type && $0.name == "Event Settlement" }) {
            existingLoose.isSystem = true
            return existingLoose
        }
        
        let category = Category(
            name: "Event Settlement",
            icon: "person.3.sequence.fill",
            colorHex: "#5E5CE6",
            type: type,
            isSystem: true
        )
        modelContext.insert(category)
        return category
    }
    
    private func fetchOrCreateEventExpenseCategory() throws -> Category {
        let allCategories = try modelContext.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.deletedAt == nil }))
        if let existing = allCategories.first(where: { $0.isSystem && $0.type == .expense && $0.name == "Event Expense" }) {
            return existing
        }
        
        if let existingLoose = allCategories.first(where: { $0.type == .expense && $0.name == "Event Expense" }) {
            existingLoose.isSystem = true
            return existingLoose
        }
        
        let category = Category(
            name: "Event Expense",
            icon: "airplane",
            colorHex: "#FF9500",
            type: .expense,
            isSystem: true
        )
        modelContext.insert(category)
        return category
    }
    
    private func exchangeRate(from sourceCurrency: String, to targetCurrency: String) -> Decimal {
        guard sourceCurrency != targetCurrency else { return 1 }
        let manager = CurrencyManager.shared
        guard let sourceRate = manager.rates[sourceCurrency],
              let targetRate = manager.rates[targetCurrency],
              sourceRate > 0 else {
            return 1
        }
        return Decimal(targetRate / sourceRate)
    }
    
    private func eventWalletRemainingMinor(for event: Event, excludingTransactionId: UUID? = nil) throws -> Int64 {
        let members = try fetchMembers(eventId: event.id)
        let budgetPoolIds = Set(members.filter(\.isBudgetPool).map(\.id))
        let memberIds = members.filter { !budgetPoolIds.contains($0.id) }.map(\.id)
        
        let transactions = try fetchLedgerTransactions(eventId: event.id)
            .filter { !$0.isDeleted && $0.id != excludingTransactionId }
        let linksByTransaction = try participantLinksByTransaction(eventId: event.id)
        
        let result = EventSettlementEngine.compute(
            memberIds: memberIds,
            transactions: transactions,
            participantLinks: linksByTransaction,
            budgetPoolMemberIds: budgetPoolIds
        )
        return result.walletRemainingMinor
    }
    
    private func bumpLedgerRevision(for event: Event) {
        event.ledgerRevision += 1
    }
    
    private func nextSortOrder(from members: [EventMember]) -> Int {
        (members.map(\.sortOrder).max() ?? -1) + 1
    }
    
    private func normalizeNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func uniqueOrdered(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }
    
    private func saveWithoutRevisionBump() throws {
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
    
    private func save() throws {
        try modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

import SwiftUI
import SwiftData
import Foundation
import Combine

@MainActor
class AddEventLedgerTransactionViewModel: ObservableObject {
    let event: Event
    let transactionToEdit: EventLedgerTransaction?
    
    @Published var expression: String = ""
    @Published var evaluatedAmount: Decimal = 0
    @Published var transactionKind: EventLedgerTransactionKind = .expense
    @Published var selectedCategoryId: UUID?
    @Published var useEventWallet: Bool = false
    @Published var selectedPayerMemberId: UUID?
    @Published var isCustomSplit: Bool = false
    @Published var selectedParticipantIds: Set<UUID> = []
    @Published var date: Date = Date()
    @Published var note: String = ""
    @Published var selectedCurrencyCode: String = "USD"
    @Published var errorMessage: String?
    
    private var modelContext: ModelContext?
    
    init(event: Event, transactionToEdit: EventLedgerTransaction? = nil) {
        self.event = event
        self.transactionToEdit = transactionToEdit
        self.selectedCurrencyCode = event.currencyCode
        
        if let transaction = transactionToEdit {
            self.expression = "\(Decimal(transaction.amountMinor) / 100)"
            self.evaluatedAmount = Decimal(transaction.amountMinor) / 100
            self.transactionKind = transaction.kind
            self.selectedCategoryId = transaction.categoryId
            self.useEventWallet = transaction.paidSource == .eventWallet
            self.selectedPayerMemberId = transaction.paidByMemberId
            self.date = transaction.date
            self.note = transaction.note ?? ""
            
            if let participants = transaction.participants {
                self.selectedParticipantIds = Set(participants.map { $0.memberId })
            }
            self.isCustomSplit = !transaction.isSplitAll
        } else {
            // Defaults for new transaction
            self.transactionKind = .expense
            
            // Default paid source based on wallet balance
            let walletBalance = event.ledgerTransactions?
                .filter { !$0.isDeleted }
                .reduce(0 as Int64) { result, transaction in
                    if transaction.kind == .contribution {
                        return result + transaction.amountMinor
                    } else if transaction.kind == .expense && transaction.paidSource == .eventWallet {
                        return result - transaction.amountMinor
                    }
                    return result
                } ?? 0
            
            self.useEventWallet = walletBalance > 0
            
            // Default to all members participating
            if let members = event.members {
                self.selectedParticipantIds = Set(members.filter { !$0.isArchived }.map { $0.id })
            }
        }
    }
    
    @Published var expenseCategories: [Category] = []
    
    var resolvedAmount: Decimal {
        evaluatedAmount
    }
    
    var isValid: Bool {
        guard evaluatedAmount > 0 else { return false }
        if transactionKind == .expense {
            let hasParticipants = isCustomSplit
                ? !selectedParticipantIds.isEmpty
                : !(event.members?.filter { !$0.isArchived }.isEmpty ?? true)
            return selectedCategoryId != nil && (useEventWallet || selectedPayerMemberId != nil) && hasParticipants
        } else {
            return selectedPayerMemberId != nil
        }
    }
    
    var frequentCategories: [Category] {
        let sorted = expenseCategories.sorted { cat1, cat2 in
            let count1 = cat1.transactions?.count ?? 0
            let count2 = cat2.transactions?.count ?? 0
            return count1 > count2
        }
        
        let count = expenseCategories.count
        let limit = count > 4 ? 3 : 4
        
        var items = Array(sorted.prefix(limit))
        
        // Ensure selected category is visible
        if let selectedId = selectedCategoryId, 
           let selectedCategory = expenseCategories.first(where: { $0.id == selectedId }),
           !items.contains(where: { $0.id == selectedId }) {
            if !items.isEmpty {
                items[items.count - 1] = selectedCategory
            } else {
                items.append(selectedCategory)
            }
        }
        
        return items
    }
    
    var selectablePayers: [EventMember] {
        (event.members?.filter { !$0.isArchived } ?? [])
            .sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    var participantMembers: [EventMember] {
        (event.members?.filter { !$0.isArchived } ?? [])
            .sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }
    
    var selectableMembers: [EventMember] {
        participantMembers
    }
    
    func toggleParticipant(_ id: UUID) {
        if selectedParticipantIds.contains(id) {
            selectedParticipantIds.remove(id)
        } else {
            selectedParticipantIds.insert(id)
        }
    }
    
    func selectAllParticipants() {
        if let members = event.members {
            selectedParticipantIds = Set(members.filter { !$0.isArchived }.map { $0.id })
        }
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        fetchCategories()
    }
    
    func fetchCategories() {
        guard let modelContext = modelContext else { return }
        let descriptor = FetchDescriptor<Category>()
        let allCategories = (try? modelContext.fetch(descriptor)) ?? []
        self.expenseCategories = allCategories.filter { $0.type == .expense }
    }
    
    func save() -> Bool {
        guard let modelContext = modelContext else {
            errorMessage = "Database error"
            return false
        }
        
        guard evaluatedAmount > 0 else {
            errorMessage = "Please enter an amount"
            return false
        }
        
        let amountMinor = Int64((evaluatedAmount as NSDecimalNumber).doubleValue * 100)
        
        // Resolve participants: when isSplitAll, use current event members
        let isSplitAll = !isCustomSplit
        let resolvedParticipantIds: Set<UUID>
        if isSplitAll {
            resolvedParticipantIds = Set(
                (event.members?.filter { !$0.isArchived } ?? []).map { $0.id }
            )
        } else {
            resolvedParticipantIds = selectedParticipantIds
        }
        
        let selectedCategory = expenseCategories.first(where: { $0.id == selectedCategoryId })
        
        if let transaction = transactionToEdit {
            transaction.kind = transactionKind
            transaction.amountMinor = amountMinor
            transaction.paidSource = useEventWallet ? .eventWallet : .member
            transaction.paidByMemberId = selectedPayerMemberId
            transaction.date = date
            transaction.note = note
            transaction.categoryId = selectedCategoryId
            transaction.categoryName = selectedCategory?.name
            transaction.categoryIcon = selectedCategory?.icon
            transaction.categoryColorHex = selectedCategory?.colorHex
            transaction.isSplitAll = isSplitAll
            
            // Update participants
            transaction.participants?.forEach { modelContext.delete($0) }
            transaction.participants = resolvedParticipantIds.enumerated().map { index, id in
                EventLedgerParticipant(memberId: id, orderIndex: index, transaction: transaction, member: event.members?.first(where: { $0.id == id }))
            }
        } else {
            let newTransaction = EventLedgerTransaction(
                kind: transactionKind,
                title: note.isEmpty ? (transactionKind == .expense ? L10n.EventTransaction.tabExpense : L10n.EventTransaction.tabContribution) : note,
                amountMinor: amountMinor,
                paidSource: useEventWallet ? .eventWallet : .member,
                paidByMemberId: selectedPayerMemberId,
                splitType: .equal,
                date: date,
                note: note,
                categoryId: selectedCategoryId,
                categoryName: selectedCategory?.name,
                categoryIcon: selectedCategory?.icon,
                categoryColorHex: selectedCategory?.colorHex,
                event: event
            )
            newTransaction.isSplitAll = isSplitAll
            modelContext.insert(newTransaction)
            
            newTransaction.participants = resolvedParticipantIds.enumerated().map { index, id in
                EventLedgerParticipant(memberId: id, orderIndex: index, transaction: newTransaction, member: event.members?.first(where: { $0.id == id }))
            }
        }
        
        do {
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
            return false
        }
    }
}

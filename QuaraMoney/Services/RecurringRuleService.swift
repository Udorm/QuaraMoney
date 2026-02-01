import Foundation
import SwiftData

@MainActor
class RecurringRuleService {
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func checkAndGenerateTransactions() {
        // Fetch all active rules
        let descriptor = FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.isActive })
        
        do {
            let rules = try modelContext.fetch(descriptor)
            let today = Date()
            
            for rule in rules {
                processRule(rule, until: today)
            }
            
            try modelContext.save()
        } catch {
            print("Failed to fetch or process rules: \(error)")
        }
    }
    
    private func processRule(_ rule: RecurringRule, until targetDate: Date) {
        // While the next due date is in the past or today
        while rule.nextDueDate <= targetDate {
            // Create Transaction
            let transaction = Transaction(
                amount: rule.amount,
                currencyCode: rule.currencyCode,
                date: rule.nextDueDate,
                type: .expense // Defaulting to expense as most recurrings are bills. Logic could be improved to support Income recurrings.
            )
            transaction.note = "Generated from \(rule.name)"
            transaction.sourceWallet = rule.wallet
            transaction.category = rule.category
            transaction.recurringRule = rule
            
            modelContext.insert(transaction)
            
            // Advance nextDueDate
            if let nextDate = calculateNextDate(from: rule.nextDueDate, frequency: rule.frequency) {
                rule.nextDueDate = nextDate
            } else {
                // Safety break to prevent infinite loops if calc fails
                break
            }
        }
    }
    
    private func calculateNextDate(from date: Date, frequency: Frequency) -> Date? {
        let calendar = Calendar.current
        switch frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

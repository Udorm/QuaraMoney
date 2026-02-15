import Foundation
import SwiftData

struct RecurringRuleService {
    nonisolated static func checkAndGenerateTransactions(modelContext: ModelContext) {
        // Fetch all active rules
        let descriptor = FetchDescriptor<RecurringRule>(predicate: #Predicate { $0.isActive })
        
        do {
            let rules = try modelContext.fetch(descriptor)
            let today = Date()
            
            for rule in rules {
                processRule(rule, until: today, modelContext: modelContext)
            }
            
            try modelContext.save()
            // Notify UI of changes
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        } catch {
            #if DEBUG
            print("Failed to fetch or process rules: \(error)")
            #endif
        }
    }
    
    nonisolated private static func processRule(_ rule: RecurringRule, until targetDate: Date, modelContext: ModelContext) {
        // While the next due date is in the past or today
        while rule.nextDueDate <= targetDate {
            // Create Transaction
            let transaction = Transaction(
                amount: rule.amount,
                currencyCode: rule.currencyCode,
                date: rule.nextDueDate,
                type: .expense // Defaulting to expense as most recurrings are bills.
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
    
    nonisolated private static func calculateNextDate(from date: Date, frequency: Frequency) -> Date? {
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

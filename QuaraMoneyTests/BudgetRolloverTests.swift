
import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class BudgetRolloverTests: XCTestCase {
    
    // Test that rollover calculation logic is correct
    // Since we cannot easily mock SwiftData ModelContext in a simple unit test without more setup,
    // we will test the logic by creating a temporary Budget object if possible, or extracting calculation logic.
    // However, BudgetRolloverService relies heavily on ModelContext.
    // For this phase, we will create a test that verifies the `Budget` model's internal calculation methods 
    // which are easier to test isolated.
    
    func testBudgetRolloverCalculation() {
        // Create a dummy budget (in memory)
        let budget = Budget(amountLimit: 1000, currencyCode: "USD", category: nil, month: 1, year: 2026)
        budget.isRecurring = true
        budget.rolloverExcess = true
        budget.periodType = .monthly
        
        // Simulate spending 800 (Leaving 200)
        let unusedAmount: Decimal = 200
        
        // Perform rollover logic manually (simulating service)
        budget.rolloverToNextPeriod(unusedAmount: unusedAmount)
        
        // Verify rollover amount is stored
        XCTAssertEqual(budget.rolloverAmount, 200, "Rollover amount should be 200")
        
        // Verify start date moved (Monthly)
        // Original: Jan 1, 2026. Next: Feb 1, 2026.
        let calendar = Calendar.current
        let month = calendar.component(.month, from: budget.startDate)
        XCTAssertEqual(month, 2, "Budget should have moved to February")
    }
    
    func testBudgetRolloverDisabled() {
        let budget = Budget(amountLimit: 1000, currencyCode: "USD", category: nil, month: 1, year: 2026)
        budget.isRecurring = true
        budget.rolloverExcess = false // Disabled
        
        let unusedAmount: Decimal = 200
        budget.rolloverToNextPeriod(unusedAmount: unusedAmount)
        
        XCTAssertEqual(budget.rolloverAmount, 0, "Rollover amount should be 0 when disabled")
    }
}

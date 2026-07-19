import Combine
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import QuaraMoney

/// Hosts the redesigned Plan detail screens in a real UIWindow and pumps the
/// run loop. A layout/observation loop or main-thread hang on push shows up as
/// a timeout here instead of only reproducing by hand in the simulator.
@MainActor
final class PlanDetailHostingProbeTests: XCTestCase {
    private func pumpRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func host<Content: View>(_ content: Content) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: AnyView(NavigationStack { content }))
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    /// Drives the actual push: list-like root, then a programmatic
    /// navigationDestination push of the detail — the moment the user's freeze
    /// occurs ("freezes at the list, detail never appears").
    private final class PushFlag: ObservableObject {
        @Published var pushed = false
    }

    private struct PushHarness<Detail: View>: View {
        @ObservedObject var flag: PushFlag
        let detail: () -> Detail
        var body: some View {
            NavigationStack {
                List {
                    Text("row")
                }
                .navigationDestination(isPresented: $flag.pushed) {
                    detail()
                }
            }
        }
    }

    private func runPushProbe<Detail: View>(_ detail: @escaping () -> Detail) {
        let flag = PushFlag()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(
            rootView: AnyView(PushHarness(flag: flag, detail: detail))
        )
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        pumpRunLoop(seconds: 0.6)
        flag.pushed = true
        pumpRunLoop(seconds: 3)
        window.isHidden = true
    }

    func testBudgetDetailPushDoesNotHang() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let budget = Budget(
            amountLimit: 500,
            currencyCode: "USD",
            periodType: .monthly,
            startDate: Date(),
            isRecurring: true
        )
        context.insert(budget)
        let expense = Transaction(amount: 12, currencyCode: "USD", date: Date(), type: .expense)
        context.insert(expense)
        try context.save()

        runPushProbe { BudgetDetailView(budget: budget).modelContainer(container) }
    }

    func testSavingsDetailPushDoesNotHang() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let goal = SavingsGoal(name: "Trip", targetAmount: 2000, currencyCode: "USD")
        context.insert(goal)
        try context.save()

        runPushProbe { SavingsGoalDetailView(goal: goal).modelContainer(container) }
    }

    func testBudgetDetailRendersWithoutHanging() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let category = Category(name: "Food", icon: "fork.knife", colorHex: "#FF0000", type: .expense)
        let budget = Budget(
            amountLimit: 500,
            currencyCode: "USD",
            periodType: .monthly,
            startDate: Date(),
            isRecurring: true,
            categories: [category]
        )
        context.insert(category)
        context.insert(budget)
        for day in 0..<5 {
            let transaction = Transaction(
                amount: 12,
                currencyCode: "USD",
                date: Calendar.current.date(byAdding: .day, value: -day, to: Date())!,
                type: .expense
            )
            transaction.category = category
            context.insert(transaction)
        }
        try context.save()

        let window = host(BudgetDetailView(budget: budget).modelContainer(container))
        pumpRunLoop(seconds: 2.5)
        window.isHidden = true
    }

    func testYearlyKHRBudgetDetailRendersWithoutHanging() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let budget = Budget(
            amountLimit: 20_000_000,
            currencyCode: "KHR",
            periodType: .yearly,
            startDate: Date(),
            isRecurring: true
        )
        context.insert(budget)
        for day in 0..<200 {
            let transaction = Transaction(
                amount: 45_000,
                currencyCode: "KHR",
                date: Calendar.current.date(byAdding: .day, value: -day, to: Date())!,
                type: .expense
            )
            context.insert(transaction)
        }
        try context.save()

        let window = host(BudgetDetailView(budget: budget).modelContainer(container))
        pumpRunLoop(seconds: 4)
        window.isHidden = true
    }

    func testSavingsDetailRendersWithoutHanging() throws {
        let container = TestModelContainer.create()
        let context = container.mainContext
        let wallet = Wallet(name: "Cash", currencyCode: "USD", icon: "wallet.pass", colorHex: "#00FF00")
        let goal = SavingsGoal(name: "Trip", targetAmount: 2000, currencyCode: "USD")
        goal.targetDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())
        context.insert(wallet)
        context.insert(goal)
        for month in 0..<4 {
            let transfer = Transaction(
                amount: 100,
                currencyCode: "USD",
                date: Calendar.current.date(byAdding: .month, value: -month, to: Date())!,
                type: .transfer
            )
            transfer.sourceWallet = wallet
            transfer.savingsGoal = goal
            context.insert(transfer)
        }
        try context.save()

        let window = host(SavingsGoalDetailView(goal: goal).modelContainer(container))
        pumpRunLoop(seconds: 2.5)
        window.isHidden = true
    }
}

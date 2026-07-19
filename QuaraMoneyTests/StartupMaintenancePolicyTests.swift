import XCTest
import SwiftData
@testable import QuaraMoney

@MainActor
final class StartupMaintenancePolicyTests: XCTestCase {
    private func input(
        syncEnabled: Bool = true,
        auth: StartupMaintenancePolicy.AuthState = .signedIn,
        conflict: StartupMaintenancePolicy.ConflictState = .resolved,
        initialSync: StartupMaintenancePolicy.InitialSyncState = .idleCompleted,
        wait: StartupMaintenancePolicy.SettlementWait = .settled
    ) -> StartupMaintenancePolicy.Input {
        StartupMaintenancePolicy.Input(
            isSyncEnabled: syncEnabled,
            authState: auth,
            conflictState: conflict,
            initialSyncState: initialSync,
            settlementWait: wait
        )
    }

    func testSafeTerminalStatesRun() {
        XCTAssertEqual(
            StartupMaintenancePolicy.decision(for: input(syncEnabled: false, auth: .sessionRestoring)),
            .run
        )
        XCTAssertEqual(
            StartupMaintenancePolicy.decision(for: input(auth: .signedOut, conflict: .notApplicable, initialSync: .notApplicable)),
            .run
        )
        XCTAssertEqual(StartupMaintenancePolicy.decision(for: input()), .run)
    }

    func testUnknownConflictFailureSyncAndTimeoutStatesSkip() {
        let unsafeInputs: [StartupMaintenancePolicy.Input] = [
            input(auth: .sessionRestoring, conflict: .checking, initialSync: .idleIncomplete),
            input(conflict: .checking, initialSync: .idleIncomplete),
            input(conflict: .pending),
            input(conflict: .checkFailed),
            input(initialSync: .inFlight),
            input(initialSync: .idleIncomplete),
            input(wait: .timedOut)
        ]

        for unsafeInput in unsafeInputs {
            XCTAssertEqual(
                StartupMaintenancePolicy.decision(for: unsafeInput),
                .skipAndRearm
            )
        }
    }

    func testSkippedDecisionRearmsWhenStateSettles() {
        let pending = input(conflict: .pending)
        let settled = input()
        XCTAssertTrue(
            StartupMaintenancePolicy.shouldRearm(
                after: StartupMaintenancePolicy.decision(for: pending),
                with: settled
            )
        )
    }

    func testStaleSettlementCompletionFromPreviousGenerationIsIgnored() {
        let userID = UUID()
        XCTAssertFalse(
            StartupMaintenanceGuard.acceptsSettlementCompletion(
                authUserID: userID,
                generation: 4,
                currentAuthUserID: userID,
                currentGeneration: 5
            )
        )
    }

    func testExactOwnerIdentityDetectsOwnedToOwnedChange() {
        let authUserID = UUID()
        let expected = StartupMaintenanceIdentity(
            authUserID: authUserID,
            localOwnerID: UUID(),
            authGeneration: 4
        )
        let ownerChanged = StartupMaintenanceIdentity(
            authUserID: authUserID,
            localOwnerID: UUID(),
            authGeneration: 4
        )

        XCTAssertFalse(StartupMaintenanceGuard.isCurrent(expected, current: ownerChanged))
    }

    func testOwnedToOwnedAccountSwitchBeforeSaveRollsBackPlanNormalization() throws {
        let container = TestModelContainer.create()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let startDate = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        let budget = Budget(
            name: "Travel",
            amountLimit: 100,
            currencyCode: "USD",
            periodType: .biweekly,
            startDate: startDate,
            isRecurring: true,
            rolloverExcess: false
        )
        context.insert(budget)
        try context.save()

        let preparation = try PlanDataMaintenance.run(in: context, ownerID: UUID(), rates: ["USD": 1], commitsMarker: false)
        XCTAssertTrue(preparation.changed)
        XCTAssertTrue(context.hasChanges)

        let accountA = UUID()
        let accountB = UUID()
        let expected = StartupMaintenanceIdentity(
            authUserID: accountA,
            localOwnerID: accountA,
            authGeneration: 8
        )
        let switched = StartupMaintenanceIdentity(
            authUserID: accountB,
            localOwnerID: accountB,
            authGeneration: 9
        )

        let result = try StartupMaintenanceGuard.commit(
            context: context,
            expected: expected,
            currentIdentity: { switched }
        )
        XCTAssertNil(result)
        XCTAssertFalse(context.hasChanges)
        // rollback() discards pending changes but does not refresh live model
        // instances — assert the guard's real contract (nothing persisted) by
        // reading the store through a fresh context.
        let verifyContext = ModelContext(container)
        let persisted = try XCTUnwrap(try verifyContext.fetch(FetchDescriptor<Budget>()).first)
        XCTAssertEqual(persisted.startDate, startDate)
        XCTAssertEqual(persisted.periodType, .biweekly)
    }

    func testAccountSwitchBeforePostSaveEffectsSuppressesEffects() {
        let accountA = UUID()
        let accountB = UUID()
        let expected = StartupMaintenanceIdentity(
            authUserID: accountA,
            localOwnerID: accountA,
            authGeneration: 2
        )
        let switched = StartupMaintenanceIdentity(
            authUserID: accountB,
            localOwnerID: accountB,
            authGeneration: 3
        )
        var scheduledReminderOrNotification = false

        if StartupMaintenanceGuard.isCurrent(expected, current: switched) {
            scheduledReminderOrNotification = true
        }

        XCTAssertFalse(scheduledReminderOrNotification)
    }
}

import Foundation
import SwiftData

/// Pure startup-maintenance decision logic. Network/auth implementations feed
/// their current state into this value layer; tests exercise every gate without
/// constructing a Supabase client.
enum StartupMaintenancePolicy {
    enum AuthState: Equatable, Sendable {
        case sessionRestoring
        case signedOut
        case signedIn
    }

    enum ConflictState: Equatable, Sendable {
        case notApplicable
        case checking
        case pending
        case checkFailed
        case resolved
    }

    enum InitialSyncState: Equatable, Sendable {
        case notApplicable
        case inFlight
        case idleIncomplete
        case idleCompleted
    }

    enum SettlementWait: Equatable, Sendable {
        case settled
        case timedOut
    }

    struct Input: Equatable, Sendable {
        let isSyncEnabled: Bool
        let authState: AuthState
        let conflictState: ConflictState
        let initialSyncState: InitialSyncState
        let settlementWait: SettlementWait
    }

    enum Decision: Equatable, Sendable {
        case run
        case skipAndRearm
    }

    static func decision(for input: Input) -> Decision {
        guard input.settlementWait == .settled else { return .skipAndRearm }
        guard input.isSyncEnabled else { return .run }

        switch input.authState {
        case .signedOut:
            return .run
        case .sessionRestoring:
            return .skipAndRearm
        case .signedIn:
            guard input.conflictState == .resolved,
                  input.initialSyncState == .idleCompleted else {
                return .skipAndRearm
            }
            return .run
        }
    }

    static func shouldRearm(after previous: Decision, with current: Input) -> Bool {
        previous == .skipAndRearm && decision(for: current) == .run
    }
}

/// Exact identity captured by a maintenance attempt. Owner UUID is distinct
/// from auth UUID because ownership can change during reconcile or conflict
/// resolution; both plus the auth generation must still match at commit/effect
/// boundaries.
nonisolated struct StartupMaintenanceIdentity: Equatable, Sendable {
    let authUserID: UUID?
    let localOwnerID: UUID?
    let authGeneration: Int
}

nonisolated enum StartupMaintenanceGuard {
    struct CommitResult: Equatable, Sendable {
        let hadChanges: Bool
    }

    static func isCurrent(
        _ expected: StartupMaintenanceIdentity,
        current: StartupMaintenanceIdentity
    ) -> Bool {
        expected == current
    }

    static func acceptsSettlementCompletion(
        authUserID: UUID?,
        generation: Int,
        currentAuthUserID: UUID?,
        currentGeneration: Int
    ) -> Bool {
        authUserID == currentAuthUserID && generation == currentGeneration
    }

    /// Disables autosave, then saves only when exact account ownership and
    /// generation still match so rollback cannot be pre-empted by an autosave.
    /// The remaining comparison-to-save instant is intentionally narrow; a
    /// full ownership/commit coordinator is outside this pass's architecture.
    static func commit(
        context: ModelContext,
        expected: StartupMaintenanceIdentity,
        currentIdentity: () -> StartupMaintenanceIdentity
    ) throws -> CommitResult? {
        context.autosaveEnabled = false
        guard isCurrent(expected, current: currentIdentity()) else {
            context.rollback()
            return nil
        }
        let hadChanges = context.hasChanges
        try context.save()
        return CommitResult(hadChanges: hadChanges)
    }
}

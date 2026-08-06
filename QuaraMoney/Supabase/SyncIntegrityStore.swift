import Foundation

struct SyncIntegrityIssue: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let ownerID: UUID
    let table: String
    let rowID: UUID
    let message: String
    let repairAction: String
    let recordedAt: Date
    var acknowledgedAt: Date?
}

enum SyncIntegrityStore {
    private static let key = "syncIntegrityIssues.v1"

    static func record(
        ownerID: UUID,
        table: String,
        rowID: UUID,
        message: String,
        repairAction: String,
        defaults: UserDefaults = .standard
    ) {
        var issues = load(defaults: defaults)
        if let index = issues.firstIndex(where: {
            $0.ownerID == ownerID && $0.table == table && $0.rowID == rowID && $0.acknowledgedAt == nil
        }) {
            issues[index] = SyncIntegrityIssue(
                id: issues[index].id,
                ownerID: ownerID,
                table: table,
                rowID: rowID,
                message: message,
                repairAction: repairAction,
                recordedAt: Date(),
                acknowledgedAt: nil
            )
        } else {
            issues.append(SyncIntegrityIssue(
                id: UUID(), ownerID: ownerID, table: table, rowID: rowID,
                message: message, repairAction: repairAction,
                recordedAt: Date(), acknowledgedAt: nil
            ))
        }
        save(issues, defaults: defaults)
    }

    static func unacknowledged(ownerID: UUID? = nil, defaults: UserDefaults = .standard) -> [SyncIntegrityIssue] {
        load(defaults: defaults).filter {
            $0.acknowledgedAt == nil && (ownerID == nil || $0.ownerID == ownerID)
        }
    }

    static func latestMessage(defaults: UserDefaults = .standard) -> String? {
        unacknowledged(defaults: defaults).max(by: { $0.recordedAt < $1.recordedAt }).map {
            "\($0.message) \($0.repairAction)"
        }
    }

    private static func load(defaults: UserDefaults) -> [SyncIntegrityIssue] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SyncIntegrityIssue].self, from: data)) ?? []
    }

    private static func save(_ issues: [SyncIntegrityIssue], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(issues) else { return }
        defaults.set(data, forKey: key)
    }
}

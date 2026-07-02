import SwiftData
import Foundation

@Model
final class EventMember {
    var id: UUID

    // MARK: - Sync metadata (Supabase migration)
    var syncUserID: UUID?
    var deletedAt: Date?
    var needsSync: Bool = true

    var name: String
    @Attribute(.externalStorage) var avatarData: Data?

    /// SHA-256 of the last avatar bytes uploaded to (or downloaded from) cloud
    /// storage; sync re-uploads only when the image changed. Local-only metadata.
    var avatarUploadedHash: String?
    var avatarIcon: String?
    var colorHex: String = "#007AFF" // Default blue
    var isArchived: Bool = false
    var isLocalUser: Bool = false
    var isBudgetPool: Bool = false
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    
    // Static icons for random assignment (Face icons only)
    static let defaultIcons = [
        "face.smiling.fill", "face.smiling.inverse", "person.fill", 
        "person.circle.fill", "person.crop.circle.fill", 
        "person.and.arrow.left.and.arrow.right", "person.2.fill", 
        "person.3.fill", "face.dashed.fill", "face.smiling"
    ]

    // Static colors for random assignment
    static let defaultColors = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", 
        "#5856D6", "#AF52DE", "#FF2D55", "#5AC8FA", "#4CD964"
    ]
    
    // Relationships
    var event: Event?
    @Relationship(deleteRule: .nullify, inverse: \EventLedgerParticipant.member) var participantLinks: [EventLedgerParticipant]?
    
    init(
        name: String,
        event: Event?,
        avatarData: Data? = nil,
        avatarIcon: String? = nil,
        colorHex: String? = nil,
        isLocalUser: Bool = false,
        isBudgetPool: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.event = event
        self.avatarData = avatarData
        self.avatarIcon = avatarIcon ?? (avatarData == nil ? Self.defaultIcons.randomElement() : nil)
        self.colorHex = colorHex ?? Self.defaultColors.randomElement() ?? "#007AFF"
        self.isLocalUser = isLocalUser
        self.isBudgetPool = isBudgetPool
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

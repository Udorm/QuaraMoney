import Foundation
import Supabase

/// Syncs the account profile (display name + avatar) with the `profiles` table
/// and the receipts storage bucket, so the user's identity follows the account
/// across devices instead of living (and leaking) in device-local AppStorage.
///
/// Local persistence intentionally reuses the same UserDefaults keys the UI has
/// always bound to (`userDisplayName`, `userAvatarPath`), so signed-out /
/// local-only users keep the existing behavior and `@AppStorage` views update
/// automatically when a pull applies remote values.
///
/// Single-row last-write-wins, mirroring the table sync: a pending local edit
/// newer than the remote row wins and pushes; otherwise the remote row is
/// applied. `SyncEngine.syncNow` runs this as its "profile" step;
/// `wipeForSignOut` / `reconcileAccountIfNeeded` call `clearLocal()` so one
/// account's name and photo can never carry over to the next.
@MainActor
final class ProfileSyncService {
    static let shared = ProfileSyncService()

    private let nameKey = "userDisplayName"
    private let avatarPathKey = "userAvatarPath"
    private let needsSyncKey = "profileNeedsSync.v1"
    private let updatedAtKey = "profileUpdatedAt.v1"
    private let avatarDirtyKey = "profileAvatarNeedsUpload.v1"

    private var defaults: UserDefaults { .standard }

    private init() {}

    // MARK: - Local state

    /// The device cache of the account avatar (same file the profile UI has
    /// always used).
    nonisolated static var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_avatar.jpg")
    }

    private var displayName: String {
        defaults.string(forKey: nameKey) ?? ""
    }

    private var localAvatarExists: Bool {
        FileManager.default.fileExists(atPath: Self.avatarFileURL.path)
    }

    /// Call after any local profile edit (rename, new photo, photo removal) so
    /// the next sync pushes it. `avatarChanged` additionally marks the avatar
    /// bytes for upload.
    func noteLocalEdit(avatarChanged: Bool = false) {
        defaults.set(true, forKey: needsSyncKey)
        if avatarChanged { defaults.set(true, forKey: avatarDirtyKey) }
        defaults.set(Date().timeIntervalSince1970, forKey: updatedAtKey)
    }

    /// Clears the device copy of the profile. Called on sign-out and on
    /// account switch — profile identity belongs to the account, not the device.
    func clearLocal() {
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: avatarPathKey)
        defaults.removeObject(forKey: needsSyncKey)
        defaults.removeObject(forKey: updatedAtKey)
        defaults.removeObject(forKey: avatarDirtyKey)
        try? FileManager.default.removeItem(at: Self.avatarFileURL)
    }

    // MARK: - Sync

    func sync(_ client: SupabaseClient, uid: UUID) async throws {
        let needsPush = defaults.bool(forKey: needsSyncKey)
        let localUpdatedAt = Date(timeIntervalSince1970: defaults.double(forKey: updatedAtKey))

        let rows: [SyncProfileRow] = try await client.from("profiles")
            .select()
            .eq("id", value: uid.uuidString)
            .limit(1)
            .execute().value
        let remote = rows.first

        if let remote {
            let localWins = needsPush && localUpdatedAt > remote.updated_at
            if !localWins {
                try await apply(remote, client)
                defaults.set(false, forKey: needsSyncKey)
                defaults.set(false, forKey: avatarDirtyKey)
                defaults.set(remote.updated_at.timeIntervalSince1970, forKey: updatedAtKey)
                return
            }
        }

        // Push when a local edit is pending, or when the account has no profile
        // row yet but this device holds one from the pre-sync era.
        let hasLocalContent = !displayName.isEmpty || localAvatarExists
        guard needsPush || (remote == nil && hasLocalContent) else { return }

        var avatarStoragePath: String?
        if localAvatarExists {
            avatarStoragePath = Self.storagePath(uid)
            let avatarDirty = defaults.bool(forKey: avatarDirtyKey)
            if avatarDirty || remote?.avatar_path == nil {
                let data = try Data(contentsOf: Self.avatarFileURL)
                _ = try await client.storage.from("receipts").upload(
                    avatarStoragePath!, data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true))
            }
        }

        let row = SyncProfileRow(id: uid,
                                 display_name: displayName.isEmpty ? nil : displayName,
                                 avatar_path: avatarStoragePath,
                                 updated_at: Date())
        let returned: [SyncProfileRow] = try await client.from("profiles")
            .upsert(row)
            .execute().value

        defaults.set(false, forKey: needsSyncKey)
        defaults.set(false, forKey: avatarDirtyKey)
        // Store the trigger-assigned server timestamp so LWW stays in one clock
        // domain (mirrors the engine's server-timestamp write-back).
        if let serverDate = returned.first?.updated_at {
            defaults.set(serverDate.timeIntervalSince1970, forKey: updatedAtKey)
        }
    }

    private func apply(_ remote: SyncProfileRow, _ client: SupabaseClient) async throws {
        if let name = remote.display_name, !name.isEmpty {
            defaults.set(name, forKey: nameKey)
        } else {
            defaults.removeObject(forKey: nameKey)
        }

        let storedUpdatedAt = defaults.double(forKey: updatedAtKey)
        let remoteChanged = remote.updated_at.timeIntervalSince1970 != storedUpdatedAt

        if let path = remote.avatar_path {
            // Download only when the row actually changed or the file is missing
            // — not on every idle sync cycle.
            if remoteChanged || !localAvatarExists {
                let data = try await client.storage.from("receipts").download(path: path)
                try data.write(to: Self.avatarFileURL, options: .atomic)
                defaults.set(Self.avatarFileURL.path(), forKey: avatarPathKey)
                NotificationCenter.default.post(name: .profileDidChange, object: self)
            }
        } else if localAvatarExists {
            try? FileManager.default.removeItem(at: Self.avatarFileURL)
            defaults.removeObject(forKey: avatarPathKey)
            NotificationCenter.default.post(name: .profileDidChange, object: self)
        }
    }

    /// Storage object path — first folder must be the lowercased user id to
    /// satisfy the receipts-bucket RLS policy.
    private nonisolated static func storagePath(_ uid: UUID) -> String {
        "\(uid.uuidString.lowercased())/profile/avatar.jpg"
    }
}

extension Notification.Name {
    /// Posted when a sync changes the local avatar file, so views holding a
    /// decoded UIImage can reload it (`@AppStorage` covers the name, not the file).
    static let profileDidChange = Notification.Name("profileDidChange")
}

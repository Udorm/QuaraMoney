import SwiftUI
import PhotosUI
import SwiftData

/// The unified Account screen (More → profile banner): profile identity,
/// cloud-sync account, sync status, and usage stats in one place. Replaces the
/// old separate ProfileView (More) and CloudSyncSettingsView (Settings).
struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: SupabaseAuthManager
    @StateObject private var sync = SyncEngine.shared
    private let viewModel = AccountViewModel()

    @AppStorage("userDisplayName") private var displayName: String = ""
    @AppStorage("userAvatarPath") private var avatarPath: String = ""
    @AppStorage("appInstallDate") private var installDateTimestamp: Double = 0
    @AppStorage("isSupabaseSyncEnabled") private var syncEnabled = false

    @Query(filter: #Predicate<Wallet> { $0.deletedAt == nil }) private var wallets: [Wallet]

    // Only the count is needed — fetch it instead of materializing every
    // Transaction object (and its relationships) just to call `.count`.
    @State private var transactionCount = 0

    @State private var avatarImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoOptions = false
    @State private var showLibraryPicker = false
    @State private var showCamera = false
    @State private var cameraCapture: UIImage?
    @State private var pendingCrop: CropCandidate?
    @State private var editingName = false
    @State private var tempName: String = ""
    @State private var authSheetMode: AuthSheetView.Mode?
    @State private var showDeleteAccountConfirm = false
    @FocusState private var isNameFocused: Bool

    /// Identifiable wrapper so a freshly captured/picked photo can drive
    /// `fullScreenCover(item:)` into the crop step.
    private struct CropCandidate: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    private var memberSinceFormatted: String {
        let date = installDateTimestamp > 0
            ? Date(timeIntervalSince1970: installDateTimestamp)
            : Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeaderCard
                accountSyncCard
                quickStatsCard
                memberSinceCard

                if viewModel.isConfigured && syncEnabled && auth.isSignedIn {
                    accountManagementSection
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.Profile.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadAvatar()
            tempName = displayName
            // Record install date if not set (kept out of body: writing
            // AppStorage during view evaluation re-triggers layout).
            if installDateTimestamp == 0 {
                installDateTimestamp = Date().timeIntervalSince1970
            }
            refreshTransactionCount()
            if syncEnabled { auth.start() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            refreshTransactionCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
            // A sync replaced/removed the avatar file — reload the decoded image.
            loadAvatar()
        }
        .onChange(of: syncEnabled) { _, enabled in
            viewModel.syncEnabledChanged(enabled, context: modelContext)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                await loadPhoto(from: newItem)
            }
        }
        .photosPicker(
            isPresented: $showLibraryPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            // Enter the crop step only after the camera has fully dismissed —
            // presenting a second cover while the first is still up gets dropped.
            if let capture = cameraCapture {
                cameraCapture = nil
                pendingCrop = CropCandidate(image: capture)
            }
        }) {
            CameraPickerView { image in
                cameraCapture = image
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $pendingCrop) { candidate in
            AvatarCropView(image: candidate.image) { cropped in
                if let cropped {
                    avatarImage = cropped
                    saveAvatar(cropped)
                }
            }
        }
        .sheet(item: $authSheetMode) { mode in
            AuthSheetView(
                showsForeignDataWarning: viewModel.hasUnsyncedDataFromPreviousAccount,
                mode: mode
            )
        }
        .confirmationDialog(
            L10n.Profile.photoOptions,
            isPresented: $showPhotoOptions,
            titleVisibility: .visible
        ) {
            Button(L10n.Profile.takePhoto) {
                showCamera = true
            }

            Button(L10n.Profile.chooseFromLibrary) {
                showLibraryPicker = true
            }

            if let avatarImage {
                Button("profile.reframePhoto".localized) {
                    pendingCrop = CropCandidate(image: avatarImage)
                }

                Button(L10n.Profile.removePhoto, role: .destructive) {
                    removeAvatar()
                }
            }

            Button(L10n.Common.cancel, role: .cancel) { }
        }
    }

    // MARK: - Profile Header Card

    private var profileHeaderCard: some View {
        VStack(spacing: 20) {
            Button {
                showPhotoOptions = true
            } label: {
                ProfileAvatarView(
                    image: avatarImage,
                    displayName: displayName.isEmpty ? L10n.Profile.namePlaceholder : displayName,
                    size: 110,
                    showEditBadge: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Profile.changePhoto)

            // Display Name
            VStack(spacing: 8) {
                if editingName {
                    HStack(spacing: 12) {
                        TextField(L10n.Profile.namePlaceholder, text: $tempName)
                            .font(.app(.title2, weight: .bold))
                            .multilineTextAlignment(.center)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                saveName()
                            }

                        Button {
                            saveName()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 32)
                } else {
                    Button {
                        tempName = displayName
                        editingName = true
                        isNameFocused = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(displayName.isEmpty ? L10n.Profile.namePlaceholder : displayName)
                                .font(.app(.title2, weight: .bold))
                                .foregroundStyle(displayName.isEmpty ? .secondary : .primary)

                            Image(systemName: "pencil.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
    }

    // MARK: - Account & Cloud Sync Card

    @ViewBuilder
    private var accountSyncCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "icloud.fill")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.cyan.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text("Cloud Sync")
                    .font(.app(.headline, weight: .semibold))

                Spacer()

                if viewModel.isConfigured {
                    Toggle("Cloud Sync", isOn: $syncEnabled)
                        .labelsHidden()
                }
            }

            if !viewModel.isConfigured {
                Label("Cloud sync isn't configured in this build.",
                      systemImage: "exclamationmark.triangle")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            } else if syncEnabled {
                Divider()
                if auth.isSignedIn {
                    signedInSection
                } else {
                    signedOutSection
                }
            } else {
                Text("When off, QuaraMoney runs fully offline on this device.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
    }

    // MARK: - Signed-out state (sign in / create account CTA)

    @ViewBuilder
    private var signedOutSection: some View {
        VStack(spacing: 16) {
            if viewModel.hasUnsyncedDataFromPreviousAccount {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("This device still has unsynced changes from a previous account. Sign back in to that account to save them — signing in to a different account will remove them from this device.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(spacing: 4) {
                Text("Back Up Your Data")
                    .font(.app(.subheadline, weight: .semibold))

                Text("Sign in so your wallets, transactions, and budgets are safely backed up and follow you to any device.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Button {
                    authSheetMode = .signIn
                } label: {
                    Text("Sign In")
                        .font(.app(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    authSheetMode = .signUp
                } label: {
                    Text("Create Account")
                        .font(.app(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Signed-in state (account + sync status)

    @ViewBuilder
    private var signedInSection: some View {
        // Who's signed in
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(auth.currentEmail ?? "")
                    .font(.app(.subheadline, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 5) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text("Signed in")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }

        Divider()

        // Sync status + manual sync
        HStack(spacing: 12) {
            syncStatusIcon
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(syncStatusTitle)
                    .font(.app(.subheadline, weight: .medium))

                Text(syncStatusDetail)
                    .font(.app(.caption))
                    .foregroundStyle(sync.lastError == nil ? Color.secondary : Color.red)
                    .lineLimit(3)
            }

            Spacer()

            Button {
                Task { await sync.syncNow(context: modelContext) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.app(.subheadline, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(sync.isSyncing)
            .accessibilityLabel("Sync Now")
        }

        if sync.isInitialSyncInProgress {
            Text("Uploading your existing data for the first time. Keep the app open.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        if sync.isSyncing {
            ProgressView()
        } else if sync.lastError != nil {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.title3)
                .foregroundStyle(.orange)
        } else if sync.lastSyncDate != nil {
            Image(systemName: "checkmark.icloud.fill")
                .font(.title3)
                .foregroundStyle(.green)
        } else {
            Image(systemName: "icloud")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var syncStatusTitle: String {
        if sync.isInitialSyncInProgress { return "Setting up cloud sync…" }
        if sync.isSyncing { return "Syncing…" }
        if sync.lastError != nil { return "Sync issue" }
        if sync.lastSyncDate != nil { return "Up to date" }
        return "Waiting for first sync"
    }

    private var syncStatusDetail: String {
        if let error = sync.lastError { return error }
        if sync.isSyncing { return "Updating your data" }
        if let last = sync.lastSyncDate {
            return "Last synced \(last.formatted(.relative(presentation: .named)))"
        }
        return "Tap sync to upload your data"
    }

    // MARK: - Sign out / Delete account

    private var accountManagementSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await auth.signOut() }
            } label: {
                HStack(spacing: 8) {
                    if auth.isWorking {
                        ProgressView()
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.app(.subheadline, weight: .semibold))
                    }
                    Text("Sign Out")
                        .font(.app(.body, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            }
            .disabled(auth.isWorking || sync.isSyncing)

            // App Store Guideline 5.1.1(v): account deletion must be available in-app.
            Button {
                showDeleteAccountConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.app(.subheadline, weight: .semibold))
                    Text("Delete Account…")
                        .font(.app(.body, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.red.opacity(0.1))
                    .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
            }
            .disabled(auth.isWorking || sync.isSyncing)

            Text("Permanently deletes your account and all synced data from the cloud and this device.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account & All Data", role: .destructive) {
                Task { await auth.deleteAccount() }
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, all synced data, and receipt images from the cloud, and removes the data from this device. This cannot be undone.")
        }
    }

    private func refreshTransactionCount() {
        transactionCount = (try? modelContext.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil }))) ?? transactionCount
    }

    // MARK: - Quick Stats Card

    private var quickStatsCard: some View {
        HStack(spacing: 0) {
            statItem(
                value: "\(wallets.filter { !$0.isArchived }.count)",
                label: L10n.Profile.totalWallets,
                icon: "wallet.pass.fill",
                color: .blue
            )

            Divider()
                .frame(height: 40)

            statItem(
                value: "\(transactionCount)",
                label: L10n.Profile.totalTransactions,
                icon: "arrow.left.arrow.right",
                color: .orange
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
    }

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.app(.title, weight: .bold))
                .foregroundStyle(.primary)

            Text(label)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Member Since Card

    private var memberSinceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.Profile.memberSince)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)

                Text(memberSinceFormatted)
                    .font(.app(.body, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
        }
    }

    // MARK: - Avatar Helpers

    private func loadAvatar() {
        let url = ProfileSyncService.avatarFileURL
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            self.avatarImage = image
        } else {
            self.avatarImage = nil
        }
    }

    private func saveAvatar(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let url = ProfileSyncService.avatarFileURL
        try? data.write(to: url, options: .atomic)
        avatarPath = url.path()
        viewModel.pushProfileEdit(avatarChanged: true, context: modelContext)
    }

    private func removeAvatar() {
        try? FileManager.default.removeItem(at: ProfileSyncService.avatarFileURL)
        avatarPath = ""
        avatarImage = nil
        viewModel.pushProfileEdit(avatarChanged: true, context: modelContext)
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }

        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await MainActor.run {
                pendingCrop = CropCandidate(image: image)
                // Reset so picking the same photo again re-triggers onChange.
                selectedPhotoItem = nil
            }
        }
    }

    private func saveName() {
        displayName = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
        editingName = false
        isNameFocused = false
        viewModel.pushProfileEdit(context: modelContext)
    }
}

// MARK: - Camera Picker (UIImagePickerController wrapper)

struct CameraPickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        // Cropping happens in AvatarCropView (UIImagePickerController's
        // built-in edit step is unreliable about the chosen frame).
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            parent.onImagePicked(image)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onImagePicked(nil)
            parent.dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AccountView()
    }
    .environmentObject(SupabaseAuthManager.shared)
    .modelContainer(for: Wallet.self, inMemory: true)
}

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
    @State private var showCamera = false
    @State private var editingName = false
    @State private var tempName: String = ""
    @FocusState private var isNameFocused: Bool

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
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                if let image {
                    self.avatarImage = image
                    saveAvatar(image)
                }
            }
        }
        .confirmationDialog(
            L10n.Profile.photoOptions,
            isPresented: $showPhotoOptions,
            titleVisibility: .visible
        ) {
            Button(L10n.Profile.takePhoto) {
                showCamera = true
            }

            // Library selection is handled by the PhotosPicker overlay on the avatar.

            if avatarImage != nil {
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
            // Avatar
            ZStack {
                ProfileAvatarView(
                    image: avatarImage,
                    displayName: displayName.isEmpty ? L10n.Profile.namePlaceholder : displayName,
                    size: 110,
                    showEditBadge: true
                )

                // PhotosPicker overlay for library selection
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Color.clear
                        .frame(width: 110, height: 110)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .onTapGesture {
                showPhotoOptions = true
            }

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
            HStack(spacing: 10) {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(.cyan)
                Text("Account & Cloud Sync")
                    .font(.app(.headline, weight: .semibold))
                Spacer()
            }

            if !viewModel.isConfigured {
                Label("Cloud sync isn't configured in this build.",
                      systemImage: "exclamationmark.triangle")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Enable Cloud Sync (Beta)", isOn: $syncEnabled)
                    .font(.app(.body))

                if syncEnabled {
                    Divider()
                    if auth.isSignedIn {
                        signedInSection
                    } else {
                        AccountAuthForm(showsForeignDataWarning: viewModel.hasUnsyncedDataFromPreviousAccount)
                    }
                } else {
                    Text("When off, QuaraMoney runs fully offline on this device.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
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

    @ViewBuilder
    private var signedInSection: some View {
        LabeledContent {
            Text(auth.currentEmail ?? "")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
        } label: {
            Text("Signed in")
                .font(.app(.body))
        }

        Button {
            Task { await sync.syncNow(context: modelContext) }
        } label: {
            HStack {
                Label(sync.isInitialSyncInProgress ? "Setting up cloud sync…" : "Sync Now",
                      systemImage: "arrow.triangle.2.circlepath")
                if sync.isSyncing {
                    Spacer()
                    ProgressView()
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(sync.isSyncing)

        if sync.isInitialSyncInProgress {
            Text("Uploading your existing data for the first time. Keep the app open.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }

        if let last = sync.lastSyncDate {
            LabeledContent {
                Text(last.formatted(date: .abbreviated, time: .shortened))
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            } label: {
                Text("Last synced")
                    .font(.app(.body))
            }
        }

        if let error = sync.lastError {
            Text(error)
                .font(.app(.caption))
                .foregroundStyle(.red)
        }

        Divider()

        Button("Sign Out", role: .destructive) {
            Task { await auth.signOut() }
        }
        .disabled(auth.isWorking || sync.isSyncing)
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
                self.avatarImage = image
                saveAvatar(image)
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

// MARK: - Auth form (email/password + magic link)

private struct AccountAuthForm: View {
    let showsForeignDataWarning: Bool

    @EnvironmentObject private var auth: SupabaseAuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn

    private enum Mode { case signIn, signUp }

    private var canSubmit: Bool {
        !auth.isWorking && !email.isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .signIn ? "Sign In" : "Create Account")
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)

            if showsForeignDataWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("This device still has unsynced changes from a previous account. Sign back in to that account to save them — signing in to a different account will remove them from this device.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .padding(10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                Task {
                    switch mode {
                    case .signIn: await auth.signIn(email: email, password: password)
                    case .signUp: await auth.signUp(email: email, password: password)
                    }
                }
            } label: {
                HStack {
                    Spacer()
                    if auth.isWorking {
                        ProgressView()
                    } else {
                        Text(mode == .signIn ? "Sign In" : "Create Account")
                            .font(.app(.body, weight: .semibold))
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)

            HStack {
                Button(mode == .signIn ? "Need an account? Sign up"
                                       : "Have an account? Sign in") {
                    mode = (mode == .signIn) ? .signUp : .signIn
                }
                .font(.app(.footnote))

                Spacer()

                Button("Email me a magic link") {
                    Task { await auth.sendMagicLink(email: email) }
                }
                .font(.app(.footnote))
                .disabled(auth.isWorking || email.isEmpty)
            }

            if let error = auth.errorMessage {
                Text(error)
                    .font(.app(.caption))
                    .foregroundStyle(.red)
            }
            if let info = auth.infoMessage {
                Text(info)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
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
        picker.allowsEditing = true
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

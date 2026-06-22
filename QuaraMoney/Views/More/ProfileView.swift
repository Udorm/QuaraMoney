import SwiftUI
import PhotosUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("userDisplayName") private var displayName: String = ""
    @AppStorage("userAvatarPath") private var avatarPath: String = ""
    @AppStorage("appInstallDate") private var installDateTimestamp: Double = 0
    
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
    
    private var memberSinceDate: Date {
        if installDateTimestamp > 0 {
            return Date(timeIntervalSince1970: installDateTimestamp)
        }
        // If no install date recorded, set it now
        let now = Date()
        installDateTimestamp = now.timeIntervalSince1970
        return now
    }
    
    private var memberSinceFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: memberSinceDate)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Profile Header Card
                profileHeaderCard
                
                // MARK: - Quick Stats
                quickStatsCard
                
                // MARK: - Member Since
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
            // Record install date if not set
            if installDateTimestamp == 0 {
                installDateTimestamp = Date().timeIntervalSince1970
            }
            refreshTransactionCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidUpdate)) { _ in
            refreshTransactionCount()
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
            
            // PhotosPicker must be used inline — we'll handle it separately
            // This button triggers the photo picker via the PhotosPicker overlay
            
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
        guard !avatarPath.isEmpty else { return }
        let url = getAvatarURL()
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            self.avatarImage = image
        }
    }
    
    private func saveAvatar(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let url = getAvatarURL()
        try? data.write(to: url, options: .atomic)
        avatarPath = url.path()
    }
    
    private func removeAvatar() {
        let url = getAvatarURL()
        try? FileManager.default.removeItem(at: url)
        avatarPath = ""
        avatarImage = nil
    }
    
    private func getAvatarURL() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("profile_avatar.jpg")
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
        ProfileView()
    }
    .modelContainer(for: Wallet.self, inMemory: true)
}

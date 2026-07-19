
import SwiftUI
import SwiftData

struct MoreView: View {
    @State private var navigateToRecurring = false
    @AppStorage("userDisplayName") private var displayName: String = ""
    @AppStorage("userAvatarPath") private var avatarPath: String = ""
    @AppStorage("isSupabaseSyncEnabled") private var syncEnabled = false
    @ObservedObject private var auth = SupabaseAuthManager.shared
    @State private var avatarImage: UIImage?
    @State private var isVisible = false
    @State private var needsAvatarRefresh = true
    private var router = AppRouter.shared

    // Simple predicate only (a compound `isActive && deletedAt == nil` #Predicate
    // can hang SwiftData here); `isActive`/`isDue` filtering happens in memory.
    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil })
    private var recurringRules: [RecurringRule]

    /// Recurring occurrences due today or earlier — surfaced as a badge so the
    /// review inbox is discoverable without drilling into the Recurring screen.
    private var dueRecurringCount: Int {
        recurringRules.filter { RecurringRuleService.isDue($0) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Profile / Account Banner
                Section {
                    NavigationLink(destination: LazyView(AccountView())) {
                        HStack(spacing: 14) {
                            ProfileAvatarView(
                                image: avatarImage,
                                displayName: displayName.isEmpty ? L10n.Profile.namePlaceholder : displayName,
                                size: 52
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayName.isEmpty ? L10n.Profile.namePlaceholder : displayName)
                                    .appFont(.body, weight: .semibold)
                                    .foregroundStyle(displayName.isEmpty ? .secondary : .primary)

                                Text(accountSubtitle)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section(L10n.More.management) {
                    NavigationLink(destination: LazyView(WalletListView())) {
                        Label {
                            Text(L10n.Wallet.title)
                        } icon: {
                            ListIconView(systemImage: "wallet.bifold.fill", color: .indigo)
                        }
                    }

                    NavigationLink(destination: LazyView(CategoryListView())) {
                        Label {
                            Text(L10n.More.categories)
                        } icon: {
                            ListIconView(systemImage: "tag.fill", color: .green)
                        }
                    }

                    NavigationLink(destination: LazyView(DebtListView())) {
                        Label {
                            Text(L10n.Debt.title)
                        } icon: {
                            ListIconView(systemImage: "person.2.crop.square.stack", color: .red)
                        }
                    }

                    NavigationLink(destination: LazyView(RecurringRuleListView())) {
                        Label {
                            Text(L10n.More.recurringRules)
                        } icon: {
                            ListIconView(systemImage: "repeat", color: .teal)
                        }
                    }
                    .badge(dueRecurringCount)
                }

                Section(L10n.More.insights) {
                    NavigationLink(destination: LazyView(EventListView())) {
                        Label {
                            Text(L10n.Event.title)
                        } icon: {
                            ListIconView(systemImage: "party.popper", color: .orange)
                        }
                    }
                }

                Section(L10n.More.app) {
                    NavigationLink(destination: LazyView(SettingsView())) {
                        Label {
                            Text(L10n.Settings.title)
                        } icon: {
                            ListIconView(systemImage: "gear", color: Color(.systemGray))
                        }
                    }
                }
            }
            .navigationTitle(L10n.More.title)
            .navigationDestination(isPresented: $navigateToRecurring) {
                RecurringRuleListView()
            }
            // Recurring deep link: consumed from the router (staged by
            // ContentView) once this tab is actually visible — same pattern as
            // the Home quick action, no notification/timer race.
            .onChange(of: router.pendingRecurringReview) { _, _ in
                consumePendingRecurringReview()
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
                // A sync replaced/removed the avatar file — reload the banner image.
                if isVisible {
                    loadAvatar()
                } else {
                    needsAvatarRefresh = true
                }
            }
            .onAppear {
                isVisible = true
                if needsAvatarRefresh {
                    loadAvatar()
                }
                // Consume a deep-link that arrived before this view existed
                // (LazyView delays creation until the More tab is selected).
                consumePendingRecurringReview()
            }
            .onDisappear { isVisible = false }
        }
    }

    /// Pushes the Recurring review screen for a staged deep link, but only
    /// while this tab is actually on screen.
    private func consumePendingRecurringReview() {
        guard isVisible, router.pendingRecurringReview else { return }
        router.pendingRecurringReview = false
        navigateToRecurring = true
    }

    /// Banner subtitle: signed-in account email when cloud sync is active,
    /// otherwise the edit-profile hint.
    private var accountSubtitle: String {
        if syncEnabled, let email = auth.currentEmail, !email.isEmpty {
            return email
        }
        return L10n.Profile.editProfile
    }

    private func loadAvatar() {
        needsAvatarRefresh = false
        guard !avatarPath.isEmpty else {
            avatarImage = nil
            return
        }
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsDir.appendingPathComponent("profile_avatar.jpg")
        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            self.avatarImage = image
        } else {
            avatarImage = nil
        }
    }
}

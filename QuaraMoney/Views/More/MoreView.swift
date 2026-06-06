
import SwiftUI

struct MoreView: View {
    @State private var showBudgetWizard = false
    @AppStorage("userDisplayName") private var displayName: String = ""
    @AppStorage("userAvatarPath") private var avatarPath: String = ""
    @State private var avatarImage: UIImage?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Profile Banner
                Section {
                    NavigationLink(destination: ProfileView()) {
                        HStack(spacing: 14) {
                            ProfileAvatarView(
                                image: avatarImage,
                                displayName: displayName.isEmpty ? L10n.Profile.namePlaceholder : displayName,
                                size: 52
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayName.isEmpty ? L10n.Profile.namePlaceholder : displayName)
                                    .font(.app(.body, weight: .semibold))
                                    .foregroundStyle(displayName.isEmpty ? .secondary : .primary)

                                Text(L10n.Profile.editProfile)
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section(L10n.More.planningTools) {
                    Button {
                        showBudgetWizard = true
                    } label: {
                        Label {
                            Text(L10n.More.budgetWizard)
                                .foregroundStyle(.primary)
                        } icon: {
                            ListIconView(systemImage: "wand.and.stars", color: .purple)
                        }
                    }
                }

                Section(L10n.More.features) {
                    NavigationLink(destination: BudgetInsightsView()) {
                        Label {
                            Text(L10n.Budget.insights)
                        } icon: {
                            ListIconView(systemImage: "chart.line.uptrend.xyaxis", color: .blue)
                        }
                    }

                    NavigationLink(destination: EventListView()) {
                        Label {
                            Text(L10n.Event.title)
                        } icon: {
                            ListIconView(systemImage: "party.popper", color: .orange)
                        }
                    }

                    NavigationLink(destination: RecurringRuleListView()) {
                        Label {
                            Text(L10n.More.recurringRules)
                        } icon: {
                            ListIconView(systemImage: "repeat", color: .teal)
                        }
                    }

                    NavigationLink(destination: DebtListView()) {
                        Label {
                            Text(L10n.Debt.title)
                        } icon: {
                            ListIconView(systemImage: "person.2.crop.square.stack", color: .red)
                        }
                    }
                }

                Section(L10n.More.management) {
                    NavigationLink(destination: WalletListView()) {
                        Label {
                            Text(L10n.Wallet.title)
                        } icon: {
                            ListIconView(systemImage: "wallet.bifold.fill", color: .indigo)
                        }
                    }

                    NavigationLink(destination: CategoryListView()) {
                        Label {
                            Text(L10n.More.categories)
                        } icon: {
                            ListIconView(systemImage: "tag.fill", color: .green)
                        }
                    }
                }

                Section(L10n.More.app) {
                    NavigationLink(destination: SettingsView()) {
                        Label {
                            Text(L10n.Settings.title)
                        } icon: {
                            ListIconView(systemImage: "gear", color: Color(.systemGray))
                        }
                    }
                }
            }
            .navigationTitle(L10n.More.title)
            .sheet(isPresented: $showBudgetWizard) {
                BudgetSetupWizardView()
            }
            .onAppear {
                loadAvatar()
            }
        }
    }

    private func loadAvatar() {
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

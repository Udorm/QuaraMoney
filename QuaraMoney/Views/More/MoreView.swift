
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
                    NavigationLink(destination: BudgetInsightsView()) {
                        Label(L10n.Budget.insights, systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    Button {
                        showBudgetWizard = true
                    } label: {
                        Label(L10n.More.budgetWizard, systemImage: "wand.and.stars")
                    }
                }
                
                Section(L10n.More.features) {
                    NavigationLink(destination: EventListView()) {
                        Label(L10n.Event.title, systemImage: "party.popper")
                    }
                    
                    NavigationLink(destination: RecurringRuleListView()) {
                        Label(L10n.More.recurringRules, systemImage: "repeat")
                    }
                }
                
                Section(L10n.More.management) {
                    NavigationLink(destination: DebtListView()) {
                        Label(L10n.Debt.title, systemImage: "person.2.crop.square.stack")
                    }
                    
                    NavigationLink(destination: CategoryListView()) {
                        Label(L10n.More.categories, systemImage: "list.bullet")
                    }
                }
                
                Section(L10n.More.app) {
                    NavigationLink(destination: SettingsView()) {
                        Label(L10n.Settings.title, systemImage: "gear")
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

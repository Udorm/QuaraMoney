import SwiftUI
import SwiftData
import Combine

// NOTE: the pre-iOS-18 `LegacyContentView` (NavigationSplitView + tag-based
// TabView) was deleted — the deployment target is iOS 26, so the #available
// branch could never take the fallback path. iPad/regular width is handled by
// `.tabViewStyle(.sidebarAdaptable)` below.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { $0.deletedAt == nil }) private var wallets: [Wallet]
    @Query(filter: #Predicate<RecurringRule> { $0.deletedAt == nil }) private var recurringRules: [RecurringRule]
    @AppStorage("useSidebarOniPad") private var useSidebarOniPad: Bool = true
    @AppStorage("analyticsProMode") private var analyticsProMode: Bool = false
    @State private var showCreateWallet = false
    @State private var selectedTab: Int = 0

    var body: some View {
        Group {
            if useSidebarOniPad {
                TabView(selection: $selectedTab) {
                    Tab(value: 0) {
                        HomeView()
                    } label: {
                        VStack {
                            Image(systemName: "house.fill")
                            Text(L10n.Tab.home)
                                .appFont(.caption2)
                        }
                    }

                    Tab(value: 1) {
                        LazyView(AnalysisView())
                    } label: {
                        VStack {
                            Image(systemName: "chart.pie")
                            Text(L10n.Tab.analysis)
                                .appFont(.caption2)
                        }
                    }

                    Tab(value: 2) {
                        LazyView(BudgetTabView())
                    } label: {
                        VStack {
                            Image(systemName: "target")
                            Text("tab.plan".localized)
                                .appFont(.caption2)
                        }
                    }

                    Tab(value: 3) {
                        LazyView(MoreView())
                    } label: {
                        VStack {
                            Image(systemName: "ellipsis")
                            Text(L10n.Tab.more)
                                .appFont(.caption2)
                        }
                    }
                    .badge(dueRecurringCount)
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: $selectedTab) {
                    Tab(L10n.Tab.home, systemImage: "house.fill", value: 0) {
                        HomeView()
                    }

                    Tab(L10n.Tab.analysis, systemImage: "chart.pie", value: 1) {
                        LazyView(AnalysisView())
                    }

                    Tab("tab.plan".localized, systemImage: "target", value: 2) {
                        LazyView(BudgetTabView())
                    }

                    Tab(L10n.Tab.more, systemImage: "ellipsis", value: 3) {
                        LazyView(MoreView())
                    }
                    .badge(dueRecurringCount)
                }
                .tabViewStyle(.automatic)
            }
        }
        .onAppear {
            if wallets.isEmpty {
                showCreateWallet = true
            }
        }
        // Cross-tab deep links: switch the tab and stage the intent on the
        // router; the destination view consumes it in onAppear/onChange once it
        // is actually visible. No timers — state + visibility can't race the
        // tab-switch animation.
        .onReceive(NotificationCenter.default.publisher(for: .openAddTransaction)) { _ in
            selectedTab = 0
            AppRouter.shared.pendingAddTransaction = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecurringReview)) { _ in
            AppRouter.shared.pendingRecurringReview = true
            selectedTab = 3 // More tab — MoreView pushes the Recurring screen
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProAnalytics)) { _ in
            analyticsProMode = true
            selectedTab = 1 // Analysis tab — routes to the Pro dashboard
        }
        .sheet(isPresented: $showCreateWallet) {
            AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
                .interactiveDismissDisabled()
        }
    }

    /// Matches the recurring inbox count shown in More. Keeping this query at
    /// the tab root lets the badge update even while MoreView remains lazy.
    private var dueRecurringCount: Int {
        recurringRules.filter { RecurringRuleService.isDue($0) }.count
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Wallet.self, RecurringRule.self], inMemory: true)
}

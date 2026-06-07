import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            iOS18ContentView()
        } else {
            LegacyContentView()
        }
    }
}

@available(iOS 18.0, *)
struct iOS18ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @AppStorage("useSidebarOniPad") private var useSidebarOniPad: Bool = true
    @State private var showCreateWallet = false
    @State private var selectedTab: Int = 0 
    
    var body: some View {
        Group {
            if useSidebarOniPad {
                TabView(selection: $selectedTab) {
                    Tab(value: 0) {
                        HomeView(modelContext: modelContext)
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
                            Image(systemName: "dollarsign.circle.fill")
                            Text(L10n.Budget.title)
                                .appFont(.caption2)
                        }
                    }

                    Tab(value: 3) {
                        LazyView(MoreView())
                    } label: {
                        VStack {
                            Image(systemName: "ellipsis.circle")
                            Text(L10n.Tab.more)
                                .appFont(.caption2)
                        }
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
            } else {
                TabView(selection: $selectedTab) {
                    Tab(L10n.Tab.home, systemImage: "house.fill", value: 0) {
                        HomeView(modelContext: modelContext)
                    }
                    
                    Tab(L10n.Tab.analysis, systemImage: "chart.pie", value: 1) {
                        LazyView(AnalysisView())
                    }
                    
                    Tab(L10n.Budget.title, systemImage: "dollarsign.circle.fill", value: 2) {
                        LazyView(BudgetTabView())
                    }

                    Tab(L10n.Tab.more, systemImage: "ellipsis.circle", value: 3) {
                        LazyView(MoreView())
                    }
                }
                .tabViewStyle(.automatic)
            }
        }
        .onAppear {
            if wallets.isEmpty {
                showCreateWallet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddTransaction)) { _ in
            selectedTab = 0
        }
        .sheet(isPresented: $showCreateWallet) {
            AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
                .interactiveDismissDisabled()
        }
    }
}

struct LegacyContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @AppStorage("useSidebarOniPad") private var useSidebarOniPad: Bool = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showCreateWallet = false
    @State private var selectedTab: Int? = 0
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        Group {
            if horizontalSizeClass == .regular && useSidebarOniPad {
                // Sidebar for iPad / Mac / Regular width screens
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    List(selection: $selectedTab) {
                        NavigationLink(value: 0) {
                            Label(L10n.Tab.home, systemImage: "house.fill")
                        }
                        NavigationLink(value: 1) {
                            Label(L10n.Tab.analysis, systemImage: "chart.pie")
                        }
                        NavigationLink(value: 2) {
                            Label(L10n.Budget.title, systemImage: "dollarsign.circle.fill")
                        }
                        NavigationLink(value: 3) {
                            Label(L10n.Tab.more, systemImage: "ellipsis.circle")
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle("QuaraMoney")
                    .appFont(.body)
                } detail: {
                    if let selectedTab = selectedTab {
                        detailView(for: selectedTab)
                            .id(selectedTab)
                    } else {
                        Text("Select an item")
                            .appFont(.headline)
                    }
                }
            } else {
                // Tab Bar for iPhone / Compact width screens
                TabView(selection: Binding($selectedTab, replacingNilWith: 0)) {
                    HomeView(modelContext: modelContext)
                        .tabItem {
                            Label(L10n.Tab.home, systemImage: "house.fill")
                        }
                        .tag(0)
                    
                    LazyView(AnalysisView())
                        .tabItem {
                            Label(L10n.Tab.analysis, systemImage: "chart.pie")
                        }
                        .tag(1)
                    
                    LazyView(BudgetTabView())
                        .tabItem {
                            Label(L10n.Budget.title, systemImage: "dollarsign.circle.fill")
                        }
                        .tag(2)

                    LazyView(MoreView())
                        .tabItem {
                            Label(L10n.Tab.more, systemImage: "ellipsis.circle")
                        }
                        .tag(3)
                }
            }
        }
        .onAppear {
            if wallets.isEmpty {
                showCreateWallet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAddTransaction)) { _ in
            selectedTab = 0
        }
        .sheet(isPresented: $showCreateWallet) {
            AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
                .interactiveDismissDisabled()
        }
    }

    @ViewBuilder
    private func detailView(for tab: Int) -> some View {
        switch tab {
        case 0: HomeView(modelContext: modelContext)
        case 1: LazyView(AnalysisView())
        case 2: LazyView(BudgetTabView())
        case 3: LazyView(MoreView())
        default: HomeView(modelContext: modelContext)
        }
    }
}

extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith defaultValue: Value) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { source.wrappedValue = $0 }
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Wallet.self, inMemory: true)
}

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @State private var showCreateWallet = false
    @State private var selectedTab: TabIdentifier = .home
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(modelContext: modelContext)
            }
            
            Tab("Budget", systemImage: "dollarsign.circle.fill", value: .budgets) {
                BudgetTabView()
            }
            
            Tab("Analysis", systemImage: "chart.pie", value: .analysis) {
                AnalysisView()
            }
             
            Tab("More", systemImage: "ellipsis.circle", value: .more) {
                MoreView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onAppear {
            if wallets.isEmpty {
                showCreateWallet = true
            }
        }
        .sheet(isPresented: $showCreateWallet) {
            AddWalletView(viewModel: AddWalletViewModel(dataService: SwiftDataService(modelContext: modelContext)))
                .interactiveDismissDisabled() // Force user to create a wallet
        }
    }
    
    enum TabIdentifier: Hashable {
        case home, budgets, analysis, more
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Wallet.self, inMemory: true)
}

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        TabView {
            // Home
            HomeView(modelContext: modelContext)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            // Wallets
            WalletListView()
                .tabItem {
                    Label("Wallets", systemImage: "wallet.pass")
                }
            
            // Analysis
            AnalysisView()
                .tabItem {
                    Label("Analysis", systemImage: "chart.pie")
                }
             
            // More
            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Wallet.self, inMemory: true)
}

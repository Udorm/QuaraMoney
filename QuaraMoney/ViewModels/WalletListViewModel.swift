import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
class WalletListViewModel: BaseViewModel {
    var wallets: [Wallet] = []
    
    // We can inject the context or rely on the query in the View. 
    // For MVVM with SwiftData, usually the View tracks the Query, but for logic we might want it here.
    // However, to keep it "Clean" and use SwiftData power, we often let the View have the @Query 
    // and the VM handle actions. 
    // BUT, since we have a DataService, let's use it for actions.
    
    // NOTE: In strict MVVM + SwiftData, fetching is often done by the Service or the View's @Query.
    // To strictly follow the requested architecture (Service layer), fetching *could* be here, 
    // but @Query is much more performant for SwiftUI. 
    // I will stick to @Query in the View for the source of truth, and this VM for *actions* (delete).
    
    func deleteWallet(at offsets: IndexSet, from currentWallets: [Wallet]) {
        for index in offsets {
            let wallet = currentWallets[index]
            // Soft-delete (tombstone) so the deletion replicates to other devices.
            SoftDeleteService.deleteWallet(wallet, strategy: .deleteTransactions)
        }
    }
}

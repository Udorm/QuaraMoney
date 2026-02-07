import Foundation
import SwiftUI
import Combine

@MainActor
class AddWalletViewModel: BaseViewModel {
    @Published var name: String = ""
    @Published var currencyCode: String = "USD"
    @Published var icon: String = "wallet.pass"
    @Published var colorHex: String = "#007AFF" // Default iOS Blue
    
    private(set) var walletToEdit: Wallet?
    
    init(dataService: DataService, walletToEdit: Wallet? = nil) {
        super.init(dataService: dataService)
        self.walletToEdit = walletToEdit
        
        if let wallet = walletToEdit {
            self.name = wallet.name
            self.currencyCode = wallet.currencyCode
            self.icon = wallet.icon
            self.colorHex = wallet.colorHex
        }
    }
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isEditing: Bool {
        walletToEdit != nil
    }
    
    var isArchived: Bool {
        walletToEdit?.isArchived ?? false
    }
    
    func saveWallet() {
        guard isValid else { return }
        
        if let wallet = walletToEdit {
            wallet.name = name
            wallet.currencyCode = currencyCode
            wallet.icon = icon
            wallet.colorHex = colorHex
            // Invalidate balance cache so it recalculates with the new currency
            wallet.invalidateBalanceCache()
        } else {
            let newWallet = Wallet(
                name: name,
                currencyCode: currencyCode,
                icon: icon,
                colorHex: colorHex
            )
            dataService.insert(newWallet)
        }
    }
    
    func archiveWallet() {
        guard let wallet = walletToEdit else { return }
        wallet.isArchived = true
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
    
    func unarchiveWallet() {
        guard let wallet = walletToEdit else { return }
        wallet.isArchived = false
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
    
    func deleteWallet() {
        guard let wallet = walletToEdit else { return }
        dataService.delete(wallet)
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

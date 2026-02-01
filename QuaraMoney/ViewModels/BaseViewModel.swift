import Foundation
import SwiftData
import Combine

@MainActor
class BaseViewModel: ObservableObject {
    let dataService: DataService
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    init(dataService: DataService) {
        self.dataService = dataService
    }
    
    func handleError(_ error: Error) {
        self.errorMessage = error.localizedDescription
        print("Error: \(error)")
    }
}

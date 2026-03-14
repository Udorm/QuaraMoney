import Foundation
import SwiftData

@Observable
@MainActor
class BaseViewModel {
    let dataService: DataService

    var isLoading: Bool = false
    var errorMessage: String?

    init(dataService: DataService) {
        self.dataService = dataService
    }

    func handleError(_ error: Error) {
        self.errorMessage = error.localizedDescription
        #if DEBUG
        print("Error: \(error)")
        #endif
    }
}

import SwiftUI
import LocalAuthentication
import Combine

@MainActor
class SecurityManager: ObservableObject {
    static let shared = SecurityManager()
    
    @Published var isAppLocked = false
    @Published var isAuthenticating = false
    @AppStorage("isAppLockEnabled") var isAppLockEnabled = false
    
    private init() {}
    
    func authenticate() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            isAuthenticating = true
            
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock QuaraMoney") { success, authenticationError in
                DispatchQueue.main.async {
                    self.isAuthenticating = false
                    if success {
                        self.isAppLocked = false
                    } else {
                        // Keep locked if failed
                    }
                }
            }
        } else {
            // No biometrics/passcode available
            isAppLocked = false 
        }
    }
    
    func lockApp() {
        if isAppLockEnabled {
            isAppLocked = true
        }
    }
}

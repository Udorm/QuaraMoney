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
        // Avoid stacking multiple biometric prompts when several triggers
        // (cold-launch, scene-active, lock-view appear) fire close together.
        guard !isAuthenticating else { return }

        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            isAuthenticating = true
            
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock QuaraMoney") { success, authenticationError in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isAuthenticating = false
                    if success {
                        self.isAppLocked = false
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
    
    // MARK: - Keychain
    
    private let apiKeyService = "com.quaramoney.gemini.apikey"
    private let apiKeyAccount = "user"
    
    func saveAPIKey(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: apiKeyService,
            kSecAttrAccount: apiKeyAccount,
            kSecValueData: data
        ] as [String: Any]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func getAPIKey() -> String? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: apiKeyService,
            kSecAttrAccount: apiKeyAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ] as [String: Any]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) {
            return key
        }
        return nil
    }
    
    func deleteAPIKey() {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: apiKeyService,
            kSecAttrAccount: apiKeyAccount
        ] as [String: Any]
        
        SecItemDelete(query as CFDictionary)
    }
}

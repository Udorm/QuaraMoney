import SwiftUI
import LocalAuthentication
import Observation

@MainActor
@Observable
final class SecurityManager {
    static let shared = SecurityManager()
    
    var isAppLocked: Bool
    var isAuthenticating = false
    /// Set when authentication cannot run at all (e.g. the device passcode was
    /// removed). Shown on the lock screen; the app stays locked (fail closed).
    var lockErrorMessage: String?
    var isAppLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAppLockEnabled, forKey: "isAppLockEnabled")
        }
    }
    
    private init() {
        let isEnabled = UserDefaults.standard.bool(forKey: "isAppLockEnabled")
        isAppLockEnabled = isEnabled
        // The cold-launch decision is made while the singleton is constructed,
        // before SwiftUI builds the first scene frame.
        isAppLocked = isEnabled
    }
    
    func authenticate() {
        // Avoid stacking multiple biometric prompts when several triggers
        // (cold-launch, scene-active, lock-view appear) fire close together.
        guard !isAuthenticating else { return }

        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            isAuthenticating = true
            lockErrorMessage = nil

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
            // No passcode/biometrics available. Fail closed: this is a finance
            // app, so the lock must not silently open. The user can regain
            // access by setting a device passcode (App Lock stays enforced).
            lockErrorMessage = "security.lockUnavailable".localized
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
        let baseQuery = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: apiKeyService,
            kSecAttrAccount: apiKeyAccount
        ] as [String: Any]

        // Delete existing item first (also clears any item saved under the old
        // default accessibility class).
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        // Readable only while unlocked; never migrates via backup to another device.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
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

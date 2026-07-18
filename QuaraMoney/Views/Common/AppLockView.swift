import SwiftUI

/// Full-screen gate shown when biometric app-lock is enabled and the app is
/// locked. Blocks all content until the user authenticates.
struct AppLockView: View {
    let onUnlock: () -> Void
    private var securityManager = SecurityManager.shared

    init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .appFont(size: 64)
                    .foregroundStyle(.tint)

                Text(L10n.Security.lockedTitle)
                    .appFont(.title2, weight: .bold)

                Text(L10n.Security.lockedMessage)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button(action: onUnlock) {
                    Label(L10n.Security.unlock, systemImage: "faceid")
                        .appFont(.body, weight: .semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .padding(.top, 8)

                if let lockError = securityManager.lockErrorMessage {
                    Text(lockError)
                        .appFont(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
        .onAppear(perform: onUnlock)
    }
}

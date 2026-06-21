import SwiftUI

/// Settings → Cloud Sync. The Phase 1 entry point for accounts.
///
/// The master toggle drives `isSupabaseSyncEnabled` (the kill-switch). While off,
/// the app is fully local — exactly as before. While on, the user can sign in;
/// actual data sync is added in later phases.
struct CloudSyncSettingsView: View {
    @EnvironmentObject private var auth: SupabaseAuthManager
    @AppStorage("isSupabaseSyncEnabled") private var syncEnabled = false

    var body: some View {
        Form {
            if !SupabaseConfig.isConfigured {
                Section {
                    Label(
                        "Cloud sync isn't configured in this build.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Toggle("Enable Cloud Sync (Beta)", isOn: $syncEnabled)
                } footer: {
                    Text("When off, QuaraMoney runs fully offline on this device. " +
                         "Beta: sign-in only for now — your data starts syncing in a later update.")
                }

                if syncEnabled {
                    if auth.isSignedIn {
                        Section("Account") {
                            LabeledContent("Signed in", value: auth.currentEmail ?? "")
                            Button("Sign Out", role: .destructive) {
                                Task { await auth.signOut() }
                            }
                            .disabled(auth.isWorking)
                        }
                    } else {
                        AuthFormView()
                    }
                }
            }
        }
        .navigationTitle("Cloud Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if syncEnabled { auth.start() } }
        .onChange(of: syncEnabled) { _, enabled in
            if enabled { auth.start() }
        }
    }
}

/// Email/password sign-in & sign-up, with an optional magic-link shortcut.
private struct AuthFormView: View {
    @EnvironmentObject private var auth: SupabaseAuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn

    private enum Mode { case signIn, signUp }

    private var canSubmit: Bool {
        !auth.isWorking && !email.isEmpty && !password.isEmpty
    }

    var body: some View {
        Section(mode == .signIn ? "Sign In" : "Create Account") {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)

            Button {
                Task {
                    switch mode {
                    case .signIn: await auth.signIn(email: email, password: password)
                    case .signUp: await auth.signUp(email: email, password: password)
                    }
                }
            } label: {
                HStack {
                    Text(mode == .signIn ? "Sign In" : "Create Account")
                    if auth.isWorking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(!canSubmit)

            Button(mode == .signIn ? "Need an account? Sign up"
                                   : "Have an account? Sign in") {
                mode = (mode == .signIn) ? .signUp : .signIn
            }
            .appFont(.footnote)
        }

        Section {
            Button("Email me a magic link") {
                Task { await auth.sendMagicLink(email: email) }
            }
            .disabled(auth.isWorking || email.isEmpty)
        } footer: {
            Text("Sends a one-tap sign-in link to the email above.")
        }

        if let error = auth.errorMessage {
            Section {
                Text(error).foregroundStyle(.red)
            }
        }
        if let info = auth.infoMessage {
            Section {
                Text(info).foregroundStyle(.secondary)
            }
        }
    }
}

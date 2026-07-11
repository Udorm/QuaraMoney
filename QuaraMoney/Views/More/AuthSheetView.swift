import SwiftUI

/// Dedicated sign-in / create-account sheet, presented from `AccountView`.
///
/// Cloud-sync/auth copy is intentionally English-only for now, matching the
/// rest of the beta sync UI in `AccountView`.
struct AuthSheetView: View {
    enum Mode: String, Identifiable {
        case signIn, signUp
        var id: String { rawValue }
    }

    let showsForeignDataWarning: Bool
    @State var mode: Mode

    @EnvironmentObject private var auth: SupabaseAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, email, password, confirmPassword }

    private var isSignIn: Bool { mode == .signIn }

    /// Only shown/validated in create-account mode.
    private var passwordsMatch: Bool { password == confirmPassword }

    private var canSubmit: Bool {
        guard !auth.isWorking,
              !email.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isSignIn {
            return password.count >= 1
        }
        // Create account: name required, 6-char password minimum (Supabase
        // enforces it), and the confirmation must match.
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
            && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if showsForeignDataWarning {
                        messageBanner(
                            icon: "exclamationmark.triangle.fill",
                            tint: .orange,
                            text: "This device still has unsynced changes from a previous account. Sign back in to that account to save them — signing in to a different account will remove them from this device."
                        )
                    }

                    credentialFields
                    submitButton

                    if isSignIn {
                        VStack(spacing: 14) {
                            magicLinkButton
                            forgotPasswordButton
                        }
                    }

                    if let error = auth.errorMessage {
                        messageBanner(icon: "exclamationmark.circle.fill", tint: .red, text: error)
                    }
                    if let info = auth.infoMessage {
                        messageBanner(icon: "envelope.badge.fill", tint: .blue, text: info)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) { modeSwitchFooter }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                }
            }
        }
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(auth.isWorking)
        .onAppear { clearMessages() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)

                Image(systemName: isSignIn ? "icloud.fill" : "person.crop.circle.fill.badge.plus")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }

            VStack(spacing: 6) {
                Text(isSignIn ? "Welcome Back" : "Create Your Account")
                    .font(.app(.title2, weight: .bold))
                    .contentTransition(.opacity)

                Text(isSignIn
                     ? "Sign in to keep your data backed up and in sync."
                     : "Your wallets, transactions, and budgets — securely backed up in the cloud.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Fields

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                if !isSignIn {
                    fieldRow(icon: "person") {
                        TextField("Name", text: $name)
                            .font(.app(.body))
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }
                    }
                    fieldDivider
                }

                fieldRow(icon: "envelope") {
                    TextField("Email", text: $email)
                        .font(.app(.body))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                fieldDivider

                fieldRow(icon: "lock") {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .font(.app(.body))
                    .textContentType(isSignIn ? .password : .newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(isSignIn ? .go : .next)
                    .onSubmit {
                        if isSignIn {
                            if canSubmit { submit() }
                        } else {
                            focusedField = .confirmPassword
                        }
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }

                if !isSignIn {
                    fieldDivider

                    fieldRow(icon: "lock.rotation") {
                        Group {
                            if showPassword {
                                TextField("Confirm password", text: $confirmPassword)
                            } else {
                                SecureField("Confirm password", text: $confirmPassword)
                            }
                        }
                        .font(.app(.body))
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { submit() } }
                    }
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

            if !isSignIn {
                if !confirmPassword.isEmpty && !passwordsMatch {
                    Label("Passwords don't match.", systemImage: "exclamationmark.circle")
                        .font(.app(.caption))
                        .foregroundStyle(.red)
                        .padding(.leading, 16)
                } else {
                    Text("Use at least 6 characters.")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
            }
        }
    }

    /// One labelled input row inside the grouped field card.
    private func fieldRow<Content: View>(
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var fieldDivider: some View {
        Divider().padding(.leading, 52)
    }

    // MARK: - Actions

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            ZStack {
                // Keep the button height stable while the label swaps to a spinner.
                Text(isSignIn ? "Sign In" : "Create Account").hidden()
                if auth.isWorking {
                    ProgressView()
                } else {
                    Text(isSignIn ? "Sign In" : "Create Account")
                }
            }
            .font(.app(.body, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    private var magicLinkButton: some View {
        Button {
            Task { await auth.sendMagicLink(email: email) }
        } label: {
            Label("Email me a sign-in link instead", systemImage: "wand.and.sparkles")
                .font(.app(.footnote, weight: .medium))
        }
        .disabled(auth.isWorking || email.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var forgotPasswordButton: some View {
        Button {
            Task { await auth.sendPasswordReset(email: email) }
        } label: {
            Text("Forgot password?")
                .font(.app(.footnote, weight: .medium))
        }
        .disabled(auth.isWorking || email.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var modeSwitchFooter: some View {
        HStack(spacing: 4) {
            Text(isSignIn ? "Don't have an account?" : "Already have an account?")
                .foregroundStyle(.secondary)

            Button(isSignIn ? "Sign Up" : "Sign In") {
                withAnimation(.snappy) {
                    mode = isSignIn ? .signUp : .signIn
                }
                clearMessages()
            }
            .fontWeight(.semibold)
            .disabled(auth.isWorking)
        }
        .font(.app(.footnote))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func messageBanner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            tint.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func submit() {
        focusedField = nil
        Task {
            switch mode {
            case .signIn: await auth.signIn(email: email, password: password)
            case .signUp: await auth.signUp(email: email, password: password, name: name)
            }
        }
    }

    private func clearMessages() {
        auth.errorMessage = nil
        auth.infoMessage = nil
    }
}

#Preview("Sign In") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AuthSheetView(showsForeignDataWarning: false, mode: .signIn)
            .environmentObject(SupabaseAuthManager.shared)
    }
}

#Preview("Sign Up") {
    Color.clear.sheet(isPresented: .constant(true)) {
        AuthSheetView(showsForeignDataWarning: true, mode: .signUp)
            .environmentObject(SupabaseAuthManager.shared)
    }
}

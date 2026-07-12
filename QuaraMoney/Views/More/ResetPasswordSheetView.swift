import SwiftUI

/// "Set a new password" sheet, presented from the app root when a
/// password-recovery deep link signs the user in (`quaramoney://auth-callback`
/// with `type=recovery` → `SupabaseAuthManager.passwordRecoveryPending`).
struct ResetPasswordSheetView: View {
    @EnvironmentObject private var auth: SupabaseAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @FocusState private var focusedField: Field?

    private enum Field { case password, confirmPassword }

    private var passwordsMatch: Bool { password == confirmPassword }

    private var canSubmit: Bool {
        // Supabase enforces a 6-character minimum on new passwords.
        !auth.isWorking && password.count >= 6 && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    passwordFields
                    submitButton

                    if let error = auth.errorMessage {
                        messageBanner(icon: "exclamationmark.circle.fill", tint: .red, text: error)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
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
        .onAppear {
            auth.errorMessage = nil
            auth.infoMessage = nil
            focusedField = .password
        }
        .onDisappear {
            // Dismissing without saving keeps the recovery session signed in;
            // just stop re-presenting the sheet.
            auth.passwordRecoveryPending = false
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

                Image(systemName: "key.fill")
                    .appFont(size: 32, weight: .medium)
                    .foregroundStyle(.white)
            }

            VStack(spacing: 6) {
                Text("auth.setNewPassword".localized)
                    .appFont(.title2, weight: .bold)

                Text(auth.currentEmail.map { "auth.resetSubtitleWithEmail".localized(with: $0) } ?? "auth.resetSubtitle".localized)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Fields

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    Group {
                        if showPassword {
                            TextField("auth.newPassword".localized, text: $password)
                        } else {
                            SecureField("auth.newPassword".localized, text: $password)
                        }
                    }
                    .appFont(.body)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirmPassword }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword ? "auth.hidePassword".localized : "auth.showPassword".localized)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .padding(.leading, 52)

                HStack(spacing: 12) {
                    Image(systemName: "lock.rotation")
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    Group {
                        if showPassword {
                            TextField("auth.confirmNewPassword".localized, text: $confirmPassword)
                        } else {
                            SecureField("auth.confirmNewPassword".localized, text: $confirmPassword)
                        }
                    }
                    .appFont(.body)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .confirmPassword)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { submit() } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )

            if !confirmPassword.isEmpty && !passwordsMatch {
                Label("auth.passwordsDontMatch".localized, systemImage: "exclamationmark.circle")
                    .appFont(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, 16)
            } else {
                Text("auth.passwordMinLength".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
        }
    }

    // MARK: - Actions

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            ZStack {
                // Keep the button height stable while the label swaps to a spinner.
                Text("auth.updatePassword".localized).hidden()
                if auth.isWorking {
                    ProgressView()
                } else {
                    Text("auth.updatePassword".localized)
                }
            }
            .appFont(.body, weight: .semibold)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    private func messageBanner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .appFont(.caption)
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
            if await auth.updatePassword(password) {
                dismiss()
            }
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        ResetPasswordSheetView()
            .environmentObject(SupabaseAuthManager.shared)
    }
}

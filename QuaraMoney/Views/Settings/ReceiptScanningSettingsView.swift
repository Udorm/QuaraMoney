import SwiftUI

/// Dedicated, plain-language screen for the (optional) Gemini-powered receipt
/// scanning. Replaces the cramped inline "Gemini API Key" field that assumed
/// the user already knew what an API key was.
struct ReceiptScanningSettingsView: View {
    @StateObject private var securityManager = SecurityManager.shared

    /// Local mirror of the stored key so the field and status stay in sync
    /// without re-reading the keychain on every keystroke.
    @State private var apiKey: String = ""

    /// Google AI Studio — where a free Gemini key is created.
    private let getKeyURL = URL(string: "https://aistudio.google.com/app/apikey")!

    private var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Form {
            Section {
                Text("settings.aiScanning.intro".localized)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }

            // Explain the two modes in plain language.
            Section {
                modeRow(
                    icon: "iphone",
                    tint: .green,
                    title: "settings.aiScanning.onDeviceTitle".localized,
                    body: "settings.aiScanning.onDeviceBody".localized,
                    active: !hasKey
                )
                modeRow(
                    icon: "sparkles",
                    tint: .purple,
                    title: "settings.aiScanning.cloudTitle".localized,
                    body: "settings.aiScanning.cloudBody".localized,
                    active: hasKey
                )
            }

            Section {
                SecureField("settings.aiScanning.apiKeyPrompt".localized, text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: apiKey) { _, newValue in
                        persist(newValue)
                    }

                Link(destination: getKeyURL) {
                    Label("settings.aiScanning.getKey".localized, systemImage: "arrow.up.right.square")
                }

                if hasKey {
                    Button(role: .destructive) {
                        apiKey = ""
                    } label: {
                        Label("settings.aiScanning.removeKey".localized, systemImage: "trash")
                    }
                }
            } header: {
                Text("settings.aiScanning.keySection".localized)
            } footer: {
                Text("settings.aiScanning.getKeyFooter".localized)
            }
        }
        .navigationTitle("settings.aiScanning.title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = securityManager.getAPIKey() ?? ""
        }
    }

    private func persist(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            securityManager.deleteAPIKey()
        } else {
            _ = securityManager.saveAPIKey(trimmed)
        }
    }

    @ViewBuilder
    private func modeRow(icon: String, tint: Color, title: String, body: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ListIconView(systemImage: icon, color: tint)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.app(.subheadline, weight: .semibold))
                    if active {
                        Image(systemName: "checkmark.circle.fill")
                            .appFont(size: 13)
                            .foregroundStyle(tint)
                    }
                }
                Text(body)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

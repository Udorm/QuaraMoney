import SwiftUI

/// Shown on first sign-in when both the device and the cloud have existing data.
/// The user must choose which dataset wins before sync proceeds.
struct DataConflictResolutionView: View {
    @ObservedObject private var syncEngine = SyncEngine.shared

    /// Driven by the engine so the modal reflects the actual resolution progress
    /// (the wipe + sync runs on the engine, not in this view's lifetime).
    private var isResolving: Bool { syncEngine.conflictState == .resolving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .appFont(size: 52, weight: .light)
                            .foregroundStyle(.orange)

                        Text("sync.conflict.title".localized)
                            .appFont(size: 24, weight: .bold)

                        Text("sync.conflict.message".localized)
                            .appFont(size: 15)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Surfaced if a previous attempt failed (engine returns here).
                    if !isResolving, let error = syncEngine.lastError {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .appFont(size: 13)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Options
                    VStack(spacing: 12) {
                        ConflictOptionCard(
                            icon: "icloud.and.arrow.down",
                            iconColor: .blue,
                            title: "sync.conflict.useCloud.title".localized,
                            description: "sync.conflict.useCloud.message".localized,
                            isDestructiveAction: "sync.conflict.useCloud.warning".localized,
                            isDisabled: isResolving
                        ) {
                            Task { await syncEngine.resolveUseCloud() }
                        }

                        ConflictOptionCard(
                            icon: "iphone",
                            iconColor: .green,
                            title: "sync.conflict.keepLocal.title".localized,
                            description: "sync.conflict.keepLocal.message".localized,
                            isDestructiveAction: "sync.conflict.keepLocal.warning".localized,
                            isDisabled: isResolving
                        ) {
                            Task { await syncEngine.resolveKeepLocal() }
                        }
                    }

                    // Non-destructive escape hatch: defer the decision. Turns cloud
                    // sync off (app stays fully local) and leaves both datasets
                    // untouched; the user can re-enable sync in Settings later and
                    // will be asked again.
                    VStack(spacing: 6) {
                        Button("sync.conflict.decideLater".localized) {
                            syncEngine.deferConflictDecision()
                        }
                        .appFont(size: 16, weight: .semibold)
                        .disabled(isResolving)

                        Text("sync.conflict.decideLater.footer".localized)
                            .appFont(size: 12)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(isResolving ? 0.5 : 1)

                    if isResolving {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("sync.conflict.applying".localized)
                                .appFont(size: 13)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(24)
            }
            .navigationBarBackButtonHidden(true)
        }
        .interactiveDismissDisabled(true)
    }
}

private struct ConflictOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isDestructiveAction: String
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .appFont(size: 20, weight: .semibold)
                        .foregroundStyle(iconColor)
                        .frame(width: 28)

                    Text(title)
                        .appFont(size: 17, weight: .semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .appFont(size: 13, weight: .semibold)
                        .foregroundStyle(.tertiary)
                }

                Text(description)
                    .appFont(size: 14)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .appFont(size: 11)
                    Text(isDestructiveAction)
                        .appFont(size: 12)
                }
                .foregroundStyle(.red.opacity(0.8))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

#Preview {
    DataConflictResolutionView()
}

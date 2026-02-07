import SwiftUI

struct WalletFilterSheet: View {
    @Binding var showArchived: Bool
    @Binding var isPresented: Bool
    
    // Pending state
    @State private var pendingShowArchived: Bool
    
    init(showArchived: Binding<Bool>, isPresented: Binding<Bool>) {
        self._showArchived = showArchived
        self._isPresented = isPresented
        self._pendingShowArchived = State(initialValue: showArchived.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Active Option
                    FilterOptionRow(
                        title: L10n.Wallet.Status.active,
                        icon: "checkmark.circle",
                        isSelected: !pendingShowArchived
                    ) {
                        pendingShowArchived = false
                    }
                    
                    // Archived Option
                    FilterOptionRow(
                        title: L10n.Wallet.Status.archived,
                        icon: "archivebox",
                        isSelected: pendingShowArchived
                    ) {
                        pendingShowArchived = true
                    }
                } header: {
                    Text(L10n.Wallet.Status.title)
                        .font(.app(.caption))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Filter.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        showArchived = pendingShowArchived
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// Reusable row for consistent UI
private struct FilterOptionRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 24)
            
            Text(title)
                .font(.app(.body))
                .foregroundStyle(.primary)
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                action()
            }
        }
    }
}

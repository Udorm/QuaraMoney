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
                    SelectableRow(
                        title: L10n.Wallet.Status.active,
                        icon: "checkmark.circle",
                        isSelected: !pendingShowArchived
                    ) {
                        pendingShowArchived = false
                    }

                    // Archived Option
                    SelectableRow(
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
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showArchived = pendingShowArchived
                        isPresented = false
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}



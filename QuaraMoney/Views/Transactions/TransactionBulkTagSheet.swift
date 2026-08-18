import SwiftUI

enum TransactionBulkTagOperation: String, Identifiable {
    case add
    case remove

    var id: String { rawValue }

    var title: String {
        switch self {
        case .add: "transaction.bulk.addTag".localized
        case .remove: "transaction.bulk.removeTag".localized
        }
    }
}

/// Native form used to add one tag to, or remove one tag from, the current
/// transaction selection.
struct TransactionBulkTagSheet: View {
    @Environment(\.dismiss) private var dismiss

    let operation: TransactionBulkTagOperation
    let availableTags: [String]
    let onApply: (String) -> Void

    @State private var tagText = ""
    @State private var selectedTag: String?

    private var proposedTag: String? {
        switch operation {
        case .add:
            TransactionTagParser.normalizedTag(tagText)
        case .remove:
            selectedTag
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch operation {
                case .add:
                    Section {
                        TextField("transaction.bulk.tagPlaceholder".localized, text: $tagText)
                            .appFont(.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("transaction.bulk.tagHelp".localized)
                            .sectionFooter()
                    }

                case .remove:
                    Section {
                        if availableTags.isEmpty {
                            ContentUnavailableView(
                                "transaction.bulk.noTags".localized,
                                systemImage: "number"
                            )
                        } else {
                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    selectedTag = tag
                                } label: {
                                    HStack {
                                        Text("#\(tag)")
                                            .appFont(.body)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if selectedTag == tag {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } footer: {
                        Text("transaction.bulk.removeTagHelp".localized)
                            .sectionFooter()
                    }
                }
            }
            .navigationTitle(operation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        guard let proposedTag else { return }
                        onApply(proposedTag)
                        dismiss()
                    }
                    .disabled(proposedTag == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview("Add tag") {
    TransactionBulkTagSheet(operation: .add, availableTags: []) { _ in }
}

#Preview("Remove tag") {
    TransactionBulkTagSheet(operation: .remove, availableTags: ["food", "work", "កាហ្វេ"]) { _ in }
}

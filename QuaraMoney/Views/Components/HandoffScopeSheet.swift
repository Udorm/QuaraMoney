import SwiftUI

/// What a shared figure is made of, behind the badge on the amount.
///
/// Both halves of a split used to state this as a permanent line of grey type
/// under the header — "Total Bill: ฿4,900.00 (2 people)" on the way out, the same
/// sentence on the way in. It is the sort of thing you read once and then scroll
/// past forever, and it was standing between the header and the controls people
/// actually came to use. Behind a tap it can also say more than one line's worth.
///
/// Deliberately generic: the two screens have different things to explain, and a
/// sheet that took a title and a list of points was cheaper than two sheets that
/// would drift apart.
struct HandoffScopeSheet: View {
    struct Point: Identifiable {
        let icon: String
        let title: String
        let detail: String

        var id: String { title }
    }

    let title: String
    let points: [Point]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(points) { point in
                        row(point)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ point: Point) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(point.title)
                    .appFont(.subheadline, weight: .semibold)
                Text(point.detail)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: point.icon)
                .foregroundStyle(Color.accentColor)
        }
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        HandoffScopeSheet(
            title: "About this split",
            points: [
                .init(icon: "receipt", title: "Total bill", detail: "฿4,900.00, split 2 ways."),
                .init(icon: "paperplane", title: "They receive ฿2,450.00",
                      detail: "The link carries the amount, category, date and note — nothing else."),
                .init(icon: "pencil", title: "Your expense becomes ฿2,450.00",
                      detail: "Your logged ฿4,900.00 is reduced to your own share when you share."),
            ]
        )
    }
}

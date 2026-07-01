import SwiftUI

/// A transient bottom snackbar with a single **Undo** action that auto-dismisses
/// after `duration`. Bind `item` to any `Identifiable` payload: the toast shows
/// while it's non-nil, clears it when the timer elapses, and clears it after the
/// user taps Undo (the `onUndo` closure runs first).
///
/// Generic so any feature can reuse it; the recurring review/detail screens use
/// it to make post/skip reversible.
struct UndoToastModifier<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let duration: TimeInterval
    let message: (Item) -> String
    let onUndo: (Item) -> Void

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let item {
                    toast(item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: item?.id)
            .onChange(of: item?.id) { _, newID in
                dismissTask?.cancel()
                guard newID != nil else { return }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { return }
                    item = nil
                }
            }
    }

    private func toast(_ item: Item) -> some View {
        HStack(spacing: 12) {
            Text(message(item))
                .font(.app(.subheadline))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                dismissTask?.cancel()
                onUndo(item)
                self.item = nil
            } label: {
                Text("common.undo".localized)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

extension View {
    /// Presents an auto-dismissing Undo snackbar pinned to the bottom while
    /// `item` is non-nil. See ``UndoToastModifier``.
    func undoToast<Item: Identifiable>(
        _ item: Binding<Item?>,
        duration: TimeInterval = 4,
        message: @escaping (Item) -> String,
        onUndo: @escaping (Item) -> Void
    ) -> some View {
        modifier(UndoToastModifier(item: item, duration: duration, message: message, onUndo: onUndo))
    }
}

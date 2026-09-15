import SwiftUI
import SwiftData
import UIKit

/// Sheet for splitting an existing expense transaction and generating a shareable deep link.
///
/// The sending half of a user-to-user handoff, and it now opens with the same
/// header its receiving half does — `AppHandoffVisual` in its `.betweenUsers`
/// route, QuaraMoney's icon at both ends with "You" on the left. The screen used
/// to lead with a 44pt glass amount card of its own, which meant the two sides of
/// one transfer looked like two unrelated features; the figure is the same
/// figure, so it is now drawn the same way.
///
/// Below the header: the split settings section (split toggle + people stepper),
/// Apple native grouped detail rows, and native share sheet triggers.
struct SplitExpenseSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let transaction: Transaction
    let originalTotalAmount: Decimal

    @State private var isSplitInHalf: Bool = false
    @State private var peopleCount: Int = 2
    @State private var showScopeInfo = false

    /// How far the wash reaches: toolbar plus the handoff header, fading out
    /// before the first settings card.
    @ScaledMetric(relativeTo: .body) private var backdropHeight: CGFloat = 250

    init(transaction: Transaction) {
        self.transaction = transaction
        self.originalTotalAmount = transaction.amount
    }

    private var calculatedSplitAmount: Decimal {
        SplitExpenseService.calculateEqualSplit(
            totalAmount: originalTotalAmount,
            peopleCount: peopleCount,
            currencyCode: transaction.currencyCode
        )
    }

    private var sharedAmount: Decimal {
        isSplitInHalf ? calculatedSplitAmount : originalTotalAmount
    }

    private var payerShareAmount: Decimal {
        isSplitInHalf ? calculatedSplitAmount : originalTotalAmount
    }

    private var currentPayload: SharedExpensePayload {
        let locationPayload: SharedExpenseLocation?
        if let loc = transaction.location {
            locationPayload = SharedExpenseLocation(
                displayName: loc.displayName,
                fullAddress: loc.fullAddress,
                shortAddress: loc.shortAddress,
                latitude: loc.latitude,
                longitude: loc.longitude,
                locality: loc.locality,
                administrativeArea: loc.administrativeArea,
                countryCode: loc.countryCode
            )
        } else {
            locationPayload = nil
        }

        return SharedExpensePayload(
            version: 1,
            originalAmount: originalTotalAmount,
            splitAmount: sharedAmount,
            currencyCode: transaction.currencyCode,
            categoryKey: transaction.category?.canonicalKey,
            categoryName: transaction.category?.displayName,
            note: transaction.note,
            date: transaction.date,
            splitCount: isSplitInHalf ? peopleCount : 1,
            isCustomSplit: false,
            location: locationPayload
        )
    }

    private var generatedURL: URL? {
        SplitExpenseService.generateURL(for: currentPayload)
    }

    private var shareMessage: String {
        guard let url = generatedURL else { return "" }
        return SplitExpenseService.generateShareText(for: currentPayload, deepLink: url)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Handoff Header & Explanation Footer
                    handoffHeader

                    // MARK: - Split Settings (People Stepper + Update Toggle)
                    splitSettingsSection

                    // MARK: - Native Apple Detail Rows
                    detailSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Same treatment as both handoff screens: the wash reaches up under
            // the toolbar, so it goes behind the scroll view with the grouped
            // colour restored underneath it.
            .background(alignment: .top) {
                AppHandoffBackdrop(route: .betweenUsers)
                    .frame(height: backdropHeight)
                    .ignoresSafeArea(edges: .top)
            }
            .background { Color(.systemGroupedBackground).ignoresSafeArea() }
            .navigationTitle("split.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.Common.cancel)
                }

                // The action was a full-width button under the detail rows,
                // which put the screen's whole point below the fold as soon as
                // the expense had a location or a long note. In the bar it is
                // reachable from the moment the sheet opens.
                ToolbarItem(placement: .confirmationAction) {
                    Button("split.shareVia".localized) { shareAction() }
                        .buttonStyle(.borderedProminent)
                        .disabled(generatedURL == nil || sharedAmount <= 0)
                }
            }
            .sheet(isPresented: $showScopeInfo) {
                HandoffScopeSheet(title: "split.scope.title".localized, points: scopePoints)
            }
        }
    }

    // MARK: - Handoff Header & Footer Explanation

    /// The header. What the figure is made of sits behind the badge on it — see
    /// `scopePoints`.
    private var handoffHeader: some View {
        AppHandoffVisual(
            role: .source,
            route: .betweenUsers,
            amount: sharedAmount.formattedAmount(for: transaction.currencyCode),
            onInfo: { showScopeInfo = true }
        )
    }

    /// Three facts the sender might want and only one of which was ever on
    /// screen: where the number came from, what actually travels in the link, and
    /// what happens to their own logged expense.
    ///
    /// That last one is the reason this is worth a sheet. Splitting now rewrites
    /// the sender's own expense down to their share automatically, and that
    /// effect is invisible until after you have shared; stating both figures
    /// makes it checkable beforehand.
    private var scopePoints: [HandoffScopeSheet.Point] {
        let total = originalTotalAmount.formattedAmount(for: transaction.currencyCode)
        let share = sharedAmount.formattedAmount(for: transaction.currencyCode)

        return [
            .init(
                icon: "doc.text",
                title: "split.scope.bill".localized,
                detail: isSplitInHalf
                    ? "split.originalBillInfo".localized(with: total, peopleCount)
                    : "split.fullAmountInfo".localized(with: total)
            ),
            .init(
                icon: "paperplane",
                title: "split.scope.theyReceive".localized(with: share),
                detail: "split.scope.theyReceive.help".localized
            ),
            .init(
                icon: "pencil",
                title: willAdjustOwnExpense
                    ? "split.scope.yourExpenseChanges".localized(with: share)
                    : "split.scope.yourExpenseStays".localized(with: total),
                detail: willAdjustOwnExpense
                    ? "split.scope.yourExpenseChanges.help".localized(with: total)
                    : "split.scope.yourExpenseStays.help".localized
            ),
        ]
    }

    /// Mirrors `applyPayerAdjustmentIfNeeded`'s guard exactly, so the sheet can
    /// never promise something the commit path won't do.
    private var willAdjustOwnExpense: Bool {
        isSplitInHalf && payerShareAmount > 0
            && payerShareAmount != originalTotalAmount
    }

    // MARK: - Split Settings Section (Split Toggle + People Stepper)
    private var splitSettingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("split.title".localized)

            VStack(spacing: 0) {
                // Split in half toggle row
                Toggle(isOn: $isSplitInHalf.animation(.easeInOut(duration: 0.2))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("split.splitInHalf".localized)
                            .appFont(.subheadline, weight: .medium)
                        Text("split.splitInHalf.help".localized)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if isSplitInHalf {
                    Divider()
                        .padding(.leading, 16)

                    // Stepper Row
                    HStack {
                        Label {
                            Text("split.numberOfPeople".localized)
                                .appFont(.body)
                        } icon: {
                            Image(systemName: "person.2.fill")
                                .appFont(.body)
                                .foregroundStyle(.blue)
                        }

                        Spacer()

                        HStack(spacing: 14) {
                            Button {
                                if peopleCount > 2 {
                                    HapticManager.shared.impact(style: .light)
                                    peopleCount -= 1
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .appFont(.title3)
                                    .foregroundStyle(peopleCount > 2 ? .blue : .secondary.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .disabled(peopleCount <= 2)

                            Text("\(peopleCount)")
                                .appFont(.headline, weight: .semibold)
                                .frame(minWidth: 24)

                            Button {
                                if peopleCount < 20 {
                                    HapticManager.shared.impact(style: .light)
                                    peopleCount += 1
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .appFont(.title3)
                                    .foregroundStyle(peopleCount < 20 ? .blue : .secondary.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .disabled(peopleCount >= 20)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
        }
    }

    // MARK: - Detail Section (Native Apple Inset Grouped Rows)
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("common.details".localized)

            VStack(spacing: 0) {
                // Category
                if let category = transaction.category {
                    let iconColor = Color(hex: category.colorHex) ?? .orange
                    let iconName = category.icon.isEmpty ? "fork.knife" : category.icon
                    detailRow(
                        icon: iconName,
                        iconColor: iconColor,
                        title: "split.category".localized,
                        value: category.displayName
                    )
                    Divider().padding(.leading, 56)
                }

                // Date & Time
                detailRow(
                    icon: "calendar",
                    iconColor: .blue,
                    title: "split.date".localized,
                    value: transaction.date.appFormatted(date: .abbreviated, time: .shortened)
                )

                // Location (if present)
                if let loc = transaction.location {
                    Divider().padding(.leading, 56)
                    detailLocationRow(loc: loc)
                }

                // Note
                if let note = transaction.note, !note.isEmpty {
                    Divider().padding(.leading, 56)
                    detailRow(
                        icon: "note.text",
                        iconColor: .purple,
                        title: "split.note".localized,
                        value: note
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous))
        }
    }

    private func detailRow(
        icon: String,
        iconColor: Color,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .appFont(.body)
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func detailLocationRow(loc: TransactionLocation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "mappin.and.ellipse")
                    .appFont(.body)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("split.location".localized)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Text(loc.displayName ?? loc.shortAddress ?? loc.fullAddress ?? "split.location".localized)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = loc.fullAddress, secondary != loc.displayName {
                    Text(secondary)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .appFont(.footnote, weight: .medium)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
    }

    // MARK: - Native Share Sheet Trigger
    private func shareAction() {
        guard let url = generatedURL else { return }
        HapticManager.shared.impact(style: .medium)
        presentNativeShareSheet(items: [shareMessage, url]) { completed in
            if completed {
                HapticManager.shared.notification(type: .success)
                applyPayerAdjustmentIfNeeded()
                dismiss()
            }
        }
    }

    private func presentNativeShareSheet(items: [Any], completion: @escaping (Bool) -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var topController = rootVC
        while let presented = topController.presentedViewController {
            topController = presented
        }

        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            completion(completed)
        }

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topController.present(activityVC, animated: true)
    }

    // MARK: - Apply Adjustment to Payer Transaction
    private func applyPayerAdjustmentIfNeeded() {
        guard isSplitInHalf else { return }
        let newAmount = payerShareAmount
        guard newAmount > 0, newAmount != originalTotalAmount else { return }

        transaction.amount = newAmount
        transaction.updatedAt = Date()
        transaction.needsSync = true

        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

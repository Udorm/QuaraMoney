import SwiftUI
import SwiftData
import UIKit

/// Sheet for splitting an existing expense transaction and generating a shareable deep link.
/// Equal-split design matching ImportSharedExpenseView:
/// features the hero amount card with Liquid Glass, combined settings section (people stepper + update toggle),
/// Apple native grouped detail rows, and native share sheet triggers.
struct SplitExpenseSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let transaction: Transaction
    let originalTotalAmount: Decimal

    @State private var isSplitInHalf: Bool = true
    @State private var peopleCount: Int = 2
    @State private var updateOriginalTransaction: Bool = true

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
                    // MARK: - Amount Card & Explanation Footer
                    amountHeroCard

                    // MARK: - Split Settings (People Stepper + Update Toggle)
                    splitSettingsSection

                    // MARK: - Native Apple Detail Rows
                    detailSection

                    // MARK: - Primary Share Button
                    shareButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
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
            }
        }
    }

    // MARK: - Amount Hero Card & Footer Explanation
    private var amountHeroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            let shape = RoundedRectangle(cornerRadius: CornerRadius.hero, style: .continuous)
            let typeTint = ThemeManager.shared.expenseColor

            let cardContent = VStack(alignment: .center, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Text(String.currencySymbol(for: transaction.currencyCode))
                        .appFont(size: 28, weight: .semibold)
                        .foregroundStyle(Color.secondary)

                    Text(formatAmountValue(sharedAmount, currencyCode: transaction.currencyCode))
                        .appFont(size: 44, weight: .bold)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)

            Group {
                if reduceTransparency {
                    cardContent
                        .background(typeTint.opacity(0.15), in: shape)
                } else if #available(iOS 26.0, *) {
                    cardContent
                        .glassEffect(.regular.tint(typeTint.opacity(0.18)), in: shape)
                } else {
                    cardContent
                        .background(Color(.secondarySystemGroupedBackground), in: shape)
                }
            }
            .clipShape(shape)
            .contentShape(shape)

            // Native Apple form footer explanation text under the card (aligned with card content)
            if isSplitInHalf {
                Text(String(format: "split.originalBillInfo".localized, originalTotalAmount.formattedAmount(for: transaction.currencyCode), peopleCount))
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            } else {
                Text(String(format: "split.fullAmountInfo".localized, originalTotalAmount.formattedAmount(for: transaction.currencyCode)))
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            }
        }
    }

    private func formatAmountValue(_ value: Decimal, currencyCode: String) -> String {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if currencyCode.uppercased() == "KHR" {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: doubleValue)) ?? "\(value)"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: doubleValue)) ?? "\(value)"
        }
    }

    // MARK: - Split Settings Section (People Stepper + Update Toggle Combined)
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

                    Divider()
                        .padding(.leading, 16)

                    // Update original transaction toggle row
                    Toggle(isOn: $updateOriginalTransaction) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("split.updateOriginal".localized)
                                .appFont(.subheadline, weight: .medium)
                            Text("split.updateOriginal.help".localized)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
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

    // MARK: - Primary Action Button
    private var shareButton: some View {
        Button {
            shareAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("split.shareVia".localized)
            }
            .appFont(.headline, weight: .semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(generatedURL == nil || sharedAmount <= 0)
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
        guard isSplitInHalf, updateOriginalTransaction else { return }
        let newAmount = payerShareAmount
        guard newAmount > 0, newAmount != originalTotalAmount else { return }

        transaction.amount = newAmount
        transaction.updatedAt = Date()
        transaction.needsSync = true

        try? modelContext.save()
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
    }
}

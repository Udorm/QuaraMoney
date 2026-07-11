import SwiftUI

struct CurrencySelectionView: View {
    // Not `private`: a private stored property would make the synthesized
    // memberwise init private too, breaking CurrencySelectionView(selection:).
    var currencyManager = CurrencyManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    // Optional binding for selection mode. If nil, acts as Settings mode (updates preferredCurrencyCode).
    var selection: Binding<String>?

    // Optional currencies pinned to a "Quick Select" section at the top (e.g. the
    // app's primary USD/KHR pair). Empty = section hidden.
    var quickSelectCurrencies: [String] = []

    var filteredCurrencies: [String] {
        let all = currencyManager.availableCurrencies
        if searchText.isEmpty { return all }
        return all.filter { code in
            code.localizedCaseInsensitiveContains(searchText) ||
            currencyName(for: code).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if searchText.isEmpty && !quickSelectCurrencies.isEmpty {
                Section {
                    ForEach(quickSelectCurrencies, id: \.self) { code in
                        currencyRow(code)
                    }
                } header: {
                    sectionHeader("Quick Select")
                }
            }

            if searchText.isEmpty && !currencyManager.recentCurrencies.isEmpty {
                Section {
                    ForEach(currencyManager.recentCurrencies, id: \.self) { code in
                        currencyRow(code)
                    }
                } header: {
                    sectionHeader("Recent")
                }
            }

            Section {
                ForEach(filteredCurrencies, id: \.self) { code in
                    currencyRow(code)
                }
            } header: {
                sectionHeader(searchText.isEmpty ? "All Currencies" : "Search Results")
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Select Currency")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(L10n.Common.cancel)
            }
        }
        .safeAreaBar(edge: .bottom) {
            searchBar
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.app(.body))
                .foregroundStyle(.secondary)

            TextField("Search Currency", text: $searchText)
                .font(.app(.body))
                .autocorrectionDisabled()
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Common.cancel)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.app(.headline))
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    private func currencyRow(_ code: String) -> some View {
        Button {
            if let selection {
                selection.wrappedValue = code
                currencyManager.addToRecent(currencyCode: code)
            } else {
                currencyManager.preferredCurrencyCode = code
            }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(currencyDisplaySymbol(for: code))
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: 32, height: 32)
                    .background(iconColor(for: code))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(code)
                        .font(.app(.body))
                        .foregroundStyle(.primary)
                    Text(currencyName(for: code))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Double(100).formattedAmount(for: code))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)

                if isSelected(code) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 44 }
    }

    private func isSelected(_ code: String) -> Bool {
        if let selection { return selection.wrappedValue == code }
        return currencyManager.preferredCurrencyCode == code
    }

    private func currencyName(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    /// Short symbol for the icon circle — native symbol if ≤ 2 chars, else first 2 chars of code.
    private func currencyDisplaySymbol(for code: String) -> String {
        let symbol = String.currencySymbol(for: code)
        return symbol.count <= 2 ? symbol : String(code.prefix(2))
    }

    /// Deterministic color derived from the currency code's hash.
    private func iconColor(for code: String) -> Color {
        var hash = 5381
        for scalar in code.unicodeScalars {
            hash = (hash << 5) &+ hash &+ Int(scalar.value)
        }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.60, brightness: 0.72)
    }
}

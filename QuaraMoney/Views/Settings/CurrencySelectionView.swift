import SwiftUI

struct CurrencySelectionView: View {
    @ObservedObject var currencyManager = CurrencyManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    // Optional binding for selection mode. If nil, acts as Settings mode (updates preferredCurrencyCode).
    var selection: Binding<String>?
    
    var filteredCurrencies: [String] {
        let all = currencyManager.availableCurrencies
        if searchText.isEmpty {
            return all
        }
        return all.filter { code in
            code.localizedCaseInsensitiveContains(searchText) ||
            currencyName(for: code).localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        List {
            // Recent Section (only when not searching)
            if searchText.isEmpty && !currencyManager.recentCurrencies.isEmpty {
                Section("Recent") {
                    ForEach(currencyManager.recentCurrencies, id: \.self) { code in
                        currencyRow(code)
                    }
                }
            }
            
            // All Currencies
            Section(searchText.isEmpty ? "All Currencies" : "Search Results") {
                ForEach(filteredCurrencies, id: \.self) { code in
                    currencyRow(code)
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Currency")
        .navigationTitle("Select Currency")
    }
    
    private func currencyRow(_ code: String) -> some View {
        Button {
            if let selection = selection {
                selection.wrappedValue = code
                currencyManager.addToRecent(currencyCode: code)
            } else {
                currencyManager.preferredCurrencyCode = code
            }
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(code)
                        .font(.headline)
                    Text(currencyName(for: code))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Display symbol/example using formatter
                Text(Double(100).formatted(.currency(code: code).presentation(.narrow))) // Using .narrow usually gives symbol
                    .foregroundStyle(.secondary)
                    .font(.caption)
                
                if isSelected(code) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func isSelected(_ code: String) -> Bool {
        if let selection = selection {
            return selection.wrappedValue == code
        }
        return currencyManager.preferredCurrencyCode == code
    }
    
    private func currencyName(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }
}



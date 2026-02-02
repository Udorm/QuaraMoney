import SwiftUI

struct ColorPickerContainer: View {
    @Binding var selectedColorHex: String
    
    let columns = [GridItem(.adaptive(minimum: 44))]
    
    var body: some View {
        VStack {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AppTheme.colors, id: \.self) { colorHex in
                    ZStack {
                        Circle()
                            .fill(Color(hex: colorHex) ?? .gray)
                            .frame(width: 44, height: 44)
                        
                        if selectedColorHex == colorHex {
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.3), lineWidth: 4)
                                .frame(width: 52, height: 52)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedColorHex = colorHex
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct SymbolPickerContainer: View {
    @Binding var selectedIcon: String
    var selectedColorHex: String
    
    @State private var searchText = ""
    
    // Adjust grid items to ensure they fill space nicely
    let columns = [GridItem(.adaptive(minimum: 44), spacing: 16)]
    
    var filteredCategories: [(key: String, value: [String])] {
        if searchText.isEmpty {
            let orderedKeys = ["Finance", "Essentials", "Food & Drink", "Transport", "Services", "Leisure", "Education", "Tech", "Misc"]
            return orderedKeys.compactMap { key in
                guard let icons = AppTheme.icons[key] else { return nil }
                return (key, icons)
            }
        } else {
            let allIcons = AppTheme.icons.flatMap { $0.value }
            let filtered = allIcons.filter { $0.localizedCaseInsensitiveContains(searchText) }
            if filtered.isEmpty { return [] }
            return [("Search Results", filtered)]
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 18))
                
                TextField("Search Symbols", text: $searchText)
                    .font(.body)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                
                Image(systemName: "mic.fill")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .cornerRadius(10)
            .padding(16)
            
            // Symbols Grid
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(filteredCategories, id: \.key) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category.key)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(category.value, id: \.self) { icon in
                                ZStack {
                                    if selectedIcon == icon {
                                        Circle()
                                            .fill(Color(hex: selectedColorHex) ?? .blue)
                                    }
                                    
                                    Image(systemName: icon)
                                        .font(.system(size: 24))
                                        .foregroundColor(selectedIcon == icon ? .white : .gray)
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedIcon = icon
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

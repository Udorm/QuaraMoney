import SwiftUI

struct IconPickerView: View {
    @Binding var selectedIcon: String
    @Binding var selectedColorHex: String
    
    let columns = [GridItem(.adaptive(minimum: 50))]
    
    // Ordered keys for consistent display
    let categories = ["Finance", "Essentials", "Food & Drink", "Transport", "Services", "Leisure", "Education", "Tech", "Misc"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(categories, id: \.self) { category in
                    if let icons = AppTheme.icons[category] {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(getLocalizedCategory(category))
                                .font(.app(.headline))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(icons, id: \.self) { icon in
                                    ZStack {
                                        Circle()
                                            .fill(selectedIcon == icon ? (Color(hex: selectedColorHex) ?? .blue) : Color(.secondarySystemFill))
                                            .frame(width: 50, height: 50)
                                        
                                        Image(systemName: icon)
                                            .appFont(size: 22) // Icons are okay as system usually
                                            .foregroundColor(selectedIcon == icon ? .white : .primary)
                                    }
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedIcon = icon
                                        }
                                    }
                                    .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    private func getLocalizedCategory(_ category: String) -> String {
        switch category {
        case "Finance": return L10n.Category.financial
        case "Essentials": return L10n.Category.housing // Approximate mapping
        case "Food & Drink": return L10n.Category.foodAndDrink
        case "Transport": return L10n.Category.transportation
        case "Services": return L10n.Category.services
        case "Leisure": return L10n.Category.leisure
        case "Education": return L10n.Category.education
        case "Tech": return L10n.Category.tech
        case "Misc": return L10n.Category.others
        default: return category
        }
    }
}

#Preview {
    IconPickerView(selectedIcon: .constant("star"), selectedColorHex: .constant("#007AFF"))
}

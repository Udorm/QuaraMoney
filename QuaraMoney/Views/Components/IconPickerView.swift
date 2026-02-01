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
                            Text(category)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(icons, id: \.self) { icon in
                                    ZStack {
                                        Circle()
                                            .fill(selectedIcon == icon ? (Color(hex: selectedColorHex) ?? .blue) : Color(.secondarySystemFill))
                                            .frame(width: 50, height: 50)
                                        
                                        Image(systemName: icon)
                                            .font(.system(size: 22))
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
}

#Preview {
    IconPickerView(selectedIcon: .constant("star"), selectedColorHex: .constant("#007AFF"))
}

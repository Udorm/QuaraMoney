import SwiftUI

struct ColorPickerView: View {
    @Binding var selectedColorHex: String
    
    let columns = [GridItem(.adaptive(minimum: 44))]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(AppTheme.colors, id: \.self) { colorHex in
                    ZStack {
                        Circle()
                            .fill(Color(hex: colorHex) ?? .gray)
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        
                        // Selection Indicator
                        if selectedColorHex == colorHex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedColorHex = colorHex
                        }
                    }
                    .scaleEffect(selectedColorHex == colorHex ? 1.1 : 1.0)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ColorPickerView(selectedColorHex: .constant("#007AFF"))
}

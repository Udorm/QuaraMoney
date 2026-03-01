import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Form {
            Section("settings.incomeColor".localized) {
                HStack {
                    Text("settings.currentColor".localized)
                    Spacer()
                    Circle()
                        .fill(themeManager.incomeColor)
                        .frame(width: 24, height: 24)
                }
                
                ColorPickerView(selectedColorHex: $themeManager.incomeColorHex)
                    .frame(height: 150)
            }
            
            Section("settings.expenseColor".localized) {
                HStack {
                    Text("settings.currentColor".localized)
                    Spacer()
                    Circle()
                        .fill(themeManager.expenseColor)
                        .frame(width: 24, height: 24)
                }
                
                ColorPickerView(selectedColorHex: $themeManager.expenseColorHex)
                    .frame(height: 150)
            }
            
            Section {
                Button("settings.resetDefaults".localized) {
                    withAnimation {
                        themeManager.incomeColorHex = "#34C759" // Green
                        themeManager.expenseColorHex = "#FF3B30" // Red
                    }
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("settings.themeTitle".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
}

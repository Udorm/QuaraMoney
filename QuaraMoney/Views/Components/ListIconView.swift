import SwiftUI

struct ListIconView: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .appFont(size: 14, weight: .medium)
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: CornerRadius.icon, style: .continuous))
    }
}

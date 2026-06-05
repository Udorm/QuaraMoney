import SwiftUI

/// A reusable avatar component that displays a user's profile photo or
/// their initials over a gradient background when no photo is set.
struct ProfileAvatarView: View {
    let image: UIImage?
    let displayName: String
    let size: CGFloat
    var showEditBadge: Bool = false
    
    private var initials: String {
        let parts = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        
        if parts.isEmpty {
            return "?"
        }
        
        if parts.count == 1 {
            return String(parts[0].prefix(1)).uppercased()
        }
        
        let first = String(parts[0].prefix(1)).uppercased()
        let last = String(parts[parts.count - 1].prefix(1)).uppercased()
        return first + last
    }
    
    private var gradientColors: [Color] {
        // Generate a deterministic gradient based on the display name
        let hash = abs(displayName.hashValue)
        let hue1 = Double(hash % 360) / 360.0
        let hue2 = (hue1 + 0.15).truncatingRemainder(dividingBy: 1.0)
        return [
            Color(hue: hue1, saturation: 0.55, brightness: 0.85),
            Color(hue: hue2, saturation: 0.65, brightness: 0.70)
        ]
    }
    
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            
            // Subtle border ring
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size > 60 ? 3 : 1.5
                )
                .frame(width: size, height: size)
            
            // Edit badge
            if showEditBadge {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: size * 0.3, height: size * 0.3)
                            
                            Image(systemName: "camera.fill")
                                .font(.system(size: size * 0.12))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: size > 60 ? 8 : 3, y: size > 60 ? 4 : 2)
    }
}

#Preview("With Photo") {
    ProfileAvatarView(
        image: nil,
        displayName: "Dorm Udorm",
        size: 100,
        showEditBadge: true
    )
    .padding()
}

#Preview("No Photo") {
    VStack(spacing: 20) {
        ProfileAvatarView(image: nil, displayName: "Dorm Udorm", size: 100)
        ProfileAvatarView(image: nil, displayName: "Dorm", size: 60)
        ProfileAvatarView(image: nil, displayName: "", size: 44)
    }
    .padding()
}

import SwiftUI

struct OverlappingAvatarsView: View {
    let members: [EventMember]
    let limit: Int = 4
    let size: CGFloat = 32
    
    var body: some View {
        HStack(spacing: -size/3) {
            ForEach(members.prefix(limit)) { member in
                AvatarView(member: member, size: size)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            }
            
            if members.count > limit {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: size, height: size)
                    .overlay(
                        Text("+\(members.count - limit)")
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundStyle(.secondary)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }
}

private struct AvatarView: View {
    let member: EventMember
    let size: CGFloat
    
    var body: some View {
        if let data = member.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let icon = member.avatarIcon {
            Circle()
                .fill((Color(hex: member.colorHex) ?? .blue).opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(Color(hex: member.colorHex) ?? .blue)
                )
        } else {
            Circle()
                .fill(Color(.secondarySystemFill))
                .frame(width: size, height: size)
                .overlay(
                    Text(member.initials)
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundStyle(.secondary)
                )
        }
    }
}

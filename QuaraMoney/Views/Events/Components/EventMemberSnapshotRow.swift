import SwiftUI

struct EventMemberSnapshotRow: View {
    let members: [EventMember]
    let balances: [UUID: EventMemberLedgerBalance]
    let event: Event
    let onAddMember: () -> Void
    let onSelectMember: (EventMember) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Add Member Button (moved to left)
                Button(action: onAddMember) {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Color(.secondarySystemFill))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "plus")
                                    .appFont(size: 24)
                                    .foregroundStyle(.blue)
                            )
                        
                        Text(L10n.Common.add)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(members) { member in
                    MemberSnapshotItem(member: member)
                        .onTapGesture {
                            onSelectMember(member)
                        }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct MemberSnapshotItem: View {
    let member: EventMember
    
    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            if let data = member.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else if let icon = member.avatarIcon {
                Circle()
                    .fill((Color(hex: member.colorHex) ?? .blue).opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: icon)
                            .appFont(size: 28)
                            .foregroundStyle(Color(hex: member.colorHex) ?? .blue)
                    )
            } else {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(member.initials)
                            .appFont(.headline)
                            .foregroundStyle(.secondary)
                    )
            }
            
            Text(member.name)
                .appFont(.caption, weight: .medium)
                .lineLimit(1)
        }
        .frame(width: 70)
    }
}

extension EventMember {
    var initials: String {
        let components = name.components(separatedBy: .whitespaces)
        guard let first = components.first?.first else { return "?" }
        if components.count > 1, let last = components.last?.first {
            return "\(first)\(last)"
        }
        return String(first)
    }
}

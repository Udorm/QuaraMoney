import SwiftUI
import SwiftData

struct EventMemberListView: View {
    let event: Event
    let members: [EventMember]
    let balances: [UUID: EventMemberLedgerBalance]
    let onAddMember: () -> Void
    let onSelectMember: (EventMember) -> Void
    let onDeleteMember: (EventMember) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredMembers: [EventMember] {
        if searchText.isEmpty {
            return members
        }
        return members.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        List {
            ForEach(filteredMembers) { member in
                MemberRow(
                    member: member,
                    balance: balances[member.id],
                    currencyCode: event.currencyCode,
                    onSelect: { onSelectMember(member) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        onDeleteMember(member)
                    } label: {
                        Label(L10n.Common.delete, systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("\(event.title) \(L10n.EventDetail.members)")
//        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: L10n.EventAdditional.memberListSearch)
        .searchToolbarBehavior(.minimize)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    onAddMember()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

private struct MemberRow: View {
    let member: EventMember
    let balance: EventMemberLedgerBalance?
    let currencyCode: String
    let onSelect: () -> Void
    
    private var balanceText: String {
        guard let balance = balance else { return "" }
        let amount = MoneyMinorUnitConverter.fromMinorUnits(balance.netMinor, currencyCode: currencyCode)
        return amount.formattedAmount(for: currencyCode)
    }
    
    private var balanceColor: Color {
        guard let balance = balance else { return .secondary }
        if balance.netMinor > 0 { return .green }
        if balance.netMinor < 0 { return .red }
        return .secondary
    }
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 12) {
                // Avatar logic
                if let data = member.avatarData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else if let icon = member.avatarIcon {
                    Circle()
                        .fill((Color(hex: member.colorHex) ?? .blue).opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: icon)
                                .appFont(size: 20)
                                .foregroundStyle(Color(hex: member.colorHex) ?? .blue)
                        )
                } else {
                    Circle()
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(member.initials)
                                .font(.app(.subheadline, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.app(.body, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    if member.isLocalUser {
                        Text(L10n.EventAdditional.memberListYou)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if let balance = balance, balance.netMinor != 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(balanceText)
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(balanceColor)
                        
                        Text(balance.netMinor > 0 ? "receives" : "owes")
                            .appFont(size: 10)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .appFont(size: 14, weight: .semibold)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle()) // Makes entire row tappable
        }
        .buttonStyle(.plain)
    }
}

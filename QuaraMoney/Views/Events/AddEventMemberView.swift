import SwiftUI
import SwiftData

struct AddEventMemberView: View {
    let event: Event
    let memberToEdit: EventMember?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var avatarIcon: String = EventMember.defaultIcons.randomElement() ?? "face.smiling.fill"
    @State private var colorHex: String = EventMember.defaultColors.randomElement() ?? "#007AFF"
    @State private var avatarData: Data?
    @State private var isLocalUser: Bool = false
    @State private var errorMessage: String?
    @State private var showingIconPicker = false
    
    private var service: EventLedgerService {
        EventLedgerService(modelContext: modelContext)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if let avatarData, let uiImage = UIImage(data: avatarData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill((Color(hex: colorHex) ?? .blue).opacity(0.1))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: avatarIcon)
                                            .appFont(size: 40)
                                            .foregroundStyle(Color(hex: colorHex) ?? .blue)
                                    )
                            }
                            
                            Button(avatarData == nil ? L10n.EventMember.changeIcon : L10n.EventMember.removeImage) {
                                if avatarData != nil {
                                    avatarData = nil
                                } else {
                                    showingIconPicker = true
                                }
                            }
                            .font(.app(.caption, weight: .medium))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section(L10n.EventMember.details) {
                    TextField("Name", text: $name)
                    Toggle("This is me", isOn: $isLocalUser)
                }
                
                Section(L10n.EventMember.color) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(EventMember.defaultColors, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex) ?? .blue)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary.opacity(0.2), lineWidth: colorHex == hex ? 3 : 0)
                                    )
                                    .onTapGesture {
                                        withAnimation {
                                            colorHex = hex
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                }
                
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.app(.caption))
                    }
                }
            }
            .navigationTitle(memberToEdit == nil ? L10n.EventMember.addMember : L10n.EventMember.editMember)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingIconPicker) {
                MemberIconPickerView(selectedIcon: $avatarIcon, themeColor: Color(hex: colorHex) ?? .blue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.save) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let memberToEdit {
                    name = memberToEdit.name
                    avatarIcon = memberToEdit.avatarIcon ?? (EventMember.defaultIcons.randomElement() ?? "face.smiling.fill")
                    colorHex = memberToEdit.colorHex
                    avatarData = memberToEdit.avatarData
                    isLocalUser = memberToEdit.isLocalUser
                }
            }
        }
    }
    
    private func save() {
        do {
            if let memberToEdit {
                try service.updateMember(memberToEdit, name: name, avatarData: avatarData, avatarIcon: avatarIcon, colorHex: colorHex, isLocalUser: isLocalUser, isBudgetPool: memberToEdit.isBudgetPool)
            } else {
                _ = try service.addMember(to: event, name: name, avatarData: avatarData, avatarIcon: avatarIcon, colorHex: colorHex, isLocalUser: isLocalUser, isBudgetPool: false)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MemberIconPickerView: View {
    @Binding var selectedIcon: String
    let themeColor: Color
    @Environment(\.dismiss) private var dismiss
    
    let columns = [GridItem(.adaptive(minimum: 60))]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(EventMember.defaultIcons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            dismiss()
                        } label: {
                            Image(systemName: icon)
                                .appFont(size: 24)
                                .frame(width: 50, height: 50)
                                .background(selectedIcon == icon ? themeColor.opacity(0.1) : Color(.secondarySystemFill))
                                .foregroundStyle(selectedIcon == icon ? themeColor : .primary)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(selectedIcon == icon ? themeColor : Color.clear, lineWidth: 2)
                                )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Select Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

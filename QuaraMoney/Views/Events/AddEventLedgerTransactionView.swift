import SwiftUI
import SwiftData

struct AddEventLedgerTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel: AddEventLedgerTransactionViewModel
    
    @State private var isDateExpanded = false
    @State private var isTimeExpanded = false
    @State private var showKeyboard = true
    @State private var showAllCategories = false
    @State private var categorySearchText = ""
    @FocusState private var isNoteFocused: Bool
    
    // Grid layout for consistent member/category display
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 4)
    
    init(event: Event, transactionToEdit: EventLedgerTransaction? = nil) {
        self.viewModel = AddEventLedgerTransactionViewModel(event: event, transactionToEdit: transactionToEdit)
    }
    
    var body: some View {
        NavigationStack {
            
            List {
                // MARK: - Amount Display & Type (Fluid row)
                Section {
                    AmountDisplayView(
                        amount: viewModel.resolvedAmount,
                        currencyCode: $viewModel.selectedCurrencyCode,
                        expression: viewModel.expression,
                        isEditing: showKeyboard,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboard = true
                                isNoteFocused = false
                            }
                        }
                    )
                }
                .listRowBackground(
                    (viewModel.transactionKind == .expense 
                        ? ThemeManager.shared.expenseColor 
                        : ThemeManager.shared.incomeColor)
                    .opacity(0.15)
                )
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                // .listRowBackground(Color.clear)
                
                if viewModel.transactionKind == .expense {
                    // MARK: - Category
                    Section(L10n.Transaction.category) {
                        if viewModel.expenseCategories.isEmpty {
                            Text(L10n.EventTransaction.noCategories)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 10) {
                                ForEach(viewModel.frequentCategories) { category in
                                    CategoryGridItem(
                                        category: category,
                                        isSelected: viewModel.selectedCategoryId == category.id
                                    ) {
                                        withAnimation {
                                            viewModel.selectedCategoryId = category.id
                                        }
                                    }
                                }
                                
                                if viewModel.expenseCategories.count > 4 {
                                    Button {
                                        showAllCategories = true
                                    } label: {
                                        VStack(spacing: 4) {
                                            Image(systemName: "ellipsis.circle.fill")
                                                .font(.app(.title3))
                                                .foregroundColor(.secondary)
                                                .frame(width: 40, height: 40)
                                                .background(Color(.tertiarySystemGroupedBackground))
                                                .clipShape(Circle())
                                            
                                            Text("common.more".localized)
                                                .font(.app(.caption2))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    // MARK: - Payment & Splitting
                    Section(L10n.EventTransaction.paymentAndSplitting) {
                        Toggle("Use Event Wallet", isOn: $viewModel.useEventWallet.animation(.default))
                        
                        if !viewModel.useEventWallet {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.EventTransaction.selectPayer)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if viewModel.selectablePayers.isEmpty {
                                    Text(L10n.EventTransaction.noMembers)
                                        .foregroundStyle(.secondary)
                                } else {
                                    LazyVGrid(columns: gridColumns, spacing: 16) {
                                        ForEach(viewModel.selectablePayers) { member in
                                            MemberGridItem(
                                                member: member,
                                                isSelected: viewModel.selectedPayerMemberId == member.id
                                            ) {
                                                withAnimation {
                                                    viewModel.selectedPayerMemberId = member.id
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Split
                        Toggle("Split equally with everyone", isOn: Binding(
                            get: { !viewModel.isCustomSplit },
                            set: {
                                viewModel.isCustomSplit = !$0
                                if !viewModel.isCustomSplit {
                                    viewModel.selectAllParticipants()
                                }
                            }
                        ).animation(.default))
                        
                        if viewModel.isCustomSplit {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(L10n.EventTransaction.selectParticipants)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if viewModel.participantMembers.isEmpty {
                                    Text(L10n.EventTransaction.noMembers)
                                        .foregroundStyle(.secondary)
                                } else {
                                    LazyVGrid(columns: gridColumns, spacing: 16) {
                                        ForEach(viewModel.selectableMembers) { member in
                                            MemberGridItem(
                                                member: member,
                                                isSelected: viewModel.selectedParticipantIds.contains(member.id)
                                            ) {
                                                withAnimation {
                                                    viewModel.toggleParticipant(member.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    // MARK: - Contribution
                    Section(L10n.EventTransaction.contributor) {
                        if viewModel.selectablePayers.isEmpty {
                            Text(L10n.EventTransaction.noMembers)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(viewModel.selectablePayers) { member in
                                    MemberGridItem(
                                        member: member,
                                        isSelected: viewModel.selectedPayerMemberId == member.id
                                    ) {
                                        withAnimation {
                                            viewModel.selectedPayerMemberId = member.id
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        
                        Text("Contribution increases Event Wallet balance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // MARK: - Optional Fields
                Section {
                    // Date Selection Row
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isDateExpanded.toggle()
                            if isDateExpanded {
                                isTimeExpanded = false
                                showKeyboard = false
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text(L10n.Transaction.date)
                            Spacer()
                            Text(viewModel.date.appFormatted(date: .long, time: .omitted))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isDateExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if isDateExpanded {
                        DatePicker(
                            "",
                            selection: $viewModel.date,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Time Selection Row
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isTimeExpanded.toggle()
                            if isTimeExpanded {
                                isDateExpanded = false
                                showKeyboard = false
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text(L10n.TransactionAdditional.time)
                            Spacer()
                            Text(viewModel.date.appFormatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isTimeExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isTimeExpanded {
                        DatePicker(
                            "",
                            selection: $viewModel.date,
                            displayedComponents: [.hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Note Field
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        TextField("Note (optional)", text: $viewModel.note)
                            .focused($isNoteFocused)
                            .onTapGesture {
                                showKeyboard = false
                            }
                            .submitLabel(.done)
                    }
                }
                
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.insetGrouped)
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Entry Type", selection: $viewModel.transactionKind) {
                        Text(L10n.EventTransaction.tabExpense).tag(EventLedgerTransactionKind.expense)
                        Text(L10n.EventTransaction.tabContribution).tag(EventLedgerTransactionKind.contribution)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200) // Give it a fixed width to look good in the title area
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if viewModel.save() {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                if viewModel.transactionToEdit != nil {
                    showKeyboard = false
                }
            }
            .safeAreaInset(edge: .bottom) {
                 // Calculator keyboard overlay
                 if showKeyboard && !isNoteFocused {
                    CalculatorKeyboardView(
                        expression: $viewModel.expression,
                        evaluatedAmount: $viewModel.evaluatedAmount,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboard = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom))
                    .background(Color(.systemGroupedBackground)) // Match background
                 }
            }
            .sheet(isPresented: $showAllCategories) {
                categoryPickerSheet
            }
        }


    }
    
    // MARK: - Category Picker Sheet
    private var categoryPickerSheet: some View {
        NavigationStack {
            let displayCategories: [Category] = categorySearchText.isEmpty
                ? viewModel.expenseCategories
                : viewModel.expenseCategories.filter { $0.name.localizedCaseInsensitiveContains(categorySearchText) }
            
            List {
                ForEach(displayCategories) { category in
                    Button {
                        viewModel.selectedCategoryId = category.id
                        showAllCategories = false
                    } label: {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundColor(Color(hex: category.colorHex) ?? .gray)
                                .frame(width: 24)
                            Text(category.name)
                            Spacer()
                            if viewModel.selectedCategoryId == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle(L10n.TransactionAdditional.selectCategory)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $categorySearchText, prompt: L10n.TransactionAdditional.searchCategories)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { showAllCategories = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Reusable Member Grid Item
struct MemberGridItem: View {
    let member: EventMember
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2)
                            .frame(width: 46, height: 46)
                    }
                    
                    if let avatarData = member.avatarData, let uiImage = UIImage(data: avatarData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else if let icon = member.avatarIcon {
                        Image(systemName: icon)
                            .font(.title3)
                            .foregroundColor(isSelected ? .white : Color(hex: member.colorHex) ?? .gray)
                            .frame(width: 40, height: 40)
                            .background(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.title3)
                            .foregroundColor(isSelected ? .white : .gray)
                            .frame(width: 40, height: 40)
                            .background(isSelected ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                    
                    if member.isLocalUser {
                         Image(systemName: "person.circle.fill")
                            .appFont(size: 12)
                            .foregroundColor(.blue)
                            .background(Circle().fill(.white))
                            .offset(x: 14, y: 14)
                    }
                }
                
                Text(member.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }
}

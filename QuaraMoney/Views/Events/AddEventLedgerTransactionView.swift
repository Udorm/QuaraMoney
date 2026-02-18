import SwiftUI
import SwiftData

struct AddEventLedgerTransactionView: View {
    let event: Event
    let transactionToEdit: EventLedgerTransaction?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: [SortDescriptor(\EventMember.sortOrder), SortDescriptor(\EventMember.name)]) private var allMembers: [EventMember]
    @Query(sort: \Category.name) private var categories: [Category]
    
    @State private var expression: String = ""
    @State private var evaluatedAmount: Decimal = 0
    @State private var transactionKind: EventLedgerTransactionKind = .expense
    @State private var expensePaidSource: EventExpensePaidSource = .member
    @State private var selectedPayerMemberId: UUID?
    @State private var selectedParticipantIds: Set<UUID> = []
    @State private var selectedCategoryId: UUID?
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var errorMessage: String?
    
    @State private var showKeyboard = true
    @State private var showAllCategories = false
    @State private var categorySearchText = ""
    
    @FocusState private var isNoteFocused: Bool
    
    init(event: Event, transactionToEdit: EventLedgerTransaction? = nil) {
        self.event = event
        self.transactionToEdit = transactionToEdit
    }
    
    private var service: EventLedgerService {
        EventLedgerService(modelContext: modelContext)
    }
    
    private var members: [EventMember] {
        allMembers.filter { $0.event?.id == event.id }
    }
    
    private var budgetPoolMemberIds: Set<UUID> {
        Set(members.filter(\.isBudgetPool).map(\.id))
    }
    
    private var selectableMembers: [EventMember] {
        members.filter { member in
            if budgetPoolMemberIds.contains(member.id) { return false }
            return !member.isArchived || member.id == selectedPayerMemberId || selectedParticipantIds.contains(member.id)
        }
    }
    
    private var selectablePayers: [EventMember] {
        selectableMembers.filter { !$0.isArchived || $0.id == selectedPayerMemberId }
    }
    
    private var participantMembers: [EventMember] {
        selectableMembers.filter { !$0.isArchived || selectedParticipantIds.contains($0.id) }
    }
    
    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }
    
    private var selectedCategory: Category? {
        guard let selectedCategoryId else { return nil }
        return expenseCategories.first(where: { $0.id == selectedCategoryId })
    }
    
    private var frequentCategories: [Category] {
        let sorted = expenseCategories.sorted { cat1, cat2 in
            let count1 = cat1.transactions?.count ?? 0
            let count2 = cat2.transactions?.count ?? 0
            return count1 > count2
        }
        let count = expenseCategories.count
        let limit = count > 4 ? 3 : 4
        
        var items = Array(sorted.prefix(limit))
        if let selectedCategory, !items.contains(where: { $0.id == selectedCategory.id }) {
            if !items.isEmpty {
                items[items.count - 1] = selectedCategory
            } else {
                items.append(selectedCategory)
            }
        }
        return items
    }
    
    private var resolvedAmount: Decimal {
        if evaluatedAmount > 0 {
            return evaluatedAmount
        }
        return ExpressionEvaluator.evaluate(expression) ?? 0
    }
    
    private var orderedSelectedParticipantIds: [UUID] {
        participantMembers
            .filter { selectedParticipantIds.contains($0.id) }
            .map(\.id)
    }
    
    private var isValid: Bool {
        guard resolvedAmount > 0 else { return false }
        switch transactionKind {
        case .contribution:
            return selectedPayerMemberId != nil
        case .expense:
            guard !orderedSelectedParticipantIds.isEmpty else { return false }
            if !expenseCategories.isEmpty && selectedCategory == nil {
                return false
            }
            if expensePaidSource == .member {
                return selectedPayerMemberId != nil
            }
            return true
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissCalculator()
                    }
                
                ScrollView {
                    VStack(spacing: 16) {
                        AmountDisplayView(
                            amount: resolvedAmount,
                            currencyCode: .constant(event.currencyCode),
                            expression: expression,
                            isEditing: showKeyboard
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboard = true
                                isNoteFocused = false
                            }
                        }
                        
                        entryTypeSection
                        
                        if transactionKind == .expense {
                            categorySection
                            expenseSourceSection
                            participantsSection
                        } else {
                            contributionSection
                        }
                        
                        optionalFieldsSection
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.app(.caption))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                
                if showKeyboard && !isNoteFocused {
                    CalculatorKeyboardView(
                        expression: $expression,
                        evaluatedAmount: $evaluatedAmount,
                        onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showKeyboard = false
                            }
                        }
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .navigationTitle(transactionToEdit == nil ? "Add Event Entry" : "Edit Event Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                configureInitialState()
            }
            .sheet(isPresented: $showAllCategories) {
                categoryPickerSheet
            }
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var entryTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entry Type")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            
            Picker("Entry Type", selection: $transactionKind) {
                Text("Expense").tag(EventLedgerTransactionKind.expense)
                Text("Contribution").tag(EventLedgerTransactionKind.contribution)
            }
            .pickerStyle(.segmented)
            .onChange(of: transactionKind) { _, newValue in
                if newValue == .contribution {
                    expensePaidSource = .member
                    selectedParticipantIds.removeAll()
                    selectedCategoryId = nil
                    if selectedPayerMemberId == nil {
                        selectedPayerMemberId = selectablePayers.first?.id
                    }
                } else {
                    if selectedParticipantIds.isEmpty {
                        selectedParticipantIds = Set(participantMembers.filter { !$0.isArchived }.map(\.id))
                    }
                    if selectedPayerMemberId == nil {
                        selectedPayerMemberId = selectablePayers.first?.id
                    }
                    if selectedCategoryId == nil {
                        selectedCategoryId = expenseCategories.first?.id
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.Category.title)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            if expenseCategories.isEmpty {
                Text("No expense categories available")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(8)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(frequentCategories) { category in
                        CategoryGridItem(
                            category: category,
                            isSelected: selectedCategoryId == category.id
                        ) {
                            selectedCategoryId = category.id
                        }
                    }
                    
                    if expenseCategories.count > 4 {
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
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var expenseSourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paid Source")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            
            Picker("Paid Source", selection: $expensePaidSource) {
                Text("Member").tag(EventExpensePaidSource.member)
                Text("Event Wallet").tag(EventExpensePaidSource.eventWallet)
            }
            .pickerStyle(.segmented)
            
            if expensePaidSource == .member {
                payerSelectionContent
            } else {
                Text("This expense will be paid from the internal event wallet pool.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var contributionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contributor")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
            
            payerSelectionContent
            
            Text("Contribution increases Event Wallet balance and is not counted as trip cost.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var payerSelectionContent: some View {
        if selectablePayers.isEmpty {
            Text("Add members before creating event entries.")
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectablePayers) { member in
                        Button {
                            selectedPayerMemberId = member.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: member.isLocalUser ? "person.fill.checkmark" : "person.fill")
                                    .font(.app(.caption2))
                                Text(member.name)
                                    .font(.app(.subheadline, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background((selectedPayerMemberId == member.id) ? Color.accentColor : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle((selectedPayerMemberId == member.id) ? Color.white : Color.primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Split With")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                if !participantMembers.isEmpty {
                    Button("All") {
                        selectedParticipantIds = Set(participantMembers.filter { !$0.isArchived }.map(\.id))
                    }
                    .font(.app(.caption))
                    
                    Button("None") {
                        selectedParticipantIds.removeAll()
                    }
                    .font(.app(.caption))
                }
            }
            
            if participantMembers.isEmpty {
                Text("Add members before creating event expenses.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(participantMembers) { member in
                        Button {
                            toggleParticipant(member.id)
                        } label: {
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: member.isLocalUser ? "person.fill.checkmark" : "person.fill")
                                        .foregroundStyle(.secondary)
                                    Text(member.name)
                                        .foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: selectedParticipantIds.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedParticipantIds.contains(member.id) ? .blue : .secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var optionalFieldsSection: some View {
        VStack(spacing: 10) {
            DatePicker(
                selection: $date,
                displayedComponents: [.date, .hourAndMinute]
            ) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                        .frame(width: 24)
                    Text("Date")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
            
            HStack {
                Image(systemName: "note.text")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($isNoteFocused)
                    .onTapGesture {
                        showKeyboard = false
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
    }
    
    private var categoryPickerSheet: some View {
        let displayCategories = categorySearchText.isEmpty
            ? expenseCategories
            : expenseCategories.filter { $0.name.localizedCaseInsensitiveContains(categorySearchText) }
        
        return NavigationStack {
            List {
                ForEach(displayCategories) { category in
                    Button {
                        selectedCategoryId = category.id
                        showAllCategories = false
                    } label: {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundColor(Color(hex: category.colorHex) ?? .gray)
                                .frame(width: 24)
                            Text(category.name)
                            Spacer()
                            if selectedCategoryId == category.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $categorySearchText, prompt: "Search categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAllCategories = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func dismissCalculator() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let result = ExpressionEvaluator.evaluate(expression), result > 0 {
                evaluatedAmount = result
                expression = decimalExpression(result)
            }
            showKeyboard = false
            isNoteFocused = false
        }
    }
    
    private func decimalExpression(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let doubleValue = number.doubleValue
        if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", doubleValue)
        }
        return String(format: "%.2f", doubleValue)
    }
    
    private func toggleParticipant(_ memberId: UUID) {
        if selectedParticipantIds.contains(memberId) {
            selectedParticipantIds.remove(memberId)
        } else {
            selectedParticipantIds.insert(memberId)
        }
    }
    
    private func configureInitialState() {
        if let transactionToEdit {
            let amount = MoneyMinorUnitConverter.fromMinorUnits(transactionToEdit.amountMinor, currencyCode: event.currencyCode)
            evaluatedAmount = amount
            expression = decimalExpression(amount)
            transactionKind = transactionToEdit.kind
            
            let payerIsBudgetPool = transactionToEdit.paidByMemberId.map { budgetPoolMemberIds.contains($0) } ?? false
            if transactionToEdit.kind == .expense,
               (transactionToEdit.paidSource == .eventWallet || payerIsBudgetPool || transactionToEdit.paidByMemberId == nil) {
                expensePaidSource = .eventWallet
            } else {
                expensePaidSource = .member
            }
            
            selectedPayerMemberId = transactionToEdit.paidByMemberId
            selectedCategoryId = transactionToEdit.categoryId
            date = transactionToEdit.date
            note = transactionToEdit.note ?? ""
            
            if transactionToEdit.kind == .expense {
                do {
                    let ids = try service.participantIds(for: transactionToEdit, eventId: event.id)
                    selectedParticipantIds = Set(ids.filter { !budgetPoolMemberIds.contains($0) })
                } catch {
                    selectedParticipantIds = []
                }
            } else {
                selectedParticipantIds = []
            }
            showKeyboard = false
        } else {
            transactionKind = .expense
            expensePaidSource = .member
            selectedPayerMemberId = selectablePayers.first(where: { !$0.isArchived })?.id ?? selectablePayers.first?.id
            selectedParticipantIds = Set(participantMembers.filter { !$0.isArchived }.map(\.id))
            selectedCategoryId = expenseCategories.first?.id
            showKeyboard = true
        }
    }
    
    private func save() {
        let amount = resolvedAmount
        let title = derivedTitle()
        
        do {
            if let transactionToEdit {
                try service.updateTransaction(
                    transactionToEdit,
                    kind: transactionKind,
                    title: title,
                    amount: amount,
                    category: transactionKind == .expense ? selectedCategory : nil,
                    paidSource: transactionKind == .expense ? expensePaidSource : .member,
                    paidByMemberId: selectedPayerMemberId,
                    participantIds: transactionKind == .expense ? orderedSelectedParticipantIds : [],
                    date: date,
                    note: note
                )
            } else {
                _ = try service.addTransaction(
                    to: event,
                    kind: transactionKind,
                    title: title,
                    amount: amount,
                    category: transactionKind == .expense ? selectedCategory : nil,
                    paidSource: transactionKind == .expense ? expensePaidSource : .member,
                    paidByMemberId: selectedPayerMemberId,
                    participantIds: transactionKind == .expense ? orderedSelectedParticipantIds : [],
                    date: date,
                    note: note
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func derivedTitle() -> String {
        if transactionKind == .contribution {
            return "Contribution"
        }
        if let categoryName = selectedCategory?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !categoryName.isEmpty {
            return categoryName
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty {
            return trimmedNote
        }
        if let existing = transactionToEdit?.title, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        return "Event Expense"
    }
}

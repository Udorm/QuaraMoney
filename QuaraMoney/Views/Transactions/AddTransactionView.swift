import SwiftUI
import SwiftData

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: AddTransactionViewModel
    let isNewTransaction: Bool
    
    // Query data
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \Wallet.name) private var wallets: [Wallet]
    @Query(sort: \Event.startDate, order: .reverse) private var events: [Event]
    
    // UI State
    @State private var showDatePicker = false
    @State private var showEventPicker = false
    @State private var showAllCategories = false
    @State private var showAllWallets = false
    @State private var showKeyboard = true
    @State private var categorySearchText = ""
    @State private var walletSearchText = ""
    @State private var eventSearchText = ""
    @FocusState private var isNoteFieldFocused: Bool
    
    // Configuration
    private let maxQuickCategories = 3 // Show 3 categories + "More" to keep strictly to one row (4 items)
    private let maxQuickWallets = 4
    
    init(viewModel: AddTransactionViewModel, isNewTransaction: Bool = true) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.isNewTransaction = isNewTransaction
    }
    
    private var filteredCategories: [Category] {
        categories.filter { $0.type == viewModel.type }
    }
    
    /// Get frequently used categories (by transaction count) - limit to maxQuickCategories
    private var frequentCategories: [Category] {
        let sorted = filteredCategories.sorted { cat1, cat2 in
            let count1 = cat1.transactions?.count ?? 0
            let count2 = cat2.transactions?.count ?? 0
            return count1 > count2
        }
        let count = filteredCategories.count
        let limit = count > 4 ? 3 : 4 // If more than 4, show 3 + More. Else show all up to 4.
        
        var items = Array(sorted.prefix(limit))
        
        // If user selected a category that isn't in the top N, replace the last one to show selection
        if let selected = viewModel.selectedCategory, !items.contains(where: { $0.id == selected.id }) {
            if !items.isEmpty {
                items[items.count - 1] = selected
            } else {
                items.append(selected)
            }
        }
        
        return items
    }
    
    /// Get frequently used wallets - limit to maxQuickWallets
    private var frequentWallets: [Wallet] {
        let sorted = wallets.sorted { w1, w2 in
            // Could sort by transaction count or last used
            // For now just take first N
            return true
        }
        return Array(sorted.prefix(maxQuickWallets))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Tap to dismiss keyboard
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
                
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 16) {
                            // MARK: - Amount Display (Top Priority)
                            AmountDisplayView(
                                amount: viewModel.evaluatedAmount,
                                currencyCode: viewModel.selectedWallet?.currencyCode ?? "USD",
                                expression: viewModel.expression,
                                isEditing: showKeyboard
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showKeyboard = true
                                    isNoteFieldFocused = false
                                }
                            }
                        
                        // MARK: - Transaction Type Selector
                        transactionTypeSelector
                        
                        // MARK: - Wallet Selector
                        walletSelector
                        
                        // MARK: - Category/Destination Section
                        if viewModel.type == .transfer {
                            destinationWalletSection
                        } else {
                            categorySection
                        }
                        
                        // MARK: - Optional Fields (Collapsed)
                        optionalFieldsSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                
                // MARK: - Calculator Keyboard (Dismissible)
                if showKeyboard && !isNoteFieldFocused {
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
                }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit Transaction" : "New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isEditing ? "Save" : "Add") {
                        viewModel.saveTransaction()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.isValid)
                }
            }
            .onAppear {
                if viewModel.selectedWallet == nil, let first = wallets.first {
                    viewModel.selectedWallet = first
                }
                // Only show keyboard for new transactions
                showKeyboard = isNewTransaction
            }
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func dismissKeyboard() {
        withAnimation(.easeInOut(duration: 0.2)) {
            // Finalize calculation before dismissing
            if let result = ExpressionEvaluator.evaluate(viewModel.expression), result > 0 {
                viewModel.evaluatedAmount = result
                let doubleValue = NSDecimalNumber(decimal: result).doubleValue
                if doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                    viewModel.expression = String(format: "%.0f", doubleValue)
                } else {
                    viewModel.expression = String(format: "%.2f", doubleValue)
                }
            }
            showKeyboard = false
            isNoteFieldFocused = false
        }
    }
    
    // MARK: - Transaction Type Selector
    private var transactionTypeSelector: some View {
        Picker("Type", selection: $viewModel.type) {
            Text("Expense").tag(TransactionType.expense)
            Text("Income").tag(TransactionType.income)
            Text("Transfer").tag(TransactionType.transfer)
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.type) { _, newType in
            if newType != .transfer {
                viewModel.selectedCategory = nil
            }
        }
    }
    
    // MARK: - Wallet Selector
    private var walletSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("From Wallet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if wallets.count > maxQuickWallets {
                    Button("See All") {
                        showAllWallets = true
                    }
                    .font(.caption)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(frequentWallets) { wallet in
                        WalletChip(
                            wallet: wallet,
                            isSelected: viewModel.selectedWallet?.id == wallet.id
                        ) {
                            viewModel.selectedWallet = wallet
                            viewModel.updateExchangeRate()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAllWallets) {
            walletPickerSheet
        }
    }
    
    // MARK: - Wallet Picker Sheet
    private var walletPickerSheet: some View {
        let displayWallets = walletSearchText.isEmpty ? wallets : wallets.filter { $0.name.localizedCaseInsensitiveContains(walletSearchText) || $0.currencyCode.localizedCaseInsensitiveContains(walletSearchText) }
        
        return NavigationStack {
            List {
                ForEach(displayWallets) { wallet in
                    Button {
                        viewModel.selectedWallet = wallet
                        viewModel.updateExchangeRate()
                        showAllWallets = false
                    } label: {
                        HStack {
                            Image(systemName: wallet.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(wallet.name)
                                Text(wallet.currencyCode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedWallet?.id == wallet.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Select Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $walletSearchText, prompt: "Search wallets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAllWallets = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    // MARK: - Destination Wallet Section (for Transfers)
    @ViewBuilder
    private var destinationWalletSection: some View {
        let availableWallets = wallets.filter { $0.id != viewModel.selectedWallet?.id }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("To Wallet")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if availableWallets.isEmpty {
                Text("No other wallets available")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableWallets) { wallet in
                            WalletChip(
                                wallet: wallet,
                                isSelected: viewModel.destinationWallet?.id == wallet.id
                            ) {
                                viewModel.destinationWallet = wallet
                                viewModel.updateExchangeRate()
                            }
                        }
                    }
                }
            }
            
            // Exchange rate if different currencies
            if let source = viewModel.selectedWallet,
               let dest = viewModel.destinationWallet,
               source.currencyCode != dest.currencyCode {
                exchangeRateSection(source: source, destination: dest)
            }
        }
    }
    
    private func exchangeRateSection(source: Wallet, destination: Wallet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("1 \(source.currencyCode) =")
                    .foregroundStyle(.secondary)
                TextField("Rate", value: $viewModel.exchangeRate, format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Text(destination.currencyCode)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            
            let convertedAmount = viewModel.evaluatedAmount * Decimal(viewModel.exchangeRate)
            Text("≈ \(convertedAmount.formatted(.currency(code: destination.currencyCode)))")
                .font(.caption)
                .foregroundStyle(.blue)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Category Section (Smart Selection)
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            if filteredCategories.isEmpty {
                Text("No categories for \(viewModel.type.rawValue)")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            } else {
                // Show frequent categories in grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(frequentCategories) { category in
                        CategoryGridItem(
                            category: category,
                            isSelected: viewModel.selectedCategory?.id == category.id
                        ) {
                            viewModel.selectedCategory = category
                        }
                    }
                    
                    // Always show a "More" option if there are more than 4 categories
                    if filteredCategories.count > 4 {
                        Button {
                            showAllCategories = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Circle())
                                
                                Text("More")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showAllCategories) {
            categoryPickerSheet
        }
    }
    
    // MARK: - Category Picker Sheet
    private var categoryPickerSheet: some View {
        let displayCategories = categorySearchText.isEmpty ? filteredCategories : filteredCategories.filter { $0.name.localizedCaseInsensitiveContains(categorySearchText) }
        
        return NavigationStack {
            List {
                ForEach(displayCategories) { category in
                    Button {
                        viewModel.selectedCategory = category
                        showAllCategories = false
                    } label: {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundColor(Color(hex: category.colorHex) ?? .gray)
                                .frame(width: 24)
                            Text(category.name)
                            Spacer()
                            if viewModel.selectedCategory?.id == category.id {
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
    
    // MARK: - Optional Fields Section
    private var optionalFieldsSection: some View {
        VStack(spacing: 10) {
            // Date Row - using native DatePicker inline
            DatePicker(
                selection: $viewModel.date,
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
            
            // Note Field
            HStack {
                Image(systemName: "note.text")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                TextField("Add note...", text: $viewModel.note)
                    .focused($isNoteFieldFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
            
            // Event Row
            Button {
                showEventPicker.toggle()
            } label: {
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 24)
                    Text(viewModel.selectedEvent?.title ?? "Event (optional)")
                        .foregroundStyle(viewModel.selectedEvent != nil ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showEventPicker) {
                eventPickerSheet
            }
        }
    }
    
    // MARK: - Event Picker Sheet
    private var eventPickerSheet: some View {
        let displayEvents = eventSearchText.isEmpty ? events : events.filter { $0.title.localizedCaseInsensitiveContains(eventSearchText) }
        
        return NavigationStack {
            List {
                Button {
                    viewModel.selectedEvent = nil
                    showEventPicker = false
                } label: {
                    HStack {
                        Text("No Event")
                        Spacer()
                        if viewModel.selectedEvent == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                ForEach(displayEvents) { event in
                    Button {
                        viewModel.selectedEvent = event
                        showEventPicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(event.title)
                                Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectedEvent?.id == event.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Event")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $eventSearchText, prompt: "Search events")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEventPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Wallet Chip Component
struct WalletChip: View {
    let wallet: Wallet
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: wallet.icon)
                    .font(.caption2)
                Text(wallet.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Grid Item Component
struct CategoryGridItem: View {
    let category: Category
    let isSelected: Bool
    let action: () -> Void
    
    private var categoryColor: Color {
        Color(hex: category.colorHex) ?? .gray
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : categoryColor)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? categoryColor : categoryColor.opacity(0.15))
                    .clipShape(Circle())
                
                Text(category.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? categoryColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

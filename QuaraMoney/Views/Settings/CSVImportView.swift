import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CSVImportViewModel
    @State private var showFilePicker = false
    
    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: CSVImportViewModel(modelContext: modelContext))
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.currentStep {
                case .selectFile:
                    fileSelectionView
                case .mapColumns:
                    columnMappingView
                case .preview:
                    previewView
                case .importing:
                    importingView
                case .complete:
                    completionView
                }
            }
            .navigationTitle("Import Transactions")
            .navigationBarTitleDisplayMode(.inline)

            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        viewModel.processSelectedFile(url)
                    }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showError = true
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred.")
            }
        }
    }
    
    // MARK: - Step 1: File Selection
    private var fileSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "doc.text")
                .appFont(size: 64)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Import from CSV")
                    .font(.app(.title2, weight: .semibold))
                
                Text("Select a CSV file containing your transactions to import.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button {
                showFilePicker = true
            } label: {
                Label("Select CSV File", systemImage: "folder")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Info section
            VStack(alignment: .leading, spacing: 12) {
                Text("Supported Columns")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 16) {
                    ForEach(["Date", "Amount", "Category", "Note", "Wallet"], id: \.self) { col in
                        Text(col)
                            .font(.app(.caption2))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
            }
        }
    }
    
    // MARK: - Step 2: Column Mapping
    private var columnMappingView: some View {
        Form {
            Section {
                Text("Map your CSV columns to transaction fields.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            
            Section("Required Fields") {
                columnPicker(for: .date)
                columnPicker(for: .amount)
            }
            
            Section("Optional Fields") {
                columnPicker(for: .type)
                columnPicker(for: .category)
                columnPicker(for: .wallet)
                columnPicker(for: .note)
            }
            
            Section("Default Wallet") {
                Picker("Fallback Wallet", selection: $viewModel.selectedDefaultWallet) {
                    Text("None").tag(nil as Wallet?)
                    ForEach(viewModel.wallets) { wallet in
                        Text(wallet.name).tag(wallet as Wallet?)
                    }
                }
            }
            
            Section {
                HStack {
                    Text("Total Rows Detected")
                    Spacer()
                    Text("\(viewModel.totalDetectedRows)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Rows Analyzed (Preview)")
                    Spacer()
                    Text("\(viewModel.previewRawRows.count)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Valid Preview Rows")
                    Spacer()
                    Text("\(viewModel.validPreviewCount)")
                        .foregroundStyle(viewModel.validPreviewCount > 0 ? .green : .red)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                viewModel.proceedToPreview()
            } label: {
                Text("Preview Import")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canProceedToPreview ? Color.accentColor : Color(.systemGray))
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(!viewModel.canProceedToPreview)
            .padding()
            .background(.bar)
        }
    }
    
    private func columnPicker(for field: CSVField) -> some View {
        Picker(field.rawValue + (field.isRequired ? " *" : ""), selection: Binding(
            get: { viewModel.getColumnIndex(for: field) },
            set: { viewModel.updateMapping(field, to: $0) }
        )) {
            Text("Not Mapped").tag(nil as Int?)
            ForEach(Array(viewModel.headers.enumerated()), id: \.offset) { index, header in
                Text(header).tag(index as Int?)
            }
        }
    }
    
    // MARK: - Step 3: Preview
    private var previewView: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview based on first \(viewModel.previewRawRows.count) rows")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(viewModel.validPreviewCount)")
                                .font(.app(.title, weight: .bold))
                                .foregroundStyle(.green)
                            Text("Valid")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("\(viewModel.invalidPreviewCount)")
                                .font(.app(.title, weight: .bold))
                                .foregroundStyle(viewModel.invalidPreviewCount > 0 ? .red : .secondary)
                            Text("Skipped")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("Transactions Preview") {
                ForEach(viewModel.parsedPreviewRows) { row in
                    if row.isValid {
                        PreviewRowView(
                            row: row,
                            categories: viewModel.categories,
                            wallets: viewModel.wallets,
                            onCategoryChange: { viewModel.updateCategory(for: row.id, to: $0) },
                            onWalletChange: { viewModel.updateWallet(for: row.id, to: $0) }
                        )
                    }
                }
                
                if viewModel.totalDetectedRows > viewModel.parsedPreviewRows.count {
                    Text("... and \(viewModel.totalDetectedRows - viewModel.parsedPreviewRows.count) more rows not shown")
                        .foregroundStyle(.secondary)
                        .font(.app(.caption))
                        .listRowBackground(Color.clear)
                }
            }
            
            if viewModel.invalidPreviewCount > 0 {
                Section("Skipped Rows (Preview)") {
                    ForEach(viewModel.parsedPreviewRows) { row in
                        if !row.isValid {
                            HStack {
                                Text("Row \(row.rowIndex + 1)")
                                Spacer()
                                Text(row.errorMessage ?? "Invalid")
                                    .font(.app(.caption))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    viewModel.goBackToMapping()
                } label: {
                    Text("Adjust Mapping")
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.accentColor)
                }
                
                Button {
                    viewModel.executeImport()
                } label: {
                    Text("Import All \(viewModel.totalDetectedRows) Rows")
                        .font(.app(.headline))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.canImport ? Color.accentColor : Color(.systemGray))
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(!viewModel.canImport)
            }
            .padding()
            .background(.bar)
        }
    }
    
    // MARK: - Step 4: Importing
    private var importingView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Importing Transactions...")
                .font(.app(.headline))
            
            Text("Please wait. Large files may take a moment.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Step 5: Complete
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .appFont(size: 72)
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Import Complete!")
                    .font(.app(.title2, weight: .semibold))
                
                if let result = viewModel.importResult {
                    Text("\(result.successCount) transactions imported successfully")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    
                    if result.skippedCount > 0 {
                        Text("\(result.skippedCount) rows skipped")
                            .font(.app(.caption))
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.app(.headline))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding()
        }
        .padding()
    }
    
    // MARK: - Loading Overlay
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.primary)
                Text("Processing...")
                    .font(.app(.headline))
            }
            .padding(24)
            .background(.thickMaterial)
            .cornerRadius(12)
            .shadow(radius: 10)
        }
    }
}

// MARK: - Preview Row View
struct PreviewRowView: View {
    let row: CSVParsedRow
    let categories: [Category]
    let wallets: [Wallet]
    let onCategoryChange: (Category?) -> Void
    let onWalletChange: (Wallet?) -> Void
    
    @State private var showingCategoryPicker = false
    @State private var showingWalletPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date and Amount
            HStack {
                if let date = row.date {
                    Text(date, style: .date)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let amount = row.amount {
                    let amountDouble = NSDecimalNumber(decimal: amount).doubleValue
                    Text(amountDouble, format: .currency(code: "USD"))
                        .font(.app(.headline))
                        .foregroundStyle(row.type == .income ? .green : .red)
                }
            }
            
            // Note
            if let note = row.note, !note.isEmpty {
                Text(note)
                    .font(.app(.subheadline))
                    .lineLimit(1)
            }
            
            // Category & Wallet
            HStack(spacing: 12) {
                // Category Badge
                Button {
                    showingCategoryPicker = true
                } label: {
                    HStack(spacing: 4) {
                        if let cat = row.matchedCategory {
                            Image(systemName: cat.icon)
                                .font(.app(.caption2))
                            Text(cat.name)
                                .font(.app(.caption))
                        } else {
                            Image(systemName: "questionmark.circle")
                                .font(.app(.caption2))
                            Text(row.categoryName ?? "No Category")
                                .font(.app(.caption))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(row.matchedCategory != nil ? Color(.systemGray5) : Color.orange.opacity(0.2))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingCategoryPicker) {
                    CategoryPickerSheet(
                        categories: categories.filter { $0.type == (row.type ?? .expense) },
                        selected: row.matchedCategory,
                        onSelect: onCategoryChange
                    )
                }
                
                // Wallet Badge
                Button {
                    showingWalletPicker = true
                } label: {
                    HStack(spacing: 4) {
                        if let wallet = row.matchedWallet {
                            Image(systemName: wallet.icon)
                                .font(.app(.caption2))
                            Text(wallet.name)
                                .font(.app(.caption))
                        } else {
                            Image(systemName: "wallet.pass")
                                .font(.app(.caption2))
                            Text(row.walletName ?? "Default")
                                .font(.app(.caption2))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingWalletPicker) {
                    WalletPickerSheet(
                        wallets: wallets,
                        selected: row.matchedWallet,
                        onSelect: onWalletChange
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category Picker Sheet
struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]
    let selected: Category?
    let onSelect: (Category?) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(categories) { category in
                    Button {
                        onSelect(category)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundStyle(Color(hex: category.colorHex) ?? .primary)
                            Text(category.name)
                            Spacer()
                            if category.id == selected?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Wallet Picker Sheet
struct WalletPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let wallets: [Wallet]
    let selected: Wallet?
    let onSelect: (Wallet?) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(wallets) { wallet in
                    Button {
                        onSelect(wallet)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: wallet.icon)
                                .foregroundStyle(Color(hex: wallet.colorHex) ?? .primary)
                            Text(wallet.name)
                            Spacer()
                            if wallet.id == selected?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Select Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

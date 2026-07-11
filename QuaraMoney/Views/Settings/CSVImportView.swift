import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CSVImportViewModel
    @State private var showFilePicker = false
    
    init(modelContext: ModelContext) {
        self.viewModel = CSVImportViewModel(modelContext: modelContext)
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
            .navigationTitle("csv.title".localized)
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
            .alert(L10n.Common.error, isPresented: $viewModel.showError) {
                Button(L10n.Common.ok, role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "common.errorOccurred".localized)
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
                Text("settings.importCSV".localized)
                    .font(.app(.title2, weight: .semibold))
                
                Text("csv.selectFilePrompt".localized)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button {
                showFilePicker = true
            } label: {
                Label("csv.selectFile".localized, systemImage: "folder")
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
                Text("csv.supportedColumns".localized)
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    ForEach([CSVField.date, .amount, .category, .note, .wallet]) { col in
                        Text(col.displayName)
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
                Text("csv.mapPrompt".localized)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            
            Section("csv.requiredFields".localized) {
                columnPicker(for: .date)
                columnPicker(for: .amount)
            }
            
            Section("csv.optionalFields".localized) {
                columnPicker(for: .type)
                columnPicker(for: .category)
                columnPicker(for: .wallet)
                columnPicker(for: .note)
            }
            
            Section("csv.defaultWalletSection".localized) {
                Picker("csv.fallbackWallet".localized, selection: $viewModel.selectedDefaultWallet) {
                    Text("common.none".localized).tag(nil as Wallet?)
                    ForEach(viewModel.wallets) { wallet in
                        Text(wallet.name).tag(wallet as Wallet?)
                    }
                }
            }
            
            Section {
                HStack {
                    Text("csv.totalRows".localized)
                    Spacer()
                    Text("\(viewModel.totalDetectedRows)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("csv.rowsAnalyzed".localized)
                    Spacer()
                    Text("\(viewModel.previewRawRows.count)")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("csv.validPreviewRows".localized)
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
                Text("csv.previewImport".localized)
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
        Picker(field.displayName + (field.isRequired ? " *" : ""), selection: Binding(
            get: { viewModel.getColumnIndex(for: field) },
            set: { viewModel.updateMapping(field, to: $0) }
        )) {
            Text("csv.notMapped".localized).tag(nil as Int?)
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
                    Text("csv.previewBasedOn".localized(with: viewModel.previewRawRows.count))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(viewModel.validPreviewCount)")
                                .font(.app(.title, weight: .bold))
                                .foregroundStyle(.green)
                            Text("csv.valid".localized)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("\(viewModel.invalidPreviewCount)")
                                .font(.app(.title, weight: .bold))
                                .foregroundStyle(viewModel.invalidPreviewCount > 0 ? .red : .secondary)
                            Text("csv.skipped".localized)
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("csv.preview".localized) {
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
                    Text("csv.moreRowsNotShown".localized(with: viewModel.totalDetectedRows - viewModel.parsedPreviewRows.count))
                        .foregroundStyle(.secondary)
                        .font(.app(.caption))
                        .listRowBackground(Color.clear)
                }
            }
            
            if viewModel.invalidPreviewCount > 0 {
                Section("csv.skippedRowsPreview".localized) {
                    ForEach(viewModel.parsedPreviewRows) { row in
                        if !row.isValid {
                            HStack {
                                Text("csv.rowError".localized(with: row.rowIndex + 1))
                                Spacer()
                                Text(row.errorMessage ?? "common.invalid".localized)
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
                    Text("csv.adjustMapping".localized)
                    .font(.app(.subheadline))
                    .foregroundStyle(Color.accentColor)
                }
                
                Button {
                    viewModel.executeImport()
                } label: {
                    Text(String(format: "csv.importAll".localized, viewModel.totalDetectedRows))
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
            
            Text("csv.importing".localized)
                .font(.app(.headline))
            
            Text("csv.pleaseWait".localized)
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
                Text("csv.importComplete".localized)
                    .font(.app(.title2, weight: .semibold))
                
                if let result = viewModel.importResult {
                    Text(String(format: "csv.importedCount".localized, result.successCount))
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                    
                    if result.skippedCount > 0 {
                        Text(String(format: "csv.skippedCount".localized, result.skippedCount))
                            .font(.app(.caption))
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text(L10n.Common.done)
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
                Text("csv.processing".localized)
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
                    Text(date.appFormatted(date: .abbreviated))
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
                            Text(cat.displayName)
                                .font(.app(.caption))
                        } else {
                            Image(systemName: "questionmark.circle")
                                .font(.app(.caption2))
                            Text(row.categoryName ?? "csv.noCategory".localized)
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
                            Text(row.walletName ?? "csv.defaultWallet".localized)
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
                            Text(category.displayName)
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
            .navigationTitle(L10n.TransactionAdditional.selectCategory)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
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
            .navigationTitle("csv.selectWallet".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

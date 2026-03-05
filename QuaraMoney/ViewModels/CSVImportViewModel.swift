import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class CSVImportViewModel {
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let importService: CSVImportService
    
    // MARK: - Step Management
    enum ImportStep {
        case selectFile
        case mapColumns
        case preview
        case importing
        case complete
    }
    
    var currentStep: ImportStep = .selectFile
    var isLoading = false
    var errorMessage: String?
    var showError = false
    
    // MARK: - CSV Data
    var fileURL: URL?
    var headers: [String] = []
    // We only keep a limited number of rows for preview/mapping
    var previewRawRows: [[String]] = [] 
    var mapping = CSVColumnMapping()
    var parsedPreviewRows: [CSVParsedRow] = []
    var totalDetectedRows: Int = 0
    
    // MARK: - Existing Data
    var categories: [Category] = []
    var wallets: [Wallet] = []
    var selectedDefaultWallet: Wallet?
    
    // MARK: - Import Result
    var importResult: CSVImportResult?
    
    // MARK: - Learned Mappings
    var categoryMappings: [String: Category] = [:]
    var walletMappings: [String: Wallet] = [:]
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.importService = CSVImportService(modelContext: modelContext)
        loadExistingData()
    }
    
    // MARK: - Load Categories & Wallets
    private func loadExistingData() {
        do {
            categories = try importService.fetchCategories()
            wallets = try importService.fetchWallets()
            selectedDefaultWallet = wallets.first
        } catch {
            errorMessage = "Failed to load existing data: \(error.localizedDescription)"
            showError = true
        }
    }
    
    // MARK: - File Selection
    func processSelectedFile(_ url: URL) {
        // Security scoping for iOS
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Permission denied. Please try again."
            showError = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        fileURL = url
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let (parsedHeaders, parsedPreview, totalRows) = try await importService.parseHeadersAndPreview(from: url)
                
                guard !parsedHeaders.isEmpty else {
                    throw CSVImportError.invalidFormat
                }
                
                headers = parsedHeaders
                previewRawRows = parsedPreview
                totalDetectedRows = totalRows
                
                // Auto-detect column mapping
                mapping = importService.autoDetectMapping(from: headers)
                
                // Parse with initial mapping
                updateParsedPreviewRows()
                
                currentStep = .mapColumns
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }
    
    // MARK: - Update Mapping
    func updateMapping(_ field: CSVField, to columnIndex: Int?) {
        switch field {
        case .date: mapping.dateColumn = columnIndex
        case .amount: mapping.amountColumn = columnIndex
        case .type: mapping.typeColumn = columnIndex
        case .category: mapping.categoryColumn = columnIndex
        case .note: mapping.noteColumn = columnIndex
        case .wallet: mapping.walletColumn = columnIndex
        }
        
        updateParsedPreviewRows()
    }
    
    func getColumnIndex(for field: CSVField) -> Int? {
        switch field {
        case .date: return mapping.dateColumn
        case .amount: return mapping.amountColumn
        case .type: return mapping.typeColumn
        case .category: return mapping.categoryColumn
        case .note: return mapping.noteColumn
        case .wallet: return mapping.walletColumn
        }
    }
    
    // MARK: - Parse Rows
    private func updateParsedPreviewRows() {
        parsedPreviewRows = importService.parsePreviewRows(
            rawRows: previewRawRows,
            mapping: mapping,
            categories: categories,
            wallets: wallets
        )
    }
    
    // MARK: - Override Category for Row
    func updateCategory(for rowId: UUID, to category: Category?) {
        guard let index = parsedPreviewRows.firstIndex(where: { $0.id == rowId }) else { return }
        let row = parsedPreviewRows[index]
        
        // 1. Update this specific row (visual feedback)
        parsedPreviewRows[index].matchedCategory = category
        
        // 2. Identify the raw value to map
        if let rawName = row.categoryName {
            // 3. Update global mapping
            if let cat = category {
                categoryMappings[rawName] = cat
            } else {
                categoryMappings.removeValue(forKey: rawName)
            }
            
            // 4. Apply to all other preview rows with same raw name
            for i in 0..<parsedPreviewRows.count {
                if parsedPreviewRows[i].categoryName == rawName {
                    parsedPreviewRows[i].matchedCategory = category
                }
            }
        }
    }
    
    // MARK: - Override Wallet for Row
    func updateWallet(for rowId: UUID, to wallet: Wallet?) {
        guard let index = parsedPreviewRows.firstIndex(where: { $0.id == rowId }) else { return }
        let row = parsedPreviewRows[index]
        
        // 1. Update this specific row
        parsedPreviewRows[index].matchedWallet = wallet
        
        // 2. Identify raw value
        if let rawName = row.walletName {
            // 3. Update global mapping
            if let w = wallet {
                walletMappings[rawName] = w
            } else {
                walletMappings.removeValue(forKey: rawName)
            }
            
            // 4. Apply to all other preview rows
            for i in 0..<parsedPreviewRows.count {
                if parsedPreviewRows[i].walletName == rawName {
                    parsedPreviewRows[i].matchedWallet = wallet
                }
            }
        }
    }
    
    // MARK: - Navigation
    func proceedToPreview() {
        guard mapping.isValid else {
            errorMessage = "Please map the required columns (Date and Amount)."
            showError = true
            return
        }
        currentStep = .preview
    }
    
    func goBackToMapping() {
        currentStep = .mapColumns
    }
    
    // MARK: - Import
    func executeImport() {
        guard let url = fileURL else {
            errorMessage = "File lost. Please select file again."
            showError = true
            currentStep = .selectFile
            return
        }
        
        currentStep = .importing
        isLoading = true
        
        Task {
            do {
                // We pass current overrides only for potential learning/future use
                // but real import iterates file again
                
                let result = try await importService.importTransactions(
                    from: url,
                    mapping: mapping,
                    categories: categories,
                    wallets: wallets,
                    defaultWallet: selectedDefaultWallet,
                    defaultCurrency: CurrencyManager.shared.preferredCurrencyCode,
                    categoryMappings: categoryMappings,
                    walletMappings: walletMappings
                )
                
                importResult = result
                currentStep = .complete
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
                showError = true
                currentStep = .preview
            }
            isLoading = false
        }
    }
    
    // MARK: - Reset
    func reset() {
        currentStep = .selectFile
        fileURL = nil
        headers = []
        previewRawRows = []
        mapping = CSVColumnMapping()
        categoryMappings = [:]
        walletMappings = [:]
        parsedPreviewRows = []
        importResult = nil
        errorMessage = nil
    }
    
    // MARK: - Computed Properties
    var validPreviewCount: Int {
        parsedPreviewRows.filter { $0.isValid }.count
    }
    
    var invalidPreviewCount: Int {
        parsedPreviewRows.filter { !$0.isValid }.count
    }
    
    var canProceedToPreview: Bool {
        mapping.isValid && !previewRawRows.isEmpty
    }
    
    // We allow import if we see valid rows in preview OR we trust the mapping
    var canImport: Bool {
        validPreviewCount > 0
    }
}

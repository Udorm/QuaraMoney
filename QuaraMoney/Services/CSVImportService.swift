import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - CSV Column Mapping Configuration
enum CSVField: String, CaseIterable, Identifiable {
    case date = "Date"
    case amount = "Amount"
    case type = "Type"
    case category = "Category"
    case note = "Note"
    case wallet = "Wallet"
    
    var id: String { rawValue }
    
    var isRequired: Bool {
        switch self {
        case .date, .amount: return true
        case .type, .category, .note, .wallet: return false
        }
    }

    /// Localized label for pickers/chips. `rawValue` stays English — it's
    /// matched against CSV header names, not shown as-is in the UI.
    var displayName: String {
        switch self {
        case .date: return "csv.field.date".localized
        case .amount: return "csv.field.amount".localized
        case .type: return "csv.field.type".localized
        case .category: return "csv.field.category".localized
        case .note: return "csv.field.note".localized
        case .wallet: return "csv.field.wallet".localized
        }
    }
}

struct CSVColumnMapping {
    var dateColumn: Int?
    var amountColumn: Int?
    var typeColumn: Int?
    var categoryColumn: Int?
    var noteColumn: Int?
    var walletColumn: Int?
    
    var isValid: Bool {
        dateColumn != nil && amountColumn != nil
    }
}

// MARK: - Parsed CSV Row (for Preview)
struct CSVParsedRow: Identifiable {
    let id = UUID()
    let rowIndex: Int
    let rawValues: [String]
    
    // Parsed values
    var date: Date?
    var amount: Decimal?
    var type: TransactionType?
    var categoryName: String?
    var note: String?
    var walletName: String?
    
    // Matched entities (resolved later)
    var matchedCategory: Category?
    var matchedWallet: Wallet?
    
    // Validation
    var isValid: Bool {
        date != nil && amount != nil
    }
    
    var errorMessage: String? {
        if date == nil { return "Invalid date" }
        if amount == nil { return "Invalid amount" }
        return nil
    }
}

// MARK: - Import Result
struct CSVImportResult {
    let totalRows: Int
    let successCount: Int
    let skippedCount: Int
    let skippedReasons: [String]
}

struct CSVImportCategorySnapshot: Sendable {
    let persistentID: PersistentIdentifier
    let name: String
    let type: TransactionType

    init(_ category: Category) {
        persistentID = category.persistentModelID
        name = category.name
        type = category.type
    }
}

struct CSVImportWalletSnapshot: Sendable {
    let persistentID: PersistentIdentifier
    let name: String
    let currencyCode: String

    init(_ wallet: Wallet) {
        persistentID = wallet.persistentModelID
        name = wallet.name
        currencyCode = wallet.currencyCode
    }
}

// MARK: - CSV Import Service
@MainActor
final class CSVImportService {
    private let modelContext: ModelContext
    
    // Security: Maximum string lengths to prevent memory issues
    private static let maxNoteLength = 1000
    private static let maxCategoryNameLength = 100
    private static let maxWalletNameLength = 100
    
    // One formatter per supported import format, reused for every CSV row.
    private let dateFormatters: [DateFormatter]
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        dateFormatters = [
            "yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "dd/MM/yyyy",
            "MM-dd-yyyy", "dd-MM-yyyy", "yyyy-MM-dd HH:mm:ss",
            "MM/dd/yyyy HH:mm:ss"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }
    
    // MARK: - String Sanitization
    
    /// Sanitizes input strings by removing control characters and limiting length
    private func sanitizeString(_ string: String, maxLength: Int) -> String {
        // Remove control characters (except common whitespace)
        let allowedCharacters = CharacterSet.controlCharacters.inverted.union(.whitespaces)
        let sanitized = string.unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map { Character($0) }
        
        // Trim whitespace and limit length
        let trimmed = String(sanitized).trimmingCharacters(in: .whitespaces)
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength))
        }
        return trimmed
    }
    
    /// Sanitizes note field
    private func sanitizeNote(_ string: String?) -> String? {
        guard let string = string, !string.isEmpty else { return nil }
        let sanitized = sanitizeString(string, maxLength: Self.maxNoteLength)
        return sanitized.isEmpty ? nil : sanitized
    }
    
    /// Sanitizes category/wallet names
    private func sanitizeName(_ string: String) -> String {
        sanitizeString(string, maxLength: Self.maxCategoryNameLength)
    }
    
    // MARK: - Parse Headers & Preview
    func parseHeadersAndPreview(from url: URL, previewLimit: Int = 50) async throws -> (headers: [String], previewRows: [[String]], totalEstimatedRows: Int) {
        guard url.startAccessingSecurityScopedResource() else {
            throw CSVImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        var headers: [String] = []
        var previewRows: [[String]] = []
        var rowCount = 0
        
        for try await line in url.lines {
            if rowCount == 0 {
                headers = parseCSVLine(line)
            } else if rowCount <= previewLimit {
                previewRows.append(parseCSVLine(line))
            }
            rowCount += 1
        }
        
        guard !headers.isEmpty else {
            throw CSVImportError.invalidFormat
        }
        
        return (headers, previewRows, rowCount - 1) // -1 for header
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        result.append(currentField.trimmingCharacters(in: .whitespaces))
        
        return result
    }
    
    // MARK: - Auto-detect Column Mapping
    func autoDetectMapping(from headers: [String]) -> CSVColumnMapping {
        var mapping = CSVColumnMapping()
        let lowercaseHeaders = headers.map { $0.lowercased() }
        
        let mappings: [(CSVField, [String])] = [
            (.date, ["date", "time", "datetime"]),
            (.amount, ["amount", "value", "sum", "price"]),
            (.type, ["type", "kind", "direction"]),
            (.category, ["category", "cat", "group"]),
            (.note, ["note", "desc", "memo", "description"]),
            (.wallet, ["wallet", "account", "source"])
        ]
        
        for (field, keywords) in mappings {
            for (index, header) in lowercaseHeaders.enumerated() {
                if keywords.contains(where: { header.contains($0) }) {
                    switch field {
                    case .date: mapping.dateColumn = index
                    case .amount: mapping.amountColumn = index
                    case .type: mapping.typeColumn = index
                    case .category: mapping.categoryColumn = index
                    case .note: mapping.noteColumn = index
                    case .wallet: mapping.walletColumn = index
                    }
                    break
                }
            }
        }
        
        return mapping
    }
    
    // MARK: - Parse Rows for Preview
    func parsePreviewRows(
        rawRows: [[String]],
        mapping: CSVColumnMapping,
        categories: [Category],
        wallets: [Wallet]
    ) -> [CSVParsedRow] {
        return rawRows.enumerated().map { index, values in
            var row = CSVParsedRow(rowIndex: index, rawValues: values)
            
            if let col = mapping.dateColumn, col < values.count {
                row.date = parseDate(values[col])
            }
            
            if let col = mapping.amountColumn, col < values.count {
                row.amount = parseAmount(values[col])
            }
            
            if let col = mapping.typeColumn, col < values.count {
                row.type = parseType(values[col])
            } else if let amount = row.amount {
                row.type = amount < 0 ? .expense : .income
            }
            
            if let col = mapping.categoryColumn, col < values.count {
                let name = sanitizeName(values[col])
                row.categoryName = name
                row.matchedCategory = matchCategory(name: name, type: row.type ?? .expense, from: categories)
            }
            
            if let col = mapping.noteColumn, col < values.count {
                row.note = sanitizeNote(values[col])
            }
            
            if let col = mapping.walletColumn, col < values.count {
                let name = sanitizeName(values[col])
                row.walletName = name
                row.matchedWallet = matchWallet(name: name, from: wallets)
            }
            
            return row
        }
    }
    
    // MARK: - Date Parsing
    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
    
    // MARK: - Amount Parsing
    private func parseAmount(_ string: String) -> Decimal? {
        var cleaned = string
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            cleaned = "-" + cleaned.dropFirst().dropLast()
        }
        
        return Decimal(string: cleaned)
    }
    
    // MARK: - Type Parsing
    private func parseType(_ string: String) -> TransactionType? {
        let lower = string.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.contains("income") || lower == "in" || lower == "credit" || lower == "+" {
            return .income
        } else if lower.contains("expense") || lower == "out" || lower == "debit" || lower == "-" {
            return .expense
        } else if lower.contains("transfer") {
            return .transfer
        }
        return nil
    }
    
    // MARK: - Matching Helpers
    func matchCategory(name: String, type: TransactionType, from categories: [Category]) -> Category? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        let typeCategories = categories.filter { $0.type == type }
        
        if let exact = typeCategories.first(where: { $0.name.lowercased() == normalized }) {
            return exact
        }
        if let partial = typeCategories.first(where: { 
            let catName = $0.name.lowercased()
            return catName.contains(normalized) || normalized.contains(catName)
        }) {
            return partial
        }
        return nil // Prompt user to map unknown categories
    }
    
    func matchWallet(name: String, from wallets: [Wallet]) -> Wallet? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        
        if let exact = wallets.first(where: { $0.name.lowercased() == normalized }) {
            return exact
        }
        if let partial = wallets.first(where: { 
            let walletName = $0.name.lowercased()
            return walletName.contains(normalized) || normalized.contains(walletName)
        }) {
            return partial
        }
        return nil // Prompt user to select wallet if not found
    }
    
    // MARK: - Full Import (Streaming)
    func importTransactions(
        from url: URL,
        mapping: CSVColumnMapping,
        categories: [CSVImportCategorySnapshot],
        wallets: [CSVImportWalletSnapshot],
        defaultWallet: CSVImportWalletSnapshot?,
        defaultCurrency: String,

        categoryMappings: [String: CSVImportCategorySnapshot] = [:],
        walletMappings: [String: CSVImportWalletSnapshot] = [:]
    ) async throws -> CSVImportResult {
        guard url.startAccessingSecurityScopedResource() else {
            throw CSVImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        var successCount = 0
        var skippedCount = 0
        var skippedReasons: [String] = []
        var rowIndex = 0
        
        // Prepare overrides lookups by row index
        // We use the provided mappings (Value -> Entity) to apply manual overrides to all matching rows
        
        // Optimization: Cache matched categories/wallets by name to avoid O(N) lookup every row
        var categoryCache: [String: CSVImportCategorySnapshot] = [:]
        var walletCache: [String: CSVImportWalletSnapshot] = [:]
        
        let batchSize = 100
        var pendingBatchCount = 0
        
        for try await line in url.lines {
            if rowIndex == 0 {
                rowIndex += 1
                continue // Skip header
            }
            
            let values = parseCSVLine(line)
            
            let imported = importRow(
                values,
                mapping: mapping,
                categories: categories,
                wallets: wallets,
                defaultWallet: defaultWallet,
                defaultCurrency: defaultCurrency,
                categoryMappings: categoryMappings,
                walletMappings: walletMappings,
                categoryCache: &categoryCache,
                walletCache: &walletCache
            )

            guard imported else {
                skippedCount += 1
                if skippedReasons.count < 20 { // Limit errors
                    skippedReasons.append("Row \(rowIndex + 1): Invalid date or amount")
                }
                rowIndex += 1
                continue
            }
            
            successCount += 1
            pendingBatchCount += 1
            
            if pendingBatchCount >= batchSize {
                try modelContext.save()
                pendingBatchCount = 0
            }
            
            rowIndex += 1
        }
        
        if pendingBatchCount > 0 {
            try modelContext.save()
        }
        
        NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        
        return CSVImportResult(
            totalRows: rowIndex - 1,
            successCount: successCount,
            skippedCount: skippedCount,
            skippedReasons: skippedReasons
        )
    }

    /// Handles one already-read row synchronously. Any SwiftData objects
    /// resolved from persistent IDs are consumed before the stream suspends for
    /// its next line.
    private func importRow(
        _ values: [String],
        mapping: CSVColumnMapping,
        categories: [CSVImportCategorySnapshot],
        wallets: [CSVImportWalletSnapshot],
        defaultWallet: CSVImportWalletSnapshot?,
        defaultCurrency: String,
        categoryMappings: [String: CSVImportCategorySnapshot],
        walletMappings: [String: CSVImportWalletSnapshot],
        categoryCache: inout [String: CSVImportCategorySnapshot],
        walletCache: inout [String: CSVImportWalletSnapshot]
    ) -> Bool {
        let date = mapping.dateColumn.flatMap { $0 < values.count ? parseDate(values[$0]) : nil }
        let amount = mapping.amountColumn.flatMap { $0 < values.count ? parseAmount(values[$0]) : nil }
        guard let date, let amount else { return false }

        let parsedType = mapping.typeColumn.flatMap { $0 < values.count ? parseType(values[$0]) : nil }
        let type = parsedType ?? (amount < 0 ? .expense : .income)

        var categorySnapshot: CSVImportCategorySnapshot?
        if let column = mapping.categoryColumn, column < values.count {
            let name = values[column]
            let cacheKey = name + type.rawValue
            categorySnapshot = categoryMappings[name] ?? categoryCache[cacheKey]
            if categorySnapshot == nil {
                categorySnapshot = matchCategory(name: name, type: type, from: categories)
                categoryCache[cacheKey] = categorySnapshot
            }
        }

        var walletSnapshot: CSVImportWalletSnapshot?
        if let column = mapping.walletColumn, column < values.count {
            let name = values[column]
            walletSnapshot = walletMappings[name] ?? walletCache[name]
            if walletSnapshot == nil {
                walletSnapshot = matchWallet(name: name, from: wallets)
                walletCache[name] = walletSnapshot
            }
        }

        let resolvedWalletSnapshot = walletSnapshot ?? defaultWallet
        let note = mapping.noteColumn.flatMap { $0 < values.count ? sanitizeNote(values[$0]) : nil }
        let transaction = Transaction(
            amount: abs(amount),
            currencyCode: resolvedWalletSnapshot?.currencyCode ?? defaultCurrency,
            date: date,
            type: type
        )
        if let categorySnapshot {
            transaction.category = modelContext.model(for: categorySnapshot.persistentID) as? Category
        }
        if let resolvedWalletSnapshot {
            transaction.sourceWallet = modelContext.model(for: resolvedWalletSnapshot.persistentID) as? Wallet
        }
        transaction.note = note
        transaction.tags = TransactionTagParser.tags(in: note)
        modelContext.insert(transaction)
        return true
    }

    private func matchCategory(
        name: String,
        type: TransactionType,
        from categories: [CSVImportCategorySnapshot]
    ) -> CSVImportCategorySnapshot? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        let typed = categories.filter { $0.type == type }
        return typed.first { $0.name.lowercased() == normalized }
            ?? typed.first {
                let categoryName = $0.name.lowercased()
                return categoryName.contains(normalized) || normalized.contains(categoryName)
            }
    }

    private func matchWallet(
        name: String,
        from wallets: [CSVImportWalletSnapshot]
    ) -> CSVImportWalletSnapshot? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        return wallets.first { $0.name.lowercased() == normalized }
            ?? wallets.first {
                let walletName = $0.name.lowercased()
                return walletName.contains(normalized) || normalized.contains(walletName)
            }
    }
    
    // MARK: - Fetch Helpers
    func fetchCategories() throws -> [Category] {
        let descriptor = FetchDescriptor<Category>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor)
    }
    
    func fetchWallets() throws -> [Wallet] {
        let descriptor = FetchDescriptor<Wallet>(
            predicate: #Predicate { !$0.isArchived && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Errors
enum CSVImportError: LocalizedError {
    case accessDenied
    case invalidFormat
    case noValidRows
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Cannot access the selected file. Please try again."
        case .invalidFormat:
            return "The file format is not valid CSV."
        case .noValidRows:
            return "No valid transactions found in the file."
        }
    }
}

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

// MARK: - CSV Import Service
@MainActor
final class CSVImportService {
    private let modelContext: ModelContext
    
    // Security: Maximum string lengths to prevent memory issues
    private static let maxNoteLength = 1000
    private static let maxCategoryNameLength = 100
    private static let maxWalletNameLength = 100
    
    // Supported date formats (ordered by priority)
    private let dateFormats = [
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "MM/dd/yyyy",
        "dd/MM/yyyy",
        "MM-dd-yyyy",
        "dd-MM-yyyy",
        "yyyy-MM-dd HH:mm:ss",
        "MM/dd/yyyy HH:mm:ss"
    ]
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        for format in dateFormats {
            formatter.dateFormat = format
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
        categories: [Category],
        wallets: [Wallet],
        defaultWallet: Wallet?,
        defaultCurrency: String,

        categoryMappings: [String: Category] = [:],
        walletMappings: [String: Wallet] = [:]
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
        var categoryCache: [String: Category] = [:]
        var walletCache: [String: Wallet] = [:]
        
        let batchSize = 100
        var batchBuffer: [Transaction] = []
        
        for try await line in url.lines {
            if rowIndex == 0 {
                rowIndex += 1
                continue // Skip header
            }
            
            let values = parseCSVLine(line)
            
            // Parse fields
            var date: Date?
            if let col = mapping.dateColumn, col < values.count {
                date = parseDate(values[col])
            }
            
            var amount: Decimal?
            if let col = mapping.amountColumn, col < values.count {
                amount = parseAmount(values[col])
            }
            
            guard let validDate = date, let validAmount = amount else {
                skippedCount += 1
                if skippedReasons.count < 20 { // Limit errors
                    skippedReasons.append("Row \(rowIndex + 1): Invalid date or amount")
                }
                rowIndex += 1
                continue
            }
            
            var type: TransactionType?
            if let col = mapping.typeColumn, col < values.count {
                type = parseType(values[col])
            } else {
                type = validAmount < 0 ? .expense : .income
            }
            let finalType = type ?? (validAmount < 0 ? .expense : .income)
            
            // Resolve Category
            var category: Category?
            if let col = mapping.categoryColumn, col < values.count {
                let name = values[col]
                // 1. Check explicit matching (manual override)
                if let explicit = categoryMappings[name] {
                    category = explicit
                } else if let cached = categoryCache[name + finalType.rawValue] {
                    category = cached
                } else {
                    category = matchCategory(name: name, type: finalType, from: categories)
                    if let found = category {
                        categoryCache[name + finalType.rawValue] = found
                    }
                }
            }
            
            // Resolve Wallet
            var wallet: Wallet?
            if let col = mapping.walletColumn, col < values.count {
                let name = values[col]
                // 1. Check explicit matching (manual override)
                if let explicit = walletMappings[name] {
                    wallet = explicit
                } else if let cached = walletCache[name] {
                    wallet = cached
                } else {
                    wallet = matchWallet(name: name, from: wallets)
                    if let found = wallet {
                        walletCache[name] = found
                    }
                }
            }
            
            // Note (sanitized)
            var note: String?
            if let col = mapping.noteColumn, col < values.count {
                note = sanitizeNote(values[col])
            }
            
            // Create Transaction
            let transaction = Transaction(
                amount: abs(validAmount),
                currencyCode: wallet?.currencyCode ?? defaultWallet?.currencyCode ?? defaultCurrency,
                date: validDate,
                type: finalType
            )
            transaction.category = category
            transaction.sourceWallet = wallet ?? defaultWallet
            transaction.note = note
            
            modelContext.insert(transaction)
            batchBuffer.append(transaction)
            successCount += 1
            
            if batchBuffer.count >= batchSize {
                try modelContext.save()
                batchBuffer.removeAll()
            }
            
            rowIndex += 1
        }
        
        if !batchBuffer.isEmpty {
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
    
    // MARK: - Fetch Helpers
    func fetchCategories() throws -> [Category] {
        let descriptor = FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)])
        return try modelContext.fetch(descriptor)
    }
    
    func fetchWallets() throws -> [Wallet] {
        let descriptor = FetchDescriptor<Wallet>(
            predicate: #Predicate { !$0.isArchived },
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

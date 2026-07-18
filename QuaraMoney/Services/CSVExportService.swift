
import Foundation
import SwiftData
import SwiftUI

class CSVExportService {
    static let shared = CSVExportService()
    
    private init() {}
    
    /// Generates a CSV file from the provided transactions
    /// - Returns: URL to the temporary CSV file
    /// Neutralizes spreadsheet formula injection: a cell starting with =, +, -, @
    /// (or a tab/CR) is executed as a formula by Excel/Numbers when the export is
    /// opened. Prefix with a single quote so it renders as text.
    private func sanitizedCell(_ value: String) -> String {
        guard let first = value.first, "=+-@\t\r".contains(first) else { return value }
        return "'" + value
    }

    /// Removes exports from previous runs so financial data doesn't accumulate
    /// in tmp after the share sheet is done with the file.
    private func cleanupStaleExports() {
        let tmp = FileManager.default.temporaryDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent.hasPrefix("QuaraMoney_Export_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    func generateCSV(transactions: [Transaction]) -> URL? {
        cleanupStaleExports()
        let fileName = "QuaraMoney_Export_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).csv"
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        // Quote all fields to be safe against commas in content
        let csvHeader = "\"Date\",\"Amount\",\"Currency\",\"Category\",\"Type\",\"Note\",\"Wallet\"\n"
        var csvText = csvHeader
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss" // ISO-like format with time
        
        for transaction in transactions {
            let date = dateFormatter.string(from: transaction.date)
            let amount = transaction.amount.formatted(.number.grouping(.never))
            let currency = transaction.currencyCode
            let category = sanitizedCell(transaction.category?.name ?? "Uncategorized")
            let type = transaction.type.title
            let note = sanitizedCell((transaction.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")) // Escape quotes
            let wallet = sanitizedCell(transaction.sourceWallet?.name ?? "Unknown")
            
            // Wrap in quotes
            let row = "\"\(date)\",\"\(amount)\",\"\(currency)\",\"\(category)\",\"\(type)\",\"\(note)\",\"\(wallet)\"\n"
            csvText.append(row)
        }
        
        do {
            try csvText.write(to: path, atomically: true, encoding: .utf8)
            // Encrypt at rest while it sits in tmp awaiting the share sheet.
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: path.path
            )
            return path
        } catch {
            #if DEBUG
            print("Failed to create CSV file: \(error)")
            #endif
            ErrorService.shared.handleError(error, context: "csvGenerate")
            return nil
        }
    }
    
    @MainActor
    func exportData(modelContext: ModelContext, walletIDs: Set<UUID> = [], startDate: Date? = nil, endDate: Date? = nil) -> URL? {
        do {
            let descriptor: FetchDescriptor<Transaction>
            switch (startDate, endDate) {
            case let (start?, end?):
                descriptor = FetchDescriptor(
                    predicate: #Predicate<Transaction> {
                        $0.deletedAt == nil && $0.event == nil &&
                        $0.date >= start && $0.date <= end
                    },
                    sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
                )
            case let (start?, nil):
                descriptor = FetchDescriptor(
                    predicate: #Predicate<Transaction> {
                        $0.deletedAt == nil && $0.event == nil && $0.date >= start
                    },
                    sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
                )
            case let (nil, end?):
                descriptor = FetchDescriptor(
                    predicate: #Predicate<Transaction> {
                        $0.deletedAt == nil && $0.event == nil && $0.date <= end
                    },
                    sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
                )
            case (nil, nil):
                descriptor = FetchDescriptor(
                    predicate: #Predicate<Transaction> {
                        $0.deletedAt == nil && $0.event == nil
                    },
                    sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
                )
            }

            var filtered = try modelContext.fetch(descriptor)
            
            // Filter by Wallet
            if !walletIDs.isEmpty {
                filtered = filtered.filter { txn in
                    guard let wallet = txn.sourceWallet else { return false }
                    return walletIDs.contains(wallet.id)
                }
            }
            
            return generateCSV(transactions: filtered)
        } catch {
            #if DEBUG
            print("Failed to fetch transactions for export: \(error)")
            #endif
            ErrorService.shared.handleError(error, context: "csvExport")
            return nil
        }
    }
}

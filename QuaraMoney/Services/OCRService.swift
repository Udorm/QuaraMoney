
import Foundation
import Vision
import UIKit

enum OCRServiceError: Error {
    case imageProcessingFailed
    case textRecognitionFailed
    case noTextFound
}

struct ParsedReceiptData {
    var amount: Decimal?
    var date: Date?
    var merchantName: String?
    var currencyCode: String?
    var suggestedWalletName: String?
}

class OCRService {
    static let shared = OCRService()
    
    private init() {}
    
    /// Scans an image for text and attempts to parse receipt data.
    /// Uses Gemini Flash if API Key is available, otherwise falls back to Apple Vision.
    func scanReceipt(from image: UIImage, availableWallets: [String]? = nil) async throws -> ParsedReceiptData {
        // 1. Try Gemini if API Key exists
        if let apiKey = SecurityManager.shared.getAPIKey(), !apiKey.isEmpty {
            do {
                print("Attempting Gemini OCR...")
                return try await scanWithGemini(image: image, apiKey: apiKey, availableWallets: availableWallets)
            } catch {
                print("Gemini OCR failed, falling back to Vision: \(error)")
                // Fallthrough to Vision
            }
        }
        
        // 2. Apple Vision Fallback
        guard let cgImage = image.cgImage else {
            throw OCRServiceError.imageProcessingFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(throwing: OCRServiceError.textRecognitionFailed)
                    return
                }
                
                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }
                
                if recognizedStrings.isEmpty {
                    continuation.resume(throwing: OCRServiceError.noTextFound)
                    return
                }
                
                let parsedData = self.parseReceiptText(recognizedStrings)
                continuation.resume(returning: parsedData)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseReceiptText(_ lines: [String]) -> ParsedReceiptData {
        var data = ParsedReceiptData()
        
        // 1. Parse Amount
        // Look for the largest number that looks like a total price
        // Exclude common non-total numbers (like phone numbers, tax IDs if distinguishable)
        // Heuristic: "Total", "Amount", "Balance Due" often precede the real amount.
        data.amount = extractAmount(from: lines)
        
        // 2. Parse Date
        data.date = extractDate(from: lines)
        
        // 3. Parse Merchant
        // Usually the first line or first significant line
        data.merchantName = extractMerchant(from: lines)
        
        return data
    }
    
    private func extractAmount(from lines: [String]) -> Decimal? {
        // Regex for stricter currency: 
        // - Optional currency symbol ($, €, etc)
        // - Numbers with optional thousand separators (,)
        // - MUST have a decimal point followed by exactly 2 digits (e.g. .00, .99)
        // This avoids picking up years (2024), phone numbers, or zip codes.
        let currencyPattern = #"[0-9,]+\.[0-9]{2}"#
        
        var maxAmount: Decimal? = nil
        var totalLineAmount: Decimal? = nil
        
        // Keywords that strongly indicate the total line
        let totalKeywords = ["total", "amount due", "balance", "grand total", "sum", "payment"]
        
        // Keywords to exclude (like "tax", "tip", "savings") if we want net total,
        // but usually we want the biggest number which is the total.
        // However, we should be careful not to pick up "Change due" which might be small.
        
        for line in lines {
            let lowerLine = line.lowercased()
            
            // Skip lines that look like dates (e.g. 2024-05-12) if they accidentally match
            if lowerLine.contains("202") { // broad check for years 2020-2029
                continue
            }
            
            // Find numbers matching the strict pattern
            if let range = line.range(of: currencyPattern, options: .regularExpression) {
                var numberString = String(line[range])
                // Remove commas for Decimal conversion
                numberString = numberString.replacingOccurrences(of: ",", with: "")
                
                if let amount = Decimal(string: numberString) {
                    
                    // Filter out unlikely amounts (too small or too large)
                    // e.g. 0.00 is not useful
                    if amount <= 0.01 { continue }
                    
                    // Update max found amount
                    if maxAmount == nil || amount > (maxAmount ?? 0) {
                        maxAmount = amount
                    }
                    
                    // Check if this line is a "Total" line
                    if totalKeywords.contains(where: { lowerLine.contains($0) }) {
                        // If we find a total line, this is likely the winner.
                        // But if there are multiple numbers on the total line, we might still want the largest?
                        // Usually "Total: 100.00" has just one amount.
                        if totalLineAmount == nil || amount > (totalLineAmount ?? 0) {
                            totalLineAmount = amount
                        }
                    }
                }
            }
        }
        
        // Prioritize the amount found on a "Total" line, otherwise fallback to the largest amount found.
        return totalLineAmount ?? maxAmount
    }
    
    private func extractDate(from lines: [String]) -> Date? {
        // Common date formats: MM/dd/yyyy, dd/MM/yyyy, yyyy-MM-dd, dd-MMM-yyyy
        // Using NSDataDetector which is very powerful
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let fullText = lines.joined(separator: "\n")
        
        let matches = detector?.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
        
        // Return the first valid date found
        return matches?.first?.date
    }
    
    private func extractMerchant(from lines: [String]) -> String? {
        // Heuristic: First line that isn't just a number or symbol is usually the merchant.
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLine.isEmpty && cleanLine.rangeOfCharacter(from: CharacterSet.letters) != nil {
                // Ignore extremely short lines (like "A" or "1")
                if cleanLine.count > 2 {
                    return cleanLine.capitalized
                }
            }
        }
        return nil
    }
    
    // MARK: - Gemini Flash Integration
    
    private func scanWithGemini(image: UIImage, apiKey: String, availableWallets: [String]? = nil) async throws -> ParsedReceiptData {
        // resize image to reduce payload size if needed (Gemini handles up to 20MB, but smaller is faster)
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw OCRServiceError.imageProcessingFailed
        }
        let base64Image = jpegData.base64EncodedString()
        
        // Gemini API Endpoint for 1.5 Flash
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw OCRServiceError.imageProcessingFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var walletContext = ""
        if let wallets = availableWallets, !wallets.isEmpty {
            walletContext = "Matching Wallets (pick the most relevant if possible): \(wallets.joined(separator: ", "))"
        }
        
        let prompt = """
        Analyze this receipt image and extract the following:
        1. Merchant Name
        2. Transaction Date (YYYY-MM-DD format)
        3. Total Amount (number only)
        4. Currency Code (3-letter ISO, e.g., USD, KHR)
        5. Suggested Wallet Name from the provided list based on merchant/receipt content.
        
        \(walletContext)
        
        Return JSON format: {"merchant": "...", "date": "...", "amount": 0.00, "currency": "...", "wallet": "..."}
        If any field is missing, use null.
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Gemini API Error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
            throw OCRServiceError.textRecognitionFailed
        }
        
        return try parseGeminiResponse(data)
    }
    
    private func parseGeminiResponse(_ data: Data) throws -> ParsedReceiptData {
        // Gemini response structure
        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String
                    }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates?.first?.content.parts.first?.text else {
            throw OCRServiceError.noTextFound
        }
        
        // The text might be wrapped in ```json ... ``` code blocks
        var jsonString = text
        if let range = jsonString.range(of: "```json") {
            jsonString = String(jsonString[range.upperBound...])
        }
        if let range = jsonString.range(of: "```") {
            jsonString = String(jsonString[..<range.lowerBound])
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw OCRServiceError.textRecognitionFailed
        }
        
        struct ExtractionResult: Decodable {
            let merchant: String?
            let date: String?
            let amount: Decimal?
            let currency: String?
            let wallet: String?
        }
        
        let result = try JSONDecoder().decode(ExtractionResult.self, from: jsonData)
        
        var parsedData = ParsedReceiptData()
        parsedData.merchantName = result.merchant
        parsedData.amount = result.amount
        parsedData.currencyCode = result.currency?.uppercased()
        parsedData.suggestedWalletName = result.wallet
        
        if let dateString = result.date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            parsedData.date = formatter.date(from: dateString)
        }
        
        return parsedData
    }
}

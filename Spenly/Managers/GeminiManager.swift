import Foundation
import UIKit

// Google Gemini API Manager - FREE AI for Spenly
class GeminiManager {
    static let shared = GeminiManager()
    
    // Your Gemini API key (FREE from https://aistudio.google.com/app/apikey)
    // NOTE: Do not hardcode in release builds. Read from Info.plist (GeminiAPIKey)
    private let apiKey = "AIzaSyCAkwvRxOiBLTb8QqaM6SJFZmd_kNsk1Iw"
    
    // Use only the constant apiKey provided in this file as requested.
    private var effectiveApiKey: String { apiKey }
    
    private let model = "gemini-2.5-flash" // Latest fast and free model
    
    private init() {}
    
    // Send message to Gemini and get response
    func getResponse(
        systemPrompt: String,
        userMessage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let apiKeyToUse = effectiveApiKey
        guard apiKeyToUse != "YOUR_GEMINI_API_KEY_HERE" else {
            completion(.failure(NSError(domain: "Gemini", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Gemini API key missing. Set the apiKey in GeminiManager.swift."
            ])))
            return
        }
        
        let urlString = "https://generativelanguage.googleapis.com/v1/models/\(model):generateContent?key=\(apiKeyToUse)"
        
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Gemini", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid API URL"
            ])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
        // Combine system prompt and user message
        let fullPrompt = """
        \(systemPrompt)
        
        USER QUESTION: \(userMessage)
        """
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 500
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "Gemini", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "No data received"
                ])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    completion(.success(text))
                } else {
                    // Check for API errors
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        completion(.failure(NSError(domain: "Gemini", code: 4, userInfo: [
                            NSLocalizedDescriptionKey: message
                        ])))
                    } else {
                        let dataString = String(data: data, encoding: .utf8) ?? "Unknown error"
                        completion(.failure(NSError(domain: "Gemini", code: 5, userInfo: [
                            NSLocalizedDescriptionKey: "Invalid response: \(dataString)"
                        ])))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Extraction APIs
    // Parse transactions from arbitrary text (PDF text/CSV text/statement text)
    func extractTransactionsFromText(text: String, currency: Currency, completion: @escaping (Result<String, Error>) -> Void) {
        // If text is too long (>3000 chars), use simpler extraction approach
        let maxChars = 3000
        let shouldSimplify = text.count > maxChars
        
        let instruction: String
        if shouldSimplify {
            // Enhanced prompt for long statements with better transaction detection
            instruction = """
            You are a financial data extraction expert. Extract ALL transactions from this bank statement with maximum accuracy.
            
            CRITICAL INSTRUCTIONS:
            1. Scan EVERY line for transaction data
            2. Look for patterns like: date, description, amount, balance
            3. Include ALL transactions regardless of size
            4. Don't miss any entries even if they seem small or insignificant
            
            COMMON TRANSACTION PATTERNS TO FIND:
            - UPI payments (UPI-*, *@paytm, *@gpay, *@phonepe)
            - ATM withdrawals (ATM, CASH WDL)
            - Card payments (POS, DEBIT CARD, CREDIT CARD)
            - Transfers (TRF, NEFT, RTGS, IMPS)
            - Bill payments (BILL PAY, UTILITY)
            - Salary/credits (SAL, CREDIT, DEPOSIT)
            - Interest (INT, INTEREST)
            - Charges (CHG, FEE, CHARGES)
            
            OUTPUT FORMAT (JSON array only):
            [
              {"amount":450.50,"isExpense":true,"note":"UPI-STORE123","category":"Shopping","date":"2025-01-15"},
              {"amount":5000,"isExpense":false,"note":"SALARY","category":"Income","date":"2025-01-01"}
            ]
            
            FIELD RULES:
            - amount: numeric value only (no currency symbols)
            - isExpense: true for debits/withdrawals, false for credits/deposits
            - note: clean description (remove UPI IDs, keep merchant names)
            - category: Food & Dining, Shopping, Transportation, Entertainment, Healthcare, Bills, Income, Transfer, ATM Withdrawal, Other
            - date: YYYY-MM-DD format or null if not found
            
            CURRENCY: \(currency.symbol)
            
            BANK STATEMENT TEXT:
            \(text.prefix(maxChars))
            
            Extract ALL transactions found. Return JSON array:
            """
        } else {
            instruction = """
            You are an expert financial data analyst. Extract EVERY transaction from this bank statement with 100% accuracy.
            
            MISSION: Find ALL transactions - don't miss any, no matter how small or unusual.
            
            SCANNING STRATEGY:
            1. Read line by line systematically
            2. Look for date + description + amount patterns
            3. Check for both debit and credit entries
            4. Include partial transactions, pending items, and reversals
            5. Don't skip entries that look like fees, charges, or small amounts
            
            TRANSACTION INDICATORS TO WATCH FOR:
            - UPI transactions (UPI-*, *@paytm, *@gpay, *@phonepe, *@ybl)
            - Card transactions (POS, DEBIT CARD, CREDIT CARD, SWIPE)
            - ATM operations (ATM, CASH WDL, CASH DEP)
            - Transfers (TRF, NEFT, RTGS, IMPS, TRANSFER)
            - Bill payments (BILL PAY, UTILITY, RECHARGE)
            - Salary/credits (SAL, SALARY, CREDIT, DEPOSIT, REFUND)
            - Interest (INT, INTEREST, DIVIDEND)
            - Charges (CHG, FEE, CHARGES, PENALTY)
            - Reversals (REV, REVERSAL, ADJUSTMENT)
            
            OUTPUT FORMAT (JSON array):
            [
              {"amount":450.50,"isExpense":true,"note":"UPI-STORE123","category":"Shopping","date":"2025-01-15"},
              {"amount":5000,"isExpense":false,"note":"SALARY","category":"Income","date":"2025-01-01"}
            ]
            
            FIELD SPECIFICATIONS:
            - amount: numeric value only (extract from debit/credit columns)
            - isExpense: true for debits/withdrawals, false for credits/deposits
            - note: clean merchant name (remove UPI IDs, keep business names)
            - category: Food & Dining, Shopping, Transportation, Entertainment, Healthcare, Bills, Income, Transfer, ATM Withdrawal, Other
            - date: YYYY-MM-DD format or null if unclear
            
            CURRENCY: \(currency.symbol)
            
            BANK STATEMENT:
            \(text)
            
            Extract ALL transactions. Return JSON array:
            """
        }
        self.genericTextCallJSON(prompt: instruction, completion: completion)
    }

    // Parse transactions from an image of a receipt
    func extractTransactionsFromImage(image: UIImage, currency: Currency, completion: @escaping (Result<String, Error>) -> Void) {
        guard let jpeg = image.jpegData(compressionQuality: 0.75) else {
            completion(.failure(NSError(domain: "Gemini", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid image"]))); return
        }
        let instruction = """
        You are a receipt analysis expert. Extract transaction information from this receipt image with maximum accuracy.
        
        ANALYSIS INSTRUCTIONS:
        1. Look for total amount (usually at bottom, marked as "TOTAL", "AMOUNT", "GRAND TOTAL")
        2. Identify merchant name (store name, restaurant name, etc.)
        3. Scan for individual items and their prices
        4. Look for date and time if visible
        5. Check for tax, service charges, discounts
        
        COMMON RECEIPT PATTERNS:
        - Total amount: "TOTAL: ₹450.50", "AMOUNT: $45.99", "GRAND TOTAL: 500.00"
        - Merchant: Store name, restaurant name, business name
        - Items: Individual products/services with prices
        - Date: Usually at top or bottom
        - Tax: GST, VAT, TAX, SERVICE CHARGE
        
        OUTPUT FORMAT (JSON array):
        [
          {
            "amount": 45.99,
            "isExpense": true,
            "note": "Store Name - Item Description",
            "category": "Food & Dining",
            "date": null
          }
        ]
        
        FIELD RULES:
        - amount: numeric value only (extract total amount, not individual items)
        - isExpense: always true for receipts (purchases)
        - note: "Merchant Name - Brief Description" format
        - category: Choose from: "Food & Dining", "Shopping", "Transportation", "Entertainment", "Healthcare", "Bills", "Other"
        - date: null (we'll use current date)
        
        CURRENCY: \(currency.symbol)
        
        EXTRACTION STRATEGY:
        1. Find the total amount (usually the largest number)
        2. Identify the merchant/business name
        3. Create a descriptive note combining merchant + main items
        4. Categorize based on merchant type
        
        If receipt is unclear or unreadable, return: [{"amount":0,"isExpense":true,"note":"Unable to read receipt","category":"Other","date":null}]
        
        Analyze the receipt and return ONLY the JSON array:
        """
        let base64 = jpeg.base64EncodedString()
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": instruction],
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 8192
            ]
        ]
        self.sendBody(body, completion: completion)
    }

    // MARK: - Low-level helpers
    private func genericTextCall(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 800]
        ]
        self.sendBody(body, completion: completion)
    }
    
    private func genericTextCallJSON(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": [
                "temperature": 0.1,
                "topP": 0.95,
                "topK": 40,
                "maxOutputTokens": 8192
            ]
        ]
        self.sendBody(body, completion: completion)
    }

    private func sendBody(_ requestBody: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
        let apiKeyToUse = effectiveApiKey
        guard apiKeyToUse != "YOUR_GEMINI_API_KEY_HERE" else {
            completion(.failure(NSError(domain: "Gemini", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gemini API key missing. Set the apiKey in GeminiManager.swift."]))); return
        }
        let urlString = "https://generativelanguage.googleapis.com/v1/models/\(model):generateContent?key=\(apiKeyToUse)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Gemini", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"]))); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        do { request.httpBody = try JSONSerialization.data(withJSONObject: requestBody) } catch { completion(.failure(error)); return }
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "Gemini", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data received"]))); return }
            
        #if DEBUG
        if let rawString = String(data: data, encoding: .utf8) {
            print("🔍 Raw Gemini API response:")
            print(rawString)
        }
        #endif
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Attempt to aggregate all text parts
                    if let candidates = json["candidates"] as? [[String: Any]], let firstCandidate = candidates.first, let content = firstCandidate["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] {
                        let texts = parts.compactMap { $0["text"] as? String }
                        if !texts.isEmpty {
                            completion(.success(texts.joined(separator: "\n")))
                            return
                        }
                    }
                    // Propagate API error if present
                    if let errorObj = json["error"] as? [String: Any], let message = errorObj["message"] as? String {
                        print("❌ Gemini API error: \(message)")
                        completion(.failure(NSError(domain: "Gemini", code: 4, userInfo: [NSLocalizedDescriptionKey: message])));
                        return
                    }
                    // Fallback invalid structure - log the JSON structure
                    print("⚠️ Unexpected JSON structure:")
                    print(json)
                    completion(.failure(NSError(domain: "Gemini", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid response structure"])));
                } else {
                    completion(.failure(NSError(domain: "Gemini", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])));
                }
            } catch { 
                print("❌ JSON parsing error: \(error)")
                completion(.failure(error))
            }
        }.resume()
    }
}


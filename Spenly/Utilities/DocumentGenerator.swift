import Foundation
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CoreData
import FirebaseCrashlytics

class DocumentGenerator {
    static let shared = DocumentGenerator()
    
    private init() {}
    
    func generateCSV(from transactions: [Transaction]) -> Data {
        // Log export operation to Crashlytics
        Crashlytics.crashlytics().log("Generating CSV export with \(transactions.count) transactions")
        Crashlytics.crashlytics().setCustomValue(transactions.count, forKey: "export_transaction_count")
        Crashlytics.crashlytics().setCustomValue("csv", forKey: "export_format")
        
        var csvString = "Date,Type,Amount,Category,Contact,Note\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        for transaction in transactions {
            let date = dateFormatter.string(from: transaction.date ?? Date())
            let type = transaction.isExpense ? "Expense" : "Income"
            let amount = String(format: "%.2f", transaction.amount)
            let category = transaction.category?.name ?? "Uncategorized"
            let contactName = transaction.contact?.name ?? ""
            let note = transaction.note ?? ""
            
            // Escape fields that might contain commas
            let escapedNote = "\"\(note.replacingOccurrences(of: "\"", with: "\"\""))\""
            let escapedCategory = "\"\(category.replacingOccurrences(of: "\"", with: "\"\""))\""
            let escapedContact = "\"\(contactName.replacingOccurrences(of: "\"", with: "\"\""))\""
            
            csvString += "\(date),\(type),\(amount),\(escapedCategory),\(escapedContact),\(escapedNote)\n"
        }
        
        let data = Data(csvString.utf8)
        Crashlytics.crashlytics().log("CSV export completed successfully, generated \(data.count) bytes")
        return data
    }
    
    func generateExcel(from transactions: [Transaction]) -> Data {
        // For now, return the same format as CSV
        return generateCSV(from: transactions)
    }
    
    func generatePDF(from transactions: [Transaction], currency: Currency) -> Data {
        // Log export operation to Crashlytics
        Crashlytics.crashlytics().log("Generating PDF export with \(transactions.count) transactions")
        Crashlytics.crashlytics().setCustomValue(transactions.count, forKey: "export_transaction_count")
        Crashlytics.crashlytics().setCustomValue("pdf", forKey: "export_format")
        Crashlytics.crashlytics().setCustomValue(currency.code, forKey: "export_currency")
        
        // For now, return a simple PDF format
        let pdfString = transactions.map { transaction in
            let type = transaction.isExpense ? "Expense" : "Income"
            let amount = String(format: "%.2f", transaction.amount)
            let category = transaction.category?.name ?? "Uncategorized"
            let contact = transaction.contact?.name?.isEmpty == false ? " | Contact: \(transaction.contact?.name ?? "")" : ""
            return "\(type): \(currency.symbol)\(amount) - \(category)\(contact)"
        }.joined(separator: "\n")
        
        let data = Data(pdfString.utf8)
        Crashlytics.crashlytics().log("PDF export completed successfully, generated \(data.count) bytes")
        return data
    }
    
    func generateAndExportCSV(from transactions: [Transaction], account: Account?, includeNotes: Bool = true) -> Data {
        var csvString: String
        
        if includeNotes {
            csvString = "Account,Date,Type,Amount,Category,Contact,Note\n"
        } else {
            csvString = "Account,Date,Type,Amount,Category,Contact\n"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        for transaction in transactions {
            let accountName = account?.name ?? "Unknown"
            let date = dateFormatter.string(from: transaction.date ?? Date())
            let type = transaction.isExpense ? "Expense" : "Income"
            let amount = String(format: "%.2f", transaction.amount)
            let category = transaction.category?.name ?? "Uncategorized"
            let contactName = transaction.contact?.name ?? ""
            let escapedContact = "\"\(contactName.replacingOccurrences(of: "\"", with: "\"\""))\""
            // Escape fields that might contain commas
            let escapedCategory = "\"\(category.replacingOccurrences(of: "\"", with: "\"\""))\""
            let escapedAccountName = "\"\(accountName.replacingOccurrences(of: "\"", with: "\"\""))\""
            
            if includeNotes {
                let note = transaction.note ?? ""
                let escapedNote = "\"\(note.replacingOccurrences(of: "\"", with: "\"\""))\""
            csvString += "\(escapedAccountName),\(date),\(type),\(amount),\(escapedCategory),\(escapedContact),\(escapedNote)\n"
            } else {
                csvString += "\(escapedAccountName),\(date),\(type),\(amount),\(escapedCategory),\(escapedContact)\n"
            }
        }
        
        return Data(csvString.utf8)
    }
    
    func generateAndExportExcel(from transactions: [Transaction], account: Account?) -> Data {
        // For Excel, we'll use the same format as CSV but with .xls extension
        return generateAndExportCSV(from: transactions, account: account)
    }
    
    func generateAndExportPDF(from transactions: [Transaction], account: Account?) -> Data {
        var pdfContent = "Spenly Export\n"
        pdfContent += "Account: \(account?.name ?? "Unknown")\n"
        pdfContent += "Generated: \(Date().formatted())\n\n"
        
        // Group transactions by date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        
        let grouped = Dictionary(grouping: transactions) { transaction in
            dateFormatter.string(from: transaction.date ?? Date())
        }
        
        let sortedDates = grouped.keys.sorted { date1, date2 in
            dateFormatter.date(from: date1) ?? Date() > dateFormatter.date(from: date2) ?? Date()
        }
        
        for date in sortedDates {
            pdfContent += "\n\(date)\n"
            pdfContent += "----------------------------------------\n"
            
            if let dayTransactions = grouped[date] {
                for transaction in dayTransactions {
                    let type = transaction.isExpense ? "Expense" : "Income"
                    let amount = String(format: "%.2f", transaction.amount)
                    let category = transaction.category?.name ?? "Uncategorized"
                    let contact = transaction.contact?.name?.isEmpty == false ? "Contact: \(transaction.contact?.name ?? "")\n" : ""
                    let note = transaction.note ?? ""
                    
                    pdfContent += "\(type): $\(amount) - \(category)\n"
                    if !contact.isEmpty {
                        pdfContent += contact
                    }
                    if !note.isEmpty {
                        pdfContent += "Note: \(note)\n"
                    }
                    pdfContent += "----------------------------------------\n"
                }
            }
        }
        
        return Data(pdfContent.utf8)
    }
    
    func getExportFileName(for account: Account?, format: String) -> String {
        // Create a date formatter for user-friendly date format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        // Format: transactions_2024-01-15_14-30-25.pdf or .csv
        return "transactions_\(dateString).\(format)"
    }
} 

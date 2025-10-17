import Foundation
import SwiftUI
@preconcurrency import CoreData
import PDFKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import GoogleMobileAds

// Add export format enum
enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf = " PDF Document"
    case csv = "CSV Spreadsheet"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .pdf: return "doc.viewfinder"
        case .csv: return "tablecells"
        }
    }
    
    var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .csv: return "csv"
        }
    }
}

struct ExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @State private var showShareSheet = false
    
    @State private var selectedTimeframe: ExportTimeframe = .allTime
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isExporting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var exportURL: URL?
    @State private var includeNotes = true
    @State private var selectedFormat: ExportFormat = .pdf // Add format selection state
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export Your Transactions")
                            .font(selectedFont.font(size: 22, bold: true))
                        
                        Text("Generate a document of your financial data")
                            .font(selectedFont.font(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    
                    // Banner Ad placed below the header text (no space when premium)
                    if !IAPManager.shared.isAdsRemoved {
                        AdBannerView(adPosition: .top, adPlacement: .exportSettings)
                            .padding(.bottom, 16)
                    }
                    
                    // Main Content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Timeframe Selection Card
                            VStack(alignment: .leading, spacing: 12) {
                                // Section Title
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                    Text("Select Timeframe")
                                        .font(selectedFont.font(size: 16, bold: true))
                                }
                                
                                // Timeframe Picker
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(ExportTimeframe.allCases, id: \.self) { timeframe in
                                        Button {
                                            withAnimation {
                                                selectedTimeframe = timeframe
                                            }
                                        } label: {
                                            HStack {
                                                Text(timeframe.rawValue)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                if selectedTimeframe == timeframe {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                                } else {
                                                    Circle()
                                                        .strokeBorder(Color.gray.opacity(0.5), lineWidth: 1)
                                                        .frame(width: 20, height: 20)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                                
                                // Custom Date Range (Only show if custom is selected)
                                if selectedTimeframe == .custom {
                                    VStack(spacing: 16) {
                                        Divider()
                                            .padding(.vertical, 4)
                                        
                                        // Start Date Picker
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Start Date")
                                                .font(selectedFont.font(size: 15))
                                                .foregroundColor(.secondary)
                                            
                                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                                .datePickerStyle(.compact)
                                                .labelsHidden()
                                        }
                                        
                                        // End Date Picker
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("End Date")
                                                .font(selectedFont.font(size: 15))
                                                .foregroundColor(.secondary)
                                            
                                            DatePicker("", selection: $endDate, displayedComponents: .date)
                                                .datePickerStyle(.compact)
                                                .labelsHidden()
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            
                            // Export Options Card
                            VStack(alignment: .leading, spacing: 12) {
                                // Section Title
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                    Text("Export Format")
                                        .font(selectedFont.font(size: 16, bold: true))
                                }
                                
                                // Format options
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(ExportFormat.allCases, id: \.self) { format in
                                        Button {
                                            withAnimation {
                                                selectedFormat = format
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: format.icon)
                                                    .foregroundColor(.secondary)
                                                Text(format.rawValue)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                if selectedFormat == format {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                                } else {
                                                    Circle()
                                                        .strokeBorder(Color.gray.opacity(0.5), lineWidth: 1)
                                                        .frame(width: 20, height: 20)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                                
                                Divider()
                                
                                // Add include notes toggle
                                Toggle(isOn: $includeNotes) {
                                    HStack {
                                        Image(systemName: "note.text")
                                            .foregroundColor(.secondary)
                                        Text("Include Transaction Notes")
                                            .foregroundColor(.primary)
                                    }
                                }
                                .toggleStyle(SwitchToggleStyle(tint: themeManager.getAccentColor(for: colorScheme)))
                                .padding(.vertical, 8)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            
                            // Account Card
                            VStack(alignment: .leading, spacing: 12) {
                                // Section Title
                                HStack(spacing: 6) {
                                    Image(systemName: "creditcard")
                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                    Text("Account")
                                        .font(selectedFont.font(size: 16, bold: true))
                                }
                                
                                // Account Info
                                HStack {
                                    Image(systemName: "banknote")
                                        .foregroundColor(.secondary)
                                    Text(accountManager.currentAccount?.name ?? "All Accounts")
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            
                            // Export Button
                            Button(action: exportData) {
                                HStack {
                                    if isExporting {
                                        ProgressView()
                                            .padding(.trailing, 10)
                                    } else {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 16, weight: .semibold))
                                            .padding(.trailing, 10)
                                    }
                                    
                                    Text(isExporting ? "Preparing Export..." : "Export Now")
                                        .font(selectedFont.font(size: 16, bold: true))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isExporting ? themeManager.getAccentColor(for: colorScheme).opacity(0.5) : themeManager.getAccentColor(for: colorScheme))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            }
                            .disabled(isExporting)
                            
                            // Adding some blank space at the bottom
                            Color.clear.frame(height: 30)
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cleanupAndDismiss()
                    }
                }
            }
            .alert("Export Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay(alignment: .top) {
            LinearGradient(
                gradient: Gradient(colors: [
                    themeManager.getAccentColor(for: colorScheme).opacity(0.16),
                    themeManager.getAccentColor(for: colorScheme).opacity(0.06),
                    .clear
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 210)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .interactiveDismissDisabled(isExporting)
    }
    
    private func cleanupAndDismiss() {
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
        dismiss()
    }
    
    private func generateExportFileName(format: String) -> String {
        // Create a date formatter for user-friendly date format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        
        // Format: transactions_2024-01-15_14-30-25.pdf or .csv
        return "transactions_\(dateString).\(format)"
    }
    
    private func exportData() {
        isExporting = true
        
        let (start, end) = getDateRange()
        
        let fetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        
        // Build predicate based on whether we have a current account or want all accounts
        if let currentAccount = accountManager.currentAccount {
            // Filter by specific account and date range
            fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date <= %@ AND account == %@",
                                               start as NSDate,
                                               end as NSDate,
                                               currentAccount)
        } else {
            // All accounts - only filter by date range
            fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date <= %@",
                                               start as NSDate,
                                               end as NSDate)
        }
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)]
        fetchRequest.fetchBatchSize = 100
        
        Task {
            do {
                let transactions = try await viewContext.perform {
                    var allTransactions: [Transaction] = []
                    var batchOffset = 0
                    let batchLimit = 100
                    
                    while true {
                        fetchRequest.fetchOffset = batchOffset
                        fetchRequest.fetchLimit = batchLimit
                        
                        let batch = try fetchRequest.execute()
                        if batch.isEmpty { break }
                        
                        allTransactions.append(contentsOf: batch)
                        batchOffset += batch.count
                    }
                    
                    return allTransactions
                }
                
                // Generate data based on selected format
                let exportData: Data
                let fileName: String
                
                switch selectedFormat {
                case .pdf:
                    exportData = generatePDF(from: transactions)
                    fileName = generateExportFileName(format: "pdf")
                case .csv:
                    exportData = DocumentGenerator.shared.generateAndExportCSV(from: transactions, account: accountManager.currentAccount, includeNotes: includeNotes)
                    fileName = generateExportFileName(format: "csv")
                }
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try exportData.write(to: tempURL)
                
                await MainActor.run {
                    self.exportURL = tempURL
                    self.showShareSheet = true
                    self.isExporting = false
                }
            } catch {
                await MainActor.run {
                    self.showError = true
                    self.errorMessage = "Failed to export data: \(error.localizedDescription)"
                    self.isExporting = false
                }
            }
        }
    }
    
    private func getDateRange() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeframe {
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let endOfToday = calendar.dateInterval(of: .day, for: now)?.end ?? now
            return (start, endOfToday)
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            let endOfToday = calendar.dateInterval(of: .day, for: now)?.end ?? now
            return (start, endOfToday)
        case .lastYear:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            let endOfToday = calendar.dateInterval(of: .day, for: now)?.end ?? now
            return (start, endOfToday)
        case .custom:
            // For custom range, ensure end date goes to end of selected day
            let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end ?? endDate
            return (startDate, endOfDay)
        case .allTime:
            // Use a reasonable start date (10 years ago) and end of today
            let start = calendar.date(byAdding: .year, value: -10, to: now) ?? now
            let endOfToday = calendar.dateInterval(of: .day, for: now)?.end ?? now
            return (start, endOfToday)
        }
    }
    
    private func generatePDF(from transactions: [Transaction]) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "Spenly",
            kCGPDFContextAuthor: "Spenly App"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            // Fonts and styling
            let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
            let headerFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
            let textFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let margins = UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
            
            // Colors
            let headerColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            let textColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
            let subtleColor = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            
            // Date formatting
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            
            // Header section
            let title = "Transaction Report"
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: headerColor
            ]
            title.draw(at: CGPoint(x: margins.left, y: margins.top), withAttributes: titleAttributes)
            
            // Account and date range info
            let accountName = accountManager.currentAccount?.name ?? "All Accounts"
            let (start, end) = getDateRange()
            
            let infoAttributes: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: subtleColor
            ]
            
            "Account: \(accountName)".draw(
                at: CGPoint(x: margins.left, y: margins.top + 40),
                withAttributes: infoAttributes
            )
            
            "Period: \(dateFormatter.string(from: start)) to \(dateFormatter.string(from: end))".draw(
                at: CGPoint(x: margins.left, y: margins.top + 60),
                withAttributes: infoAttributes
            )
            
            // Draw separator line
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margins.left, y: margins.top + 90))
            path.addLine(to: CGPoint(x: pageWidth - margins.right, y: margins.top + 90))
            UIColor.lightGray.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            
            // Table headers
            let columnSpacing: CGFloat = 20
            var currentY = margins.top + 120
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: headerColor
            ]
            
            "Date".draw(at: CGPoint(x: margins.left, y: currentY), withAttributes: headerAttributes)
            "Category".draw(at: CGPoint(x: margins.left + 100 + columnSpacing, y: currentY), withAttributes: headerAttributes)
            
            // Only show note header if we're including notes
            if includeNotes {
                "Note".draw(at: CGPoint(x: margins.left + 220 + columnSpacing, y: currentY), withAttributes: headerAttributes)
            }
            
            "Amount".draw(at: CGPoint(x: pageWidth - margins.right - 80, y: currentY), withAttributes: headerAttributes)
            
            currentY += 25
            
            // Transaction rows
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: textColor
            ]
            
            for transaction in transactions {
                // Draw separator line between rows
                let rowPath = UIBezierPath()
                rowPath.move(to: CGPoint(x: margins.left, y: currentY - 5))
                rowPath.addLine(to: CGPoint(x: pageWidth - margins.right, y: currentY - 5))
                UIColor.lightGray.withAlphaComponent(0.1).setStroke()
                rowPath.lineWidth = 0.5
                rowPath.stroke()
                
                // Transaction data
                dateFormatter.string(from: transaction.date ?? Date()).draw(
                    at: CGPoint(x: margins.left, y: currentY),
                    withAttributes: rowAttributes
                )
                
                (transaction.category?.name ?? "Uncategorized").draw(
                    at: CGPoint(x: margins.left + 100 + columnSpacing, y: currentY),
                    withAttributes: rowAttributes
                )
                
                // Only draw note if we're including notes
                if includeNotes {
                    (transaction.note?.isEmpty == false ? transaction.note ?? "" : "-").draw(
                        at: CGPoint(x: margins.left + 220 + columnSpacing, y: currentY),
                        withAttributes: rowAttributes
                    )
                }
                
                let amount = CurrencyFormatter.format(transaction.amount, currency: selectedCurrency)
                let amountColor = transaction.isExpense ? UIColor.red : UIColor.systemGreen
                
                // Adjust amount position based on whether we're showing notes
                let amountX = includeNotes ? 
                    (pageWidth - margins.right - 80) : 
                    (margins.left + 220 + columnSpacing)
                
                amount.draw(
                    at: CGPoint(x: amountX, y: currentY),
                    withAttributes: [
                        .font: textFont,
                        .foregroundColor: amountColor
                    ]
                )
                
                currentY += 25
                
                // Check if we need a new page
                if currentY > pageHeight - margins.bottom {
                    context.beginPage()
                    currentY = margins.top
                }
            }
        }
        
        return data
    }
}

enum ExportTimeframe: String, CaseIterable {
    case lastMonth = "Last Month"
    case last3Months = "Last 3 Months"
    case lastYear = "Last Year"
    case custom = "Custom Range"
    case allTime = "All Time"
}

// Keep only TransactionPreviewRow here and remove ShareSheet and ActivityViewControllerRepresenter
struct TransactionPreviewRow: View {
    let transaction: Transaction
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.note ?? "")
                    .font(.subheadline)
                Text(transaction.category?.name ?? "Uncategorized")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(CurrencyFormatter.format(transaction.amount, currency: selectedCurrency))
                    .font(.subheadline)
                    .foregroundColor(transaction.isExpense ? .red : .green)
                if let date = transaction.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
} 

// Add ShareSheet struct
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.keyWindow else { return controller }
            
            controller.popoverPresentationController?.sourceView = window
            controller.popoverPresentationController?.permittedArrowDirections = []
            controller.popoverPresentationController?.sourceRect = CGRect(
                x: window.bounds.midX,
                y: window.bounds.midY,
                width: 0,
                height: 0
            )
        }
        
        controller.completionWithItemsHandler = { _, _, _, _ in
            if let url = activityItems.first as? URL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
} 


import SwiftUI
import CoreData

struct TransactionPopupView: View {
    let isExpense: Bool
    let transactions: [Transaction]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    private var filteredTransactions: [Transaction] {
        transactions
            .filter { $0.isExpense == isExpense }
            .sorted { $0.date ?? Date() > $1.date ?? Date() }
            .prefix(5)
            .map { $0 }
    }
    
    private var accentColor: Color {
        themeManager.getAccentColor(for: colorScheme)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Text("Recent \(isExpense ? "Expenses" : "Income")")
                        .font(selectedFont.font(size: 22, bold: true))
                        .foregroundColor(.white)
                    
                    Text("Last 5 transactions")
                        .font(selectedFont.font(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // Transactions list
                if filteredTransactions.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("No \(isExpense ? "expenses" : "income") found")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredTransactions, id: \.id) { transaction in
                                TransactionRowView(transaction: transaction)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            // Removed gradient overlay as requested; keep solid black background
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(accentColor)
                }
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

struct TransactionRowView: View {
    let transaction: Transaction
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: transaction.category?.icon ?? (transaction.isExpense ? "cart.fill" : "dollarsign.circle.fill"))
                .font(.system(size: 18))
                .foregroundColor(transaction.isExpense ? .red : .green)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            
            // Transaction details
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.category?.name ?? "Uncategorized")
                    .font(selectedFont.font(size: 16, bold: true))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                
                // Show contact info if available
                if let contact = transaction.contact {
                    Text("\(transaction.isExpense ? "Payee" : "Payer"): \(contact.safeName)")
                        .font(selectedFont.font(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Text(transaction.date?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .font(selectedFont.font(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Amount
            Text(CurrencyFormatter.format(transaction.amount, currency: selectedCurrency))
                .font(selectedFont.font(size: 16, bold: true))
                .foregroundColor(transaction.isExpense ? .red : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}



import SwiftUI
import CoreData

struct ImportConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var accountManager: AccountManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system

    @Binding var drafts: [DraftTransaction]
    let attachImage: UIImage?
    let onConfirm: ([DraftTransaction]) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                // Theme-based background
                liquidGlassBackground
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($drafts) { $draft in
                            TransactionDraftCard(
                                draft: $draft,
                                themeManager: themeManager,
                                colorScheme: colorScheme,
                                selectedFont: selectedFont
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Confirm Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel(); dismiss() }
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        .font(selectedFont.font(size: 16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add \(drafts.count) Transaction\(drafts.count == 1 ? "" : "s")") { 
                        onConfirm(drafts); dismiss() 
                    }
                    .disabled(drafts.isEmpty)
                    .foregroundColor(drafts.isEmpty ? .gray : themeManager.getAccentColor(for: colorScheme))
                    .font(selectedFont.font(size: 16, bold: true))
                }
            }
        }
    }
    
    // MARK: - Background
    private var liquidGlassBackground: some View {
        ZStack {
            // Base gradient matching Spenly theme
            LinearGradient(
                gradient: Gradient(colors: [
                    themeManager.getAccentColor(for: colorScheme).opacity(0.3),
                    Color.black,
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Glass morphism overlay
            Color.black.opacity(0.1)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Transaction Draft Card
struct TransactionDraftCard: View {
    @Binding var draft: DraftTransaction
    let themeManager: ThemeManager
    let colorScheme: ColorScheme
    let selectedFont: AppFont
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with amount and type
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Amount")
                        .font(selectedFont.font(size: 11))
                        .foregroundColor(.secondary)
                    
                    TextField("0.00", value: $draft.amount, format: .number)
                        .keyboardType(.decimalPad)
                        .font(selectedFont.font(size: 20, bold: true))
                        .foregroundColor(amountColor)
                }
                
                Spacer()
                
                // Income/Expense Toggle with visual effects
                VStack(spacing: 4) {
                    Text("Type")
                        .font(selectedFont.font(size: 11))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            draft.isExpense.toggle()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: draft.isExpense ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(draft.isExpense ? "Expense" : "Income")
                                .font(selectedFont.font(size: 12, bold: true))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(transactionTypeColor)
                                .shadow(color: transactionTypeColor.opacity(0.3), radius: 2, x: 0, y: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Transaction details
            VStack(spacing: 8) {
                // Note field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField("Add a note...", text: Binding(
                        get: { draft.note ?? "" },
                        set: { draft.note = $0.isEmpty ? nil : $0 }
                    ))
                    .font(selectedFont.font(size: 16))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                
                // Category field
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.secondary)
                    
                    TextField("Select category...", text: Binding(
                        get: { draft.category ?? "" },
                        set: { draft.category = $0.isEmpty ? nil : $0 }
                    ))
                    .font(selectedFont.font(size: 16))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                
                // Date picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date")
                        .font(selectedFont.font(size: 12))
                        .foregroundColor(.secondary)
                    
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { draft.date ?? Date() },
                            set: { draft.date = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(CompactDatePickerStyle())
                    .font(selectedFont.font(size: 16))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(themeManager.getAccentColor(for: colorScheme).opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - Computed Properties
    private var amountColor: Color {
        draft.isExpense ? .red : .green
    }
    
    private var transactionTypeColor: Color {
        draft.isExpense ? .red : .green
    }
}



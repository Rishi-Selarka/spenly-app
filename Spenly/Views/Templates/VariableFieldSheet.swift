import SwiftUI
import UIKit

struct VariableFieldSheet: View {
    let request: VariableFieldRequest
    let template: TransactionTemplate
    let onComplete: (VariableFieldResponse) -> Void
    let onCancel: () -> Void
    
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var amount = ""
    @State private var note = ""
    @State private var selectedDate = Date()
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Navigation Bar
                HStack {
                    GlassChevronButton(direction: .back) {
                        onCancel()
                    }
                    
                    Spacer()
                    

                    
                    Spacer()
                    
                    // Invisible spacer for alignment
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.below.ecg")
                                .font(.system(size: 40))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Complete Template")
                                .font(selectedFont.font(size: 24, bold: true))
                                .foregroundColor(.white)
                            
                            Text("Enter details for \"\(template.name)\"")
                                .font(selectedFont.font(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Variable fields
                        VStack(spacing: 20) {
                            if request.needsAmount {
                                amountField
                            }
                            
                            if request.needsNote {
                                noteField
                            }
                            
                            if request.needsDate {
                                dateField
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Button
                        Button("Create Transaction") {
                            handleComplete()
                        }
                        .buttonStyle(GradientButtonStyle())
                        .disabled(!isFormValid)
                        .opacity(isFormValid ? 1.0 : 0.6)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Field Views
    
    private var amountField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Amount")
                .font(selectedFont.font(size: 16, bold: true))
                .foregroundColor(.white)
            
            TextField("Enter amount", text: $amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(VariableFieldTextStyle())
            
            Text("Required field")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private var noteField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note")
                .font(selectedFont.font(size: 16, bold: true))
                .foregroundColor(.white)
            
            TextField("Enter note (optional)", text: $note)
                .textFieldStyle(VariableFieldTextStyle())
            
            Text("Optional field")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private var dateField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date")
                .font(selectedFont.font(size: 16, bold: true))
                .foregroundColor(.white)
            
            DatePicker(
                "Transaction Date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(CompactDatePickerStyle())
            .preferredColorScheme(.dark)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            
            Text("Select transaction date")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Form Validation
    
    private var isFormValid: Bool {
        if request.needsAmount {
            guard let amountValue = Double(amount), amountValue > 0 else {
                return false
            }
        }
        return true
    }
    
    // MARK: - Actions
    
    private func handleComplete() {
        var amountValue: Double? = nil
        
        // Validate amount if needed
        if request.needsAmount {
            guard let amount = Double(amount), amount > 0 else {
                showError("Please enter a valid amount")
                return
            }
            amountValue = amount
        }
        
        // Create response
        let response = VariableFieldResponse(
            amount: amountValue,
            note: request.needsNote ? (note.isEmpty ? nil : note) : nil,
            date: request.needsDate ? selectedDate : nil
        )
        
        onComplete(response)
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Variable Field Text Style

struct VariableFieldTextStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
            .foregroundColor(.white)
    }
}

import SwiftUI
import CoreData
import UIKit



struct TemplateListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var templateManager = TemplateManager.shared
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    @State private var showingCreateTemplate = false
    @State private var showingWelcome = false
    @State private var templateToUse: TransactionTemplate?
    @State private var showingVariableFields = false
    @State private var variableFieldRequest: VariableFieldRequest?
    @State private var templateToEdit: TransactionTemplate?
    @State private var showingEditTemplate = false
    @State private var templateToDelete: TransactionTemplate?
    @State private var showingDeleteAlert = false
    @State private var searchText = ""
    @State private var selectedSortOption: SortOption = .lastAdded
    
    // Grid configuration
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    private var filteredTemplates: [TransactionTemplate] {
        var filtered = templateManager.templates
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { template in
                template.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sorting
        switch selectedSortOption {
        case .alphabeticalAZ:
            filtered = filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .alphabeticalZA:
            filtered = filtered.sorted { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .lastAdded:
            filtered = filtered.reversed() // Most recent first
        case .mostUsed:
            // For now, sort by name as usage tracking isn't implemented
            filtered = filtered.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .typeExpense:
            filtered = filtered.filter { $0.isExpense }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .typeIncome:
            filtered = filtered.filter { !$0.isExpense }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        
        return filtered
    }
    
    // Lightweight suggestions derived from template names
    private var searchSuggestions: [String] {
        let names = templateManager.templates.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        let uniqueSorted = Array(Set(names)).sorted { $0.localizedCompare($1) == .orderedAscending }
        return Array(uniqueSorted.prefix(6))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Content
                    if templateManager.templates.isEmpty {
                        emptyStateView
                    } else {
                        templatesGridView
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    GlassChevronButton(direction: .back) {
                        dismissView()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !templateManager.templates.isEmpty {
                        Button {
                            showingCreateTemplate = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32, alignment: .center)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
        }
        // Bottom overlay search bar supersedes system .searchable
        .onTapGesture {
            hideKeyboard()
        }
        .highPriorityGesture(edgeSwipeGesture)
        .onAppear {
            if templateManager.shouldShowWelcome {
                showingWelcome = true
            }
        }
        .sheet(isPresented: $showingWelcome) {
            TemplateWelcomeView {
                templateManager.markWelcomeSeen()
                showingWelcome = false
            }
        }
        .sheet(isPresented: $showingCreateTemplate) {
            CreateTemplateView()
        }
        .sheet(isPresented: $showingEditTemplate) {
            if let templateToEdit = templateToEdit {
                CreateTemplateView(editingTemplate: templateToEdit)
            }
        }
        .sheet(isPresented: $showingVariableFields) {
            if let request = variableFieldRequest, let template = templateToUse {
                VariableFieldSheet(
                    request: request,
                    template: template,
                    onComplete: { response in
                        useTemplate(template, with: response)
                        showingVariableFields = false
                    },
                    onCancel: {
                        showingVariableFields = false
                    }
                )
            }
        }
        .alert("Delete Template", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                confirmDeleteTemplate()
            }
        } message: {
            if let template = templateToDelete {
                Text("Are you sure you want to delete '\(template.name)'? This action cannot be undone.")
            }
        }
        
    }
    
    // MARK: - Helper Functions
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "doc.text.below.ecg")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Text
            VStack(spacing: 12) {
                Text("No Templates Yet")
                    .font(selectedFont.font(size: 28, bold: true))
                    .foregroundColor(.white)
                
                Text("Create your first template to quickly add\ncommon transactions")
                    .font(selectedFont.font(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            
            // Button
            Button("Add Your First Template") {
                showingCreateTemplate = true
            }
            .buttonStyle(GradientButtonStyle())
            .frame(maxWidth: 280)
            
            Spacer()
        }
        .padding(.horizontal, 40)
    }
    
    // MARK: - Templates Grid View
    private var templatesGridView: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !templateManager.templates.isEmpty {
                    HStack(spacing: 12) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                                .font(.system(size: 16))
                            
                            TextField("Search templates...", text: $searchText)
                                .font(selectedFont.font(size: 16))
                                .foregroundColor(.white)
                                .onSubmit {
                                    hideKeyboard()
                                }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6).opacity(0.1))
                        )
                        
                        // Filter picker
                        Menu {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Button {
                                    selectedSortOption = option
                                } label: {
                                    HStack {
                                        Text(option.displayName)
                                        Spacer()
                                        Image(systemName: option.icon)
                                        if selectedSortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 20))
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(Color(.systemGray6).opacity(0.1))
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                }
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredTemplates) { template in
                        TemplateCard(
                            template: template,
                            action: {
                                handleTemplateSelection(template)
                            },
                            onEdit: {
                                templateToEdit = template
                                showingEditTemplate = true
                            },
                            onDelete: {
                                deleteTemplate(template)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Template Selection Logic
    private func handleTemplateSelection(_ template: TransactionTemplate) {
        let request = templateManager.getVariableFieldRequest(for: template)
        
        if request.hasVariableFields {
            // Set data first, then show sheet
            templateToUse = template
            variableFieldRequest = request
            DispatchQueue.main.async {
                showingVariableFields = true
            }
        } else {
            // Create transaction directly
            useTemplate(template, with: nil)
        }
    }
    
    private func useTemplate(_ template: TransactionTemplate, with response: VariableFieldResponse?) {
        let success = templateManager.createTransaction(
            from: template,
            variableResponse: response,
            context: viewContext,
            accountManager: accountManager
        )
        
        if success {
            // Add haptic feedback for success
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Dismiss the view after successful creation
            dismissView()
        } else {
            // CRITICAL FIX: Show user-friendly error instead of just logging
            showErrorAlert(
                title: "Transaction Failed",
                message: "Unable to create transaction from template. Please check your account and try again."
            )
        }
    }
    
    // MARK: - Template Management
    private func deleteTemplate(_ template: TransactionTemplate) {
        templateToDelete = template
        showingDeleteAlert = true
    }

    // MARK: - Dismiss Helpers & Gestures
    private func dismissView() {
        // Try SwiftUI environment dismiss first
        dismiss()
        // Fallback: ensure UIKit-presented hosting controller also dismisses
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var current = rootVC
            while let presented = current.presentedViewController { current = presented }
            current.dismiss(animated: true)
        }
    }
    
    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                if value.startLocation.x < 30 && value.translation.width > 80 && abs(value.translation.height) < 100 {
                    dismissView()
                }
            }
    }
    
    private func confirmDeleteTemplate() {
        guard let template = templateToDelete else { return }
        templateManager.deleteTemplate(template)
        
        // Add haptic feedback for deletion
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        templateToDelete = nil
    }
    
    // CRITICAL FIX: Add proper error alert functionality
    private func showErrorAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Find the current view controller to present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var currentController = rootViewController
            while let presentedController = currentController.presentedViewController {
                currentController = presentedController
            }
            currentController.present(alert, animated: true)
        }
    }
    
    
    // MARK: - Template Card
    struct TemplateCard: View {
        let template: TransactionTemplate
        let action: () -> Void
        let onEdit: () -> Void
        let onDelete: () -> Void
        @AppStorage("selectedFont") private var selectedFont: AppFont = .system
        @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
        @EnvironmentObject private var themeManager: ThemeManager
        @Environment(\.colorScheme) private var colorScheme
        
        var body: some View {
            Button(action: action) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: template.isExpense ?
                            [themeManager.getAccentColor(for: colorScheme), themeManager.getAccentColor(for: colorScheme).opacity(0.3)] :
                                [themeManager.getAccentColor(for: colorScheme).opacity(0.9), themeManager.getAccentColor(for: colorScheme)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 120)
                    .overlay(
                        VStack(spacing: 8) {
                            // Template name
                            Text(template.name)
                                .font(selectedFont.font(size: 16, bold: true))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            
                            // Amount (if fixed)
                            if template.amountType == .fixed, let amount = template.fixedAmount {
                                Text(CurrencyFormatter.format(amount, currency: selectedCurrency))
                                    .font(selectedFont.font(size: 14))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            // Type indicator
                            HStack(spacing: 4) {
                                Image(systemName: template.isExpense ? "minus.circle.fill" : "plus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text(template.isExpense ? "Expense" : "Income")
                                    .font(selectedFont.font(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                            .padding(.horizontal, 12)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            .contextMenu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    // MARK: - Sort Options
    enum SortOption: String, CaseIterable {
        case alphabeticalAZ = "A-Z"
        case alphabeticalZA = "Z-A"
        case lastAdded = "Last Added"
        case mostUsed = "Most Used"
        case typeExpense = "Expense Only"
        case typeIncome = "Income Only"
        
        var displayName: String {
            return self.rawValue
        }
        
        var icon: String {
            switch self {
            case .alphabeticalAZ:
                return "textformat"
            case .alphabeticalZA:
                return "textformat"
            case .lastAdded:
                return "clock"
            case .mostUsed:
                return "star"
            case .typeExpense:
                return "minus.circle"
            case .typeIncome:
                return "plus.circle"
            }
        }
    }
}

// MARK: - Gradient Button Style
struct GradientButtonStyle: ButtonStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .font(.headline.bold())
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            .background(
                LinearGradient(
                    colors: [
                        themeManager.getAccentColor(for: colorScheme),
                        themeManager.getAccentColor(for: colorScheme).opacity(0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .shadow(radius: 8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

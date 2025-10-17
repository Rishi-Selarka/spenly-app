import SwiftUI
import CoreData
import UIKit

struct CreateTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var themeManager: ThemeManager
    @ObservedObject private var templateManager = TemplateManager.shared
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    // Editing support
    let editingTemplate: TransactionTemplate?
    
    init(editingTemplate: TransactionTemplate? = nil) {
        self.editingTemplate = editingTemplate
    }
    
    // Form state
    @State private var name = ""
    @State private var isExpense = true
    @State private var selectedCategory: Category?
    @State private var showingCategoryPicker = false
    
    // Amount configuration
    @State private var amountType: FieldType = .fixed
    @State private var fixedAmount = ""
    
    // Note configuration
    @State private var noteType: FieldType = .fixed
    @State private var fixedNote = ""
    
    // Date configuration
    @State private var dateType: FieldType = .fixed
    @State private var selectedDateOption: DateOption = .today
    @State private var customDay: Int = 1
    
    // UI state
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Fetch categories for picker
    @FetchRequest(
        entity: Category.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.name, ascending: true)]
    ) private var categories: FetchedResults<Category>
    
    private var filteredCategories: [Category] {
        categories.filter { category in
            if isExpense {
                return category.type == "expense"
            } else {
                return category.type == "income"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Enhanced Navigation Bar
                HStack {
                    GlassChevronButton(direction: .back) {
                        dismiss()
                    }
                    
                    Spacer()
                    
                    Spacer()
                    
                    // Invisible spacer for alignment
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(
                    Color.black
                        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                )
                
                // Content with enhanced styling
                ScrollView {
                    LazyVStack(spacing: 28) {
                        // Header Section
                        VStack(spacing: 12) {
                            Image(systemName: editingTemplate != nil ? "square.and.pencil" : "plus.rectangle.on.folder")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                .padding(.bottom, 4)
                            
                            Text(editingTemplate != nil ? "Edit Template" : "Create Template")
                                .font(selectedFont.font(size: 28, bold: true))
                                .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                            
                            Text(editingTemplate != nil ? "Update your template details" : "Set up a shortcut for common transactions")
                                .font(selectedFont.font(size: 16))
                                .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                        
                        // Form sections with enhanced spacing
                        VStack(spacing: 24) {
                            templateDetailsSection
                            categorySection
                            amountSection
                            noteSection
                            dateSection
                        }
                        .padding(.horizontal, 24)
                        
                        // Action buttons with enhanced styling
                        Button(editingTemplate != nil ? "Update Template" : "Create Template") {
                            saveTemplate()
                        }
                        .buttonStyle(GradientButtonStyle())
                        .disabled(!isFormValid)
                        .opacity(isFormValid ? 1.0 : 0.6)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .onAppear {
            // Initialize form with existing template data if editing
            if let template = editingTemplate {
                name = template.name
                isExpense = template.isExpense
                amountType = template.amountType
                fixedAmount = template.fixedAmount?.description ?? ""
                noteType = template.noteType
                fixedNote = template.fixedNote ?? ""
                dateType = template.dateType
                selectedDateOption = template.dateOption ?? .today
                customDay = template.customDay ?? 1
                
                // Find and set the selected category
                if let categoryID = template.categoryID {
                    selectedCategory = categories.first { $0.id == categoryID }
                }
            }
        }
        .sheet(isPresented: $showingCategoryPicker) {
            TemplateCategoryPickerView(
                categories: filteredCategories,
                selectedCategory: $selectedCategory,
                isPresented: $showingCategoryPicker
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Form Sections
    
    private var templateDetailsSection: some View {
        TemplateSection(title: "Template Details") {
            VStack(spacing: 20) {
                // Name field
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 16))
                        
                        Text("Template Name")
                            .font(selectedFont.font(size: 16, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                    }
                    
                    TextField("e.g., Morning Coffee, Gas Station", text: $name)
                        .textFieldStyle(TemplateTextFieldStyle())
                        .onChange(of: name) { newValue in
                            if newValue.count > 15 {
                                name = String(newValue.prefix(15))
                            }
                        }
                    
                    HStack {
                        Spacer()
                        Text("\(name.count)/15 characters")
                            .font(selectedFont.font(size: 12))
                            .foregroundColor(
                                name.count > 12 ? 
                                (name.count == 15 ? Color.red : Color.orange) : 
                                themeManager.selectedTheme.colors(for: colorScheme).secondaryText
                            )
                    }
                }
                
                // Type picker
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 16))
                        
                        Text("Transaction Type")
                            .font(selectedFont.font(size: 16, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                    }
                    
                    HStack(spacing: 12) {
                        ForEach([true, false], id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isExpense = type
                                    selectedCategory = nil // Reset category when type changes
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: type ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                        .font(.system(size: 18))
                                    Text(type ? "Expense" : "Income")
                                        .font(selectedFont.font(size: 16, bold: false))
                                }
                                .foregroundColor(isExpense == type ? .white : themeManager.selectedTheme.colors(for: colorScheme).text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isExpense == type ? 
                                            (type ? Color.red : Color.green) : 
                                            Color(.systemGray6).opacity(0.1)
                                        )
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            isExpense == type ? Color.clear : Color.white.opacity(0.15),
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }
    
    private var categorySection: some View {
        TemplateSection(title: "Category") {
            Button {
                showingCategoryPicker = true
            } label: {
                HStack(spacing: 12) {
                    // Category icon with enhanced styling
                    Image(systemName: selectedCategory?.icon ?? "folder.fill")
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        .font(.system(size: 20))
                        .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedCategory?.name ?? "Select Category")
                            .font(selectedFont.font(size: 16, bold: false))
                            .foregroundColor(
                                selectedCategory != nil ? 
                                themeManager.selectedTheme.colors(for: colorScheme).text : 
                                themeManager.selectedTheme.colors(for: colorScheme).secondaryText
                            )
                        

                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.1))
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            selectedCategory != nil ? 
                            themeManager.getAccentColor(for: colorScheme).opacity(0.4) :
                            Color.white.opacity(0.15),
                            lineWidth: selectedCategory != nil ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var amountSection: some View {
        TemplateSection(title: "Amount") {
            VStack(spacing: 16) {
                // Enhanced field type selector
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 16))
                        
                        Text("Amount Type")
                            .font(selectedFont.font(size: 16, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        ForEach([FieldType.fixed, FieldType.variable], id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    amountType = type
                                }
                            } label: {
                                Text(type == .fixed ? "Fixed" : "Variable")
                                    .font(selectedFont.font(size: 14, bold: false))
                                    .foregroundColor(
                                        amountType == type ? .white : 
                                        themeManager.selectedTheme.colors(for: colorScheme).text
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                amountType == type ? 
                                                themeManager.getAccentColor(for: colorScheme) :
                                                Color(.systemGray6).opacity(0.1)
                                            )
                                            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                themeManager.selectedTheme.colors(for: colorScheme).accent.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                // Amount field (only for fixed)
                if amountType == .fixed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Amount")
                            .font(selectedFont.font(size: 14, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                        
                        TextField("Enter amount", text: $fixedAmount)
                            .textFieldStyle(TemplateTextFieldStyle())
                            .keyboardType(.decimalPad)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 14))
                        
                        Text("Amount will be prompted when using template")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }
    
    private var noteSection: some View {
        TemplateSection(title: "Note") {
            VStack(spacing: 16) {
                // Enhanced field type selector
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 16))
                        
                        Text("Note Type")
                            .font(selectedFont.font(size: 16, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        ForEach([FieldType.fixed, FieldType.variable], id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    noteType = type
                                }
                            } label: {
                                Text(type == .fixed ? "Fixed" : "Variable")
                                    .font(selectedFont.font(size: 14, bold: false))
                                    .foregroundColor(
                                        noteType == type ? .white : 
                                        themeManager.selectedTheme.colors(for: colorScheme).text
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                noteType == type ? 
                                                themeManager.getAccentColor(for: colorScheme) :
                                                Color(.systemGray6).opacity(0.1)
                                            )
                                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                noteType == type ? Color.clear :
                                                themeManager.selectedTheme.colors(for: colorScheme).accent.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                // Note field (only for fixed)
                if noteType == .fixed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note")
                            .font(selectedFont.font(size: 14, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                        
                        TextField("Enter note (optional)", text: $fixedNote)
                            .textFieldStyle(TemplateTextFieldStyle())
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 14))
                        
                        Text("Note will be prompted when using template")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }
    
    private var dateSection: some View {
        TemplateSection(title: "Date") {
            VStack(spacing: 16) {
                // Enhanced field type selector
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 16))
                        
                        Text("Date Type")
                            .font(selectedFont.font(size: 16, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                        
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        ForEach([FieldType.fixed, FieldType.variable], id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    dateType = type
                                }
                            } label: {
                                Text(type == .fixed ? "Fixed" : "Variable")
                                    .font(selectedFont.font(size: 14, bold: false))
                                    .foregroundColor(
                                        dateType == type ? .white : 
                                        themeManager.selectedTheme.colors(for: colorScheme).text
                                    )
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                dateType == type ? 
                                                themeManager.getAccentColor(for: colorScheme) :
                                                Color(.systemGray6).opacity(0.1)
                                            )
                                            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                dateType == type ? Color.clear :
                                                themeManager.selectedTheme.colors(for: colorScheme).accent.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                // Date options (only for fixed)
                if dateType == .fixed {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Date Option")
                            .font(selectedFont.font(size: 14, bold: true))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                            ForEach(DateOption.allCases, id: \.self) { option in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        selectedDateOption = option
                                    }
                                } label: {
                                    Text(option.displayName)
                                        .font(selectedFont.font(size: 12, bold: false))
                                        .foregroundColor(
                                            selectedDateOption == option ? .white :
                                            themeManager.selectedTheme.colors(for: colorScheme).text
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(
                                                    selectedDateOption == option ?
                                                    themeManager.getAccentColor(for: colorScheme) :
                                                    Color(.systemGray6).opacity(0.1)
                                                )
                                                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(
                                                    selectedDateOption == option ? Color.clear : Color.white.opacity(0.15),
                                                    lineWidth: 1
                                                )
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Custom day picker (only if custom is selected)
                        if selectedDateOption == .custom {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Select Day of Month")
                                    .font(selectedFont.font(size: 14, bold: true))
                                    .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(1...31, id: \.self) { day in
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.1)) {
                                                    customDay = day
                                                }
                                            } label: {
                                                Text("\(day)")
                                                    .font(selectedFont.font(size: 14, bold: false))
                                                    .foregroundColor(
                                                        customDay == day ? .white :
                                                        themeManager.selectedTheme.colors(for: colorScheme).text
                                                    )
                                                    .frame(width: 36, height: 36)
                                                    .background(
                                                        Circle()
                                                            .fill(
                                                                customDay == day ?
                                                                themeManager.getAccentColor(for: colorScheme) :
                                                                Color(.systemGray6).opacity(0.1)
                                                            )
                                                            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
                                                    )
                                                    .overlay(
                                                        Circle()
                                                            .strokeBorder(
                                                                customDay == day ? Color.clear : Color.white.opacity(0.15),
                                                                lineWidth: 1
                                                            )
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                                
                                Text("Day \(customDay) of current month will be used")
                                    .font(selectedFont.font(size: 12))
                                    .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).secondaryText)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                            .font(.system(size: 14))
                        
                        Text("Date will be prompted when using template")
                            .font(selectedFont.font(size: 14))
                            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }
    
    // MARK: - Form Validation
    
    private var isFormValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        
        if amountType == .fixed {
            guard let amount = Double(fixedAmount), amount > 0 else { return false }
        }
        
        return true
    }
    
    // MARK: - Template Management
    
    private func saveTemplate() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate name
        guard templateManager.validateTemplateName(trimmedName) else {
            showError("Please enter a valid template name (1-15 characters)")
            return
        }
        
        // Check uniqueness (skip if editing and name hasn't changed)
        if editingTemplate == nil || editingTemplate?.name != trimmedName {
            guard templateManager.isTemplateNameUnique(trimmedName) else {
                showError("A template with this name already exists")
                return
            }
        }
        
        // Validate fixed amount if needed
        var amountValue: Double? = nil
        if amountType == .fixed {
            guard let amount = Double(fixedAmount), amount > 0 else {
                showError("Please enter a valid amount")
                return
            }
            amountValue = amount
        }
        
        if let existingTemplate = editingTemplate {
            // Update existing template
            let updatedTemplate = TransactionTemplate(
                id: existingTemplate.id, // Preserve existing ID
                name: trimmedName,
                isExpense: isExpense,
                categoryID: selectedCategory?.id,
                amountType: amountType,
                fixedAmount: amountValue,
                noteType: noteType,
                fixedNote: noteType == .fixed ? fixedNote : nil,
                dateType: dateType,
                dateOption: dateType == .fixed ? selectedDateOption : nil,
                customDay: dateType == .fixed && selectedDateOption == .custom ? customDay : nil
            )
            templateManager.updateTemplate(updatedTemplate)
        } else {
            // Create new template
            let template = TransactionTemplate(
                name: trimmedName,
                isExpense: isExpense,
                categoryID: selectedCategory?.id,
                amountType: amountType,
                fixedAmount: amountValue,
                noteType: noteType,
                fixedNote: noteType == .fixed ? fixedNote : nil,
                dateType: dateType,
                dateOption: dateType == .fixed ? selectedDateOption : nil,
                customDay: dateType == .fixed && selectedDateOption == .custom ? customDay : nil
            )
            templateManager.addTemplate(template)
        }
        
        dismiss()
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Supporting Views

struct TemplateSection<Content: View>: View {
    let title: String
    let content: Content
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text(title)
                    .font(selectedFont.font(size: 18, bold: true))
                    .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Section Content
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.15))
                .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        )
                .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct TemplateTextFieldStyle: TextFieldStyle {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6).opacity(0.1))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
    }
}

struct TemplateCategoryPickerView: View {
    let categories: [Category]
    @Binding var selectedCategory: Category?
    @Binding var isPresented: Bool
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Enhanced Navigation Bar
                HStack {
                    GlassChevronButton(direction: .back) {
                        isPresented = false
                    }
                    
                    Spacer()
                    
                    Text("Select Category")
                        .font(selectedFont.font(size: 18, bold: true))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Invisible spacer for alignment
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(
                    Color.black
                        .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                )
                
                // Enhanced Category List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(categories, id: \.id) { category in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = category
                                    isPresented = false
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: category.icon ?? "folder.fill")
                                        .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                        .font(.system(size: 20))
                                        .frame(width: 28, height: 28)
                                    
                                    Text(category.name ?? "Unknown")
                                        .font(selectedFont.font(size: 16, bold: false))
                                        .foregroundColor(themeManager.selectedTheme.colors(for: colorScheme).text)
                                    
                                    Spacer()
                                    
                                    if selectedCategory?.id == category.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(themeManager.getAccentColor(for: colorScheme))
                                            .font(.system(size: 20))
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6).opacity(0.1))
                                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            selectedCategory?.id == category.id ?
                                            themeManager.getAccentColor(for: colorScheme).opacity(0.4) :
                                            Color.white.opacity(0.1),
                                            lineWidth: selectedCategory?.id == category.id ? 1.5 : 1
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
        }
    }
}

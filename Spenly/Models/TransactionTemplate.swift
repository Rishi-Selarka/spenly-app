import Foundation

// MARK: - Transaction Template Data Models
struct TransactionTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let isExpense: Bool
    let categoryID: UUID?
    
    // Amount configuration
    let amountType: FieldType
    let fixedAmount: Double?
    
    // Note configuration
    let noteType: FieldType
    let fixedNote: String?
    
    // Date configuration
    let dateType: FieldType
    let dateOption: DateOption?
    let customDay: Int? // For custom date option (1-31)
    
    init(
        id: UUID = UUID(),
        name: String,
        isExpense: Bool,
        categoryID: UUID? = nil,
        amountType: FieldType,
        fixedAmount: Double? = nil,
        noteType: FieldType,
        fixedNote: String? = nil,
        dateType: FieldType,
        dateOption: DateOption? = nil,
        customDay: Int? = nil
    ) {
        self.id = id
        // DEFENSIVE: Trim and validate name
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isExpense = isExpense
        self.categoryID = categoryID
        self.amountType = amountType
        // DEFENSIVE: Ensure fixed amount is positive if provided
        self.fixedAmount = (fixedAmount != nil && fixedAmount! > 0) ? fixedAmount : nil
        self.noteType = noteType
        // DEFENSIVE: Trim fixed note if provided
        self.fixedNote = fixedNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.dateType = dateType
        self.dateOption = dateOption
        // DEFENSIVE: Validate custom day is between 1-31
        self.customDay = (customDay != nil && customDay! >= 1 && customDay! <= 31) ? customDay : nil
    }
}

// MARK: - Supporting Enums
enum FieldType: String, CaseIterable, Codable {
    case fixed = "fixed"
    case variable = "variable"
    
    var displayName: String {
        switch self {
        case .fixed: return "Fixed"
        case .variable: return "Variable"
        }
    }
}

enum DateOption: String, CaseIterable, Codable {
    case yesterday = "yesterday"
    case today = "today"
    case tomorrow = "tomorrow"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .yesterday: return "Yesterday"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .custom: return "Custom Day"
        }
    }
    
    var date: Date {
        let calendar = Calendar.current
        let today = Date()
        
        switch self {
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: today) ?? today
        case .today:
            return today
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .custom:
            return today // Default, will be overridden with custom day
        }
    }
}

// MARK: - Variable Field Request
struct VariableFieldRequest {
    let templateName: String
    let needsAmount: Bool
    let needsNote: Bool
    let needsDate: Bool
    
    var hasVariableFields: Bool {
        return needsAmount || needsNote || needsDate
    }
}

// MARK: - Variable Field Response
struct VariableFieldResponse {
    let amount: Double?
    let note: String?
    let date: Date?
}

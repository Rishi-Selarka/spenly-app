import Foundation

struct TransactionReminder: Identifiable, Codable {
    let id: UUID
    var time: Date
    var days: Set<WeekDay>
    var isEnabled: Bool
    var note: String
    var category: ReminderCategory
    var priority: ReminderPriority
    var sound: ReminderSound
    
    init(id: UUID = UUID(), 
         time: Date, 
         days: Set<WeekDay>, 
         isEnabled: Bool = true, 
         note: String = "", 
         category: ReminderCategory = .general,
         priority: ReminderPriority = .medium,
         sound: ReminderSound = .default) {
        self.id = id
        self.time = time
        self.days = days
        self.isEnabled = isEnabled
        self.note = note
        self.category = category
        self.priority = priority
        self.sound = sound
    }
    
    enum WeekDay: Int, CaseIterable, Codable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7
        
        var shortName: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }
    }
    
    enum ReminderCategory: String, CaseIterable, Codable {
        case general = "General"
        case bill = "Bill Payment"
        case subscription = "Subscription"
        case income = "Income"
        case budget = "Budget Check"
        case savings = "Savings"
        case investment = "Investment"
        
        var iconName: String {
            switch self {
            case .general: return "bell.fill"
            case .bill: return "dollarsign.circle.fill"
            case .subscription: return "arrow.clockwise.circle.fill"
            case .income: return "arrow.down.circle.fill"
            case .budget: return "chart.bar.fill"
            case .savings: return "banknote.fill"
            case .investment: return "chart.line.uptrend.xyaxis.circle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .general: return "blue"
            case .bill: return "red"
            case .subscription: return "purple"
            case .income: return "green"
            case .budget: return "orange"
            case .savings: return "teal"
            case .investment: return "indigo"
            }
        }
    }
    
    enum ReminderPriority: String, CaseIterable, Codable {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        
        var iconName: String {
            switch self {
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "checkmark.circle.fill"
            case .low: return "info.circle.fill"
            }
        }
        
        var color: String {
            switch self {
            case .high: return "red"
            case .medium: return "yellow"
            case .low: return "blue"
            }
        }
    }
    
    enum ReminderSound: String, CaseIterable, Codable {
        case `default` = "Default"
        case none = "None"
        case alert = "Alert"
        case bell = "Bell"
        case chord = "Chord"
        case notification = "Notification"
        
        var filename: String? {
            switch self {
            case .default: return nil // Uses system default
            case .none: return nil
            case .alert: return "alert.caf"
            case .bell: return "bell.caf"
            case .chord: return "chord.caf"
            case .notification: return "notification.caf"
            }
        }
    }
} 
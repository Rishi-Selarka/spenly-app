import SwiftUI
import UserNotifications

struct ReminderSettingsView: View {
    @StateObject private var reminderManager = ReminderManager.shared
    @State private var showingAddReminder = false
    @State private var editingReminder: TransactionReminder?
    
    var body: some View {
        List {
            // Default reminder section
            Section {
                // Default reminder row
                HStack {
                    VStack(alignment: .leading) {
                        Text("Daily Reminder")
                            .font(.headline)
                        Text("9:00 PM")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Log your daily transactions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "bell.fill")
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Default Reminder")
            } footer: {
                Text("This reminder is set by default and cannot be modified")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Next upcoming reminder (if there is one)
            if let nextReminder = findNextReminder() {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            Text("Next Reminder")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(getFormattedTime(nextReminder.time))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if !nextReminder.note.isEmpty {
                            Text(nextReminder.note)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Upcoming")
                }
            }
            
            // Existing custom reminders section
            Section {
                if reminderManager.reminders.isEmpty {
                    Text("No custom reminders set")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(reminderManager.reminders) { reminder in
                        EnhancedReminderRow(reminder: reminder)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingReminder = reminder
                            }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            reminderManager.deleteReminder(reminderManager.reminders[index])
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom Reminders")
                    Spacer()
                    Text("\(reminderManager.reminders.count) Total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button {
                    showingAddReminder = true
                } label: {
                    Label("Add Custom Reminder", systemImage: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Reminders")
        .sheet(isPresented: $showingAddReminder) {
            EnhancedAddReminderView()
        }
        .sheet(item: $editingReminder) { reminder in
            EnhancedAddReminderView(editingReminder: reminder)
        }
    }
    
    // Helper method to find the next scheduled reminder - optimized for performance
    private func findNextReminder() -> TransactionReminder? {
        guard !reminderManager.reminders.isEmpty else { return nil }
        
        let enabledReminders = reminderManager.reminders.filter { $0.isEnabled }
        guard !enabledReminders.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        
        // Create a time-only value for comparison (in minutes since midnight)
        let currentTimeInMinutes = hour * 60 + minute
        
        // First check for today's reminders
        let todayReminders = enabledReminders.filter { reminder in
            reminder.days.contains(where: { $0.rawValue == weekday })
        }
        
        if !todayReminders.isEmpty {
            // Find the first reminder that's later today
            let laterTodayReminders = todayReminders.filter { reminder in
                let reminderHour = calendar.component(.hour, from: reminder.time)
                let reminderMinute = calendar.component(.minute, from: reminder.time)
                let reminderTimeInMinutes = reminderHour * 60 + reminderMinute
                
                return reminderTimeInMinutes > currentTimeInMinutes
            }
            
            if let nextReminder = laterTodayReminders.min(by: { 
                let hour1 = calendar.component(.hour, from: $0.time)
                let minute1 = calendar.component(.minute, from: $0.time)
                let time1 = hour1 * 60 + minute1
                
                let hour2 = calendar.component(.hour, from: $1.time)
                let minute2 = calendar.component(.minute, from: $1.time)
                let time2 = hour2 * 60 + minute2
                
                return time1 < time2
            }) {
                return nextReminder
            }
        }
        
        // No reminders for today, find the next upcoming day with a reminder
        var nextDay = weekday
        var daysChecked = 0
        
        while daysChecked < 7 {
            nextDay = nextDay % 7 + 1 // Move to next day, wrapping from 7 to 1
            daysChecked += 1
            
            let nextDayReminders = enabledReminders.filter { reminder in
                reminder.days.contains(where: { $0.rawValue == nextDay })
            }
            
            if let earliest = nextDayReminders.min(by: { 
                let hour1 = calendar.component(.hour, from: $0.time)
                let minute1 = calendar.component(.minute, from: $0.time)
                let time1 = hour1 * 60 + minute1
                
                let hour2 = calendar.component(.hour, from: $1.time)
                let minute2 = calendar.component(.minute, from: $1.time)
                let time2 = hour2 * 60 + minute2
                
                return time1 < time2
            }) {
                return earliest
            }
        }
        
        return nil
    }
    
    private func getFormattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct EnhancedReminderRow: View {
    let reminder: TransactionReminder
    @StateObject private var reminderManager = ReminderManager.shared
    
    // Cache these values to avoid repeated calculations during scrolling
    private let daysText: String
    private let hasNote: Bool
    
    init(reminder: TransactionReminder) {
        self.reminder = reminder
        self.daysText = reminder.days.map { $0.shortName }.joined(separator: ", ")
        self.hasNote = !reminder.note.isEmpty
    }
    
    var body: some View {
        HStack {
            // Category icon
            Image(systemName: reminder.category.iconName)
                .foregroundColor(Color.named(reminder.category.color))
                .font(.system(size: 18))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(reminder.time, style: .time)
                        .font(.headline)
                    
                    // Priority indicator
                    if reminder.priority == .high {
                        Image(systemName: reminder.priority.iconName)
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                    }
                }
                
                Text(daysText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if hasNote {
                    Text(reminder.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                // Display category tag
                Text(reminder.category.rawValue)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.named(reminder.category.color).opacity(0.2))
                    .foregroundColor(Color.named(reminder.category.color))
                    .cornerRadius(6)
                
                Toggle("", isOn: Binding(
                    get: { reminder.isEnabled },
                    set: { _ in reminderManager.toggleReminder(reminder) }
                ))
            }
        }
        .padding(.vertical, 4)
    }
}

struct EnhancedAddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var reminderManager = ReminderManager.shared
    @State private var time: Date
    @State private var selectedDays: Set<TransactionReminder.WeekDay>
    @State private var note: String
    @State private var selectedCategory: TransactionReminder.ReminderCategory
    @State private var selectedPriority: TransactionReminder.ReminderPriority
    @State private var showingConfirmation = false
    @State private var selectedTab = 0
    
    let editingReminder: TransactionReminder?
    
    init(editingReminder: TransactionReminder? = nil) {
        self.editingReminder = editingReminder
        _time = State(initialValue: editingReminder?.time ?? Date())
        _selectedDays = State(initialValue: editingReminder?.days ?? [])
        _note = State(initialValue: editingReminder?.note ?? "")
        
        // Set properties based on the existing reminder
        if let reminder = editingReminder {
            _selectedCategory = State(initialValue: reminder.category)
            _selectedPriority = State(initialValue: reminder.priority)
        } else {
            _selectedCategory = State(initialValue: TransactionReminder.ReminderCategory.general)
            _selectedPriority = State(initialValue: TransactionReminder.ReminderPriority.medium)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector
                HStack(spacing: 0) {
                    TabButton(title: "Basic", isSelected: selectedTab == 0) { selectedTab = 0 }
                    TabButton(title: "Advanced", isSelected: selectedTab == 1) { selectedTab = 1 }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Tab Content
                if selectedTab == 0 {
                    // Basic settings
                    Form {
                        Section {
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        }
                        
                        Section {
                            ForEach(TransactionReminder.WeekDay.allCases, id: \.rawValue) { day in
                                Toggle(day.shortName, isOn: Binding(
                                    get: { selectedDays.contains(day) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedDays.insert(day)
                                        } else {
                                            selectedDays.remove(day)
                                        }
                                    }
                                ))
                            }
                        } header: {
                            Text("Repeat On")
                        }
                        
                        Section {
                            TextField("Reminder Note (Optional)", text: $note)
                        } header: {
                            Text("Note")
                        }
                    }
                } else {
                    // Advanced settings
                    Form {
                        Section {
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(TransactionReminder.ReminderCategory.allCases, id: \.self) { category in
                                    HStack {
                                        Image(systemName: category.iconName)
                                            .foregroundColor(Color.named(category.color))
                                        Text(category.rawValue)
                                    }
                                    .tag(category)
                                }
                            }
                            
                            Picker("Priority", selection: $selectedPriority) {
                                ForEach(TransactionReminder.ReminderPriority.allCases, id: \.self) { priority in
                                    HStack {
                                        Image(systemName: priority.iconName)
                                            .foregroundColor(Color.named(priority.color))
                                        Text(priority.rawValue)
                                    }
                                    .tag(priority)
                                }
                            }
                            
                            // Quick frequency buttons
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Quick Set Frequency")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button("Daily") { selectAllDays() }
                                        .buttonStyle(FrequencyButtonStyle(isActive: selectedDays.count == 7))
                                    
                                    Button("Weekdays") { selectWeekdays() }
                                        .buttonStyle(FrequencyButtonStyle(isActive: isWeekdays()))
                                    
                                    Button("Weekends") { selectWeekends() }
                                        .buttonStyle(FrequencyButtonStyle(isActive: isWeekends()))
                                }
                            }
                            .padding(.vertical, 8)
                        } header: {
                            Text("Options")
                        }
                        
                        // Preview Section
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("You'll receive a notification at \(formatTime(time))")
                                        .font(.system(size: 14))
                                    
                                    Spacer()
                                }
                                
                                Text(selectedDays.map { $0.shortName }.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(.vertical, 8)
                        } header: {
                            Text("How it will appear")
                        }
                    }
                }
            }
            .navigationTitle(editingReminder == nil ? "Add Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveReminder()
                        dismiss()
                    }
                    .disabled(selectedDays.isEmpty)
                }
            }
        }
    }
    
    private func saveReminder() {
        let reminder = TransactionReminder(
            id: editingReminder?.id ?? UUID(),
            time: time,
            days: selectedDays,
            isEnabled: editingReminder?.isEnabled ?? true,
            note: note,
            category: selectedCategory,
            priority: selectedPriority,
            sound: editingReminder?.sound ?? .default // Use existing sound or default
        )
        
        if editingReminder != nil {
            reminderManager.updateReminder(reminder)
        } else {
            reminderManager.addReminder(reminder)
        }
    }
    
    // Helper methods for quick day selection
    private func selectAllDays() {
        selectedDays = Set(TransactionReminder.WeekDay.allCases)
    }
    
    private func selectWeekdays() {
        selectedDays = [
            TransactionReminder.WeekDay.monday,
            TransactionReminder.WeekDay.tuesday,
            TransactionReminder.WeekDay.wednesday,
            TransactionReminder.WeekDay.thursday,
            TransactionReminder.WeekDay.friday
        ]
    }
    
    private func selectWeekends() {
        selectedDays = [
            TransactionReminder.WeekDay.saturday,
            TransactionReminder.WeekDay.sunday
        ]
    }
    
    private func isWeekdays() -> Bool {
        let weekdays: Set<TransactionReminder.WeekDay> = [
            .monday, .tuesday, .wednesday, .thursday, .friday
        ]
        return selectedDays == weekdays
    }
    
    private func isWeekends() -> Bool {
        let weekends: Set<TransactionReminder.WeekDay> = [
            .saturday, .sunday
        ]
        return selectedDays == weekends
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 3)
                    
                    if isSelected {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(height: 3)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

struct FrequencyButtonStyle: ButtonStyle {
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.blue : (configuration.isPressed ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1)))
            )
            .foregroundColor(isActive ? .white : .primary)
    }
}

extension Color {
    static func named(_ name: String) -> Color {
        switch name.lowercased() {
        case "red":
            return .red
        case "blue":
            return .blue
        case "green":
            return .green
        case "yellow":
            return .yellow
        case "orange":
            return .orange
        case "purple":
            return .purple
        case "pink":
            return .pink
        case "indigo":
            return Color(UIColor.systemIndigo)
        case "teal":
            return Color(UIColor.systemTeal)
        default:
            return .primary
        }
    }
} 

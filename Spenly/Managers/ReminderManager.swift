import Foundation
import UserNotifications
import SwiftUI

class ReminderManager: ObservableObject {
    static let shared = ReminderManager()
    @Published private(set) var reminders: [TransactionReminder] = []
    @Published var filteredCategory: TransactionReminder.ReminderCategory? = nil
    @Published var showMissedReminders: Bool = true
    let defaultReminderID = "default-daily-reminder"
    
    private let userDefaults = UserDefaults.standard
    private let remindersKey = "transactionReminders"
    
    init() {
        loadReminders()
        setupTimezoneObserver()
        
        // Respect centralized permission flow: don't prompt here
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async { self.setupDefaultReminder() }
            } else {
                print("🔔 Skipping permission request in ReminderManager; handled post-login by AuthManager")
            }
        }
    }
    
    deinit {
        // Clean up notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupTimezoneObserver() {
        // Use a simpler approach that doesn't store observer references
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTimezoneChange),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
    }
    
    @objc private func handleTimezoneChange() {
        // Reschedule all reminders when timezone changes
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        setupDefaultReminder()
        
        // Reschedule all custom reminders
        reminders.filter(\.isEnabled).forEach { scheduleNotification(for: $0) }
    }
    
    private func setupDefaultReminder() {
        let center = UNUserNotificationCenter.current()
        
        print("🔔 Setting up default 9pm reminder...")
        
        // Create default 9 PM components using the current calendar
        var components = DateComponents()
        components.hour = 21
        components.minute = 0
        
        let content = UNMutableNotificationContent()
        content.title = "Daily Transaction Reminder"
        content.body = "Don't forget to log your transactions!"
        content.sound = .default
        content.badge = 0
        
        // Create calendar trigger that repeats daily
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )
        
        // Remove any existing default reminders first
        center.removePendingNotificationRequests(withIdentifiers: [self.defaultReminderID])
        
        let request = UNNotificationRequest(
            identifier: self.defaultReminderID,
            content: content,
            trigger: trigger
        )
        
        // Add the notification request
        center.add(request) { error in
            if let error = error {
                print("❌ Error scheduling default reminder: \(error.localizedDescription)")
            } else {
                print("✅ Default 9pm reminder scheduled successfully!")
                
                // Verify it was actually scheduled
                center.getPendingNotificationRequests { requests in
                    let defaultReminderExists = requests.contains { $0.identifier == self.defaultReminderID }
                    if defaultReminderExists {
                        print("✅ Verified: Default reminder is in pending notifications")
                        if let defaultRequest = requests.first(where: { $0.identifier == self.defaultReminderID }),
                           let calendarTrigger = defaultRequest.trigger as? UNCalendarNotificationTrigger,
                           let nextFireDate = calendarTrigger.nextTriggerDate() {
                            print("📅 Next 9pm reminder will fire at: \(nextFireDate)")
                        }
                    } else {
                        print("❌ Warning: Default reminder was not found in pending notifications")
                    }
                }
            }
        }
    }
    
    func addReminder(_ reminder: TransactionReminder) {
        reminders.append(reminder)
        saveReminders()
        if reminder.isEnabled {
            scheduleNotification(for: reminder)
        }
    }
    
    func toggleReminder(_ reminder: TransactionReminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index].isEnabled.toggle()
            saveReminders()
            
            if reminders[index].isEnabled {
                scheduleNotification(for: reminders[index])
            } else {
                UNUserNotificationCenter.current().removePendingNotificationRequests(
                    withIdentifiers: getReminderIdentifiers(for: reminder)
                )
            }
        }
    }
    
    func deleteReminder(_ reminder: TransactionReminder) {
        if reminder.id.uuidString != defaultReminderID {
            reminders.removeAll { $0.id == reminder.id }
            saveReminders()
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: getReminderIdentifiers(for: reminder)
            )
        }
    }
    
    func updateReminder(_ reminder: TransactionReminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = reminder
            saveReminders()
            
            // Remove existing notifications for this reminder
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: getReminderIdentifiers(for: reminder)
            )
            
            // Schedule new notifications if enabled
            if reminder.isEnabled {
                scheduleNotification(for: reminder)
            }
        }
    }
    
    private func getReminderIdentifiers(for reminder: TransactionReminder) -> [String] {
        reminder.days.map { "\(reminder.id)-\($0.rawValue)" }
    }
    
    private func saveReminders() {
        if let encoded = try? JSONEncoder().encode(reminders) {
            userDefaults.set(encoded, forKey: remindersKey)
        }
    }
    
    private func loadReminders() {
        if let data = userDefaults.data(forKey: remindersKey),
           let decoded = try? JSONDecoder().decode([TransactionReminder].self, from: data) {
            reminders = decoded
            // Reschedule enabled reminders
            decoded.filter(\.isEnabled).forEach { scheduleNotification(for: $0) }
        }
    }
    
    private func scheduleNotification(for reminder: TransactionReminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.category.rawValue + " Reminder"
        content.body = reminder.note.isEmpty ? 
            "Don't forget to log your spending!" : reminder.note
        content.categoryIdentifier = reminder.category.rawValue
        content.userInfo = ["priority": reminder.priority.rawValue]
        
        if reminder.sound == .none {
            // No sound
        } else if reminder.sound == .default {
            content.sound = .default
        } else if let soundName = reminder.sound.filename {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
        }
        
        // Use the current calendar to ensure proper timezone handling
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: reminder.time)
        
        for day in reminder.days {
            var triggerComponents = DateComponents()
            triggerComponents.hour = components.hour
            triggerComponents.minute = components.minute
            triggerComponents.weekday = day.rawValue
            
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: triggerComponents,
                repeats: true
            )
            
            let request = UNNotificationRequest(
                identifier: "\(reminder.id)-\(day.rawValue)",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    // Verify and reschedule if needed
    func verifyDefaultReminder() {
        let center = UNUserNotificationCenter.current()
        
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self = self else { return }
            
            // Check if our default reminder exists
            let hasDefaultReminder = requests.contains { $0.identifier == self.defaultReminderID }
            
            if !hasDefaultReminder {
                DispatchQueue.main.async {
                    self.setupDefaultReminder()
                }
            }
            
            // Verify all notification times are still valid
            for request in requests {
                if let trigger = request.trigger as? UNCalendarNotificationTrigger,
                   let nextTriggerDate = trigger.nextTriggerDate() {
                    // If the next trigger date is more than 24 hours in the past,
                    // the reminder might be affected by timezone changes
                    if nextTriggerDate.timeIntervalSinceNow < -86400 {
                        // Reschedule all reminders
                        DispatchQueue.main.async {
                            self.handleTimezoneChange()
                        }
                        break
                    }
                }
            }
        }
    }
    
    // Filter reminders by category
    func filteredReminders(by category: TransactionReminder.ReminderCategory? = nil) -> [TransactionReminder] {
        guard let category = category else {
            return reminders
        }
        return reminders.filter { $0.category == category }
    }
    
    // Get the count of reminders by category
    func reminderCount(for category: TransactionReminder.ReminderCategory) -> Int {
        reminders.filter { $0.category == category }.count
    }
    
    // Get next upcoming reminder
    var nextReminder: TransactionReminder? {
        guard !reminders.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        
        // First, find reminders that are scheduled for today but later
        let todayReminders = reminders.filter { reminder in
            reminder.isEnabled && 
            reminder.days.contains(where: { $0.rawValue == weekday }) &&
            (calendar.component(.hour, from: reminder.time) > hour || 
            (calendar.component(.hour, from: reminder.time) == hour && 
             calendar.component(.minute, from: reminder.time) > minute))
        }
        
        if let closest = todayReminders.min(by: { 
            calendar.dateComponents([.hour, .minute], from: $0.time).timeInMinutes() <
            calendar.dateComponents([.hour, .minute], from: $1.time).timeInMinutes() 
        }) {
            return closest
        }
        
        // If no reminders for today, find the next upcoming day
        var nextDay = weekday
        var daysChecked = 0
        
        while daysChecked < 7 {
            nextDay = nextDay % 7 + 1  // Move to next day, wrapping from 7 to 1
            daysChecked += 1
            
            let nextDayReminders = reminders.filter { reminder in
                reminder.isEnabled && reminder.days.contains(where: { $0.rawValue == nextDay })
            }
            
            if let earliest = nextDayReminders.min(by: { 
                calendar.dateComponents([.hour, .minute], from: $0.time).timeInMinutes() <
                calendar.dateComponents([.hour, .minute], from: $1.time).timeInMinutes() 
            }) {
                return earliest
            }
        }
        
        return nil
    }
    
    // MARK: - Debug Methods
    
    /// Debug method to check if default 9pm reminder is properly scheduled
    func checkDefaultReminderStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("🔔 Notification Authorization Status: \(settings.authorizationStatus.rawValue)")
            
            UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
                guard let self = self else { return }
                
                print("📋 Total pending notifications: \(requests.count)")
                
                if let defaultRequest = requests.first(where: { $0.identifier == self.defaultReminderID }) {
                    print("✅ Default 9pm reminder found!")
                    print("📧 Title: \(defaultRequest.content.title)")
                    print("📧 Body: \(defaultRequest.content.body)")
                    
                    if let calendarTrigger = defaultRequest.trigger as? UNCalendarNotificationTrigger {
                        print("⏰ Trigger components: \(calendarTrigger.dateComponents)")
                        if let nextFireDate = calendarTrigger.nextTriggerDate() {
                            print("📅 Next fire date: \(nextFireDate)")
                            print("⏱️ Time until next fire: \(nextFireDate.timeIntervalSinceNow) seconds")
                        }
                        print("🔄 Repeats: \(calendarTrigger.repeats)")
                    }
                } else {
                    print("❌ Default 9pm reminder NOT found in pending notifications!")
                    print("📋 All notification identifiers:")
                    for request in requests {
                        print("  - \(request.identifier)")
                    }
                }
            }
        }
    }
}

extension DateComponents {
    func timeInMinutes() -> Int {
        (self.hour ?? 0) * 60 + (self.minute ?? 0)
    }
}

extension Color {
    init(named: String) {
        switch named.lowercased() {
        case "red":
            self = .red
        case "blue":
            self = .blue
        case "green":
            self = .green
        case "yellow":
            self = .yellow
        case "orange":
            self = .orange
        case "purple":
            self = .purple
        case "pink":
            self = .pink
        case "indigo":
            self = .indigo
        case "teal":
            self = .teal
        default:
            self = .primary
        }
    }
} 

import Foundation
import UserNotifications
import CoreData
import SwiftUI

public class NotificationManager {
    public static let shared = NotificationManager()
    
    private init() {}
    
    // Add centralized permission checking
    public func shouldRequestPermissions() -> Bool {
        return !UserDefaults.standard.bool(forKey: "hasRequestedNotifications")
    }
    
    public func requestAuthorization() {
        // Only request if not already requested
        guard shouldRequestPermissions() else {
            print("🔔 Notifications already requested, skipping duplicate request")
            return
        }
        
        // Ensure user is signed in before showing notification permission
        guard AuthManager.shared.isSignedIn else {
            print("🔔 Deferring notification permission until after login")
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
            UserDefaults.standard.set(granted, forKey: "notificationsEnabled")
            
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            }
        }
    }
    
    public func scheduleNotification(for transaction: NSManagedObject) {
        guard let reminderDate = transaction.value(forKey: "reminderDate") as? Date else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Transaction Reminder"
        
        let amount = transaction.value(forKey: "amount") as? Double ?? 0
        let note = transaction.value(forKey: "note") as? String ?? "Transaction"
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formattedAmount = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        
        content.body = "\(note) of \(formattedAmount) is due"
        content.sound = .default
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "transaction-\(transaction.value(forKey: "id") as? UUID ?? UUID())",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    public func cancelNotification(for transaction: NSManagedObject) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["transaction-\(transaction.value(forKey: "id") as? UUID ?? UUID())"]
        )
    }
} 

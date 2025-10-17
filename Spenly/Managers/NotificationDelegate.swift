import UserNotifications
import UIKit

// Add notification name extensions
extension Notification.Name {
    static let dailyReminderTapped = Notification.Name("dailyReminderTapped")
    static let transactionReminderTapped = Notification.Name("transactionReminderTapped")
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground, but don't use badges
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification taps based on identifier
        let identifier = response.notification.request.identifier
        
        if identifier == "default-daily-reminder" {
            // Handle daily reminder tap
            NotificationCenter.default.post(name: .dailyReminderTapped, object: nil)
        } else if identifier.hasPrefix("reminder-") {
            // Handle transaction reminder tap
            NotificationCenter.default.post(name: .transactionReminderTapped, object: nil)
        }
        
        completionHandler()
    }
} 

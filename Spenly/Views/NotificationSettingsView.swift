import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var notificationStatus: NotificationStatus = .checking
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    enum NotificationStatus {
        case checking
        case enabled
        case disabled
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notification Settings")
                            .font(selectedFont.font(size: 22, bold: true))
                        
                        Text("Stay updated with important information about your finances")
                            .font(selectedFont.font(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    
                    // Main Content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Status Card
                            VStack(alignment: .leading, spacing: 12) {
                                // Section Title
                                HStack(spacing: 6) {
                                    Image(systemName: "bell.badge")
                                        .foregroundColor(.blue)
                                    Text("Notification Status")
                                        .font(selectedFont.font(size: 16, bold: true))
                                }
                                
                                if notificationStatus == .checking {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .padding()
                                        Spacer()
                                    }
                                } else {
                                    HStack {
                                        Image(systemName: notificationStatus == .enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(notificationStatus == .enabled ? .green : .red)
                                            .font(.system(size: 20))
                                        
                                        Text(notificationStatus == .enabled ? "Notifications are enabled" : "Notifications are disabled")
                                            .font(selectedFont.font(size: 15))
                                            .foregroundColor(notificationStatus == .enabled ? .green : .secondary)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            
                            // Notification Types Card
                            VStack(alignment: .leading, spacing: 12) {
                                // Section Title
                                HStack(spacing: 6) {
                                    Image(systemName: "list.bullet")
                                        .foregroundColor(.blue)
                                    Text("Notification Types")
                                        .font(selectedFont.font(size: 16, bold: true))
                                }
                                
                                // Notification Types
                                VStack(alignment: .leading, spacing: 15) {
                                    NotificationTypeRow(
                                        icon: "calendar.badge.clock",
                                        title: "Transaction Reminders",
                                        description: "Get notified when transactions are due"
                                    )
                                    
                                    Divider()
                                    
                                    NotificationTypeRow(
                                        icon: "chart.pie.fill",
                                        title: "Budget Alerts",
                                        description: "Receive alerts when reaching spending limits"
                                    )
                                    
                                    Divider()
                                    
                                    NotificationTypeRow(
                                        icon: "dollarsign.circle.fill",
                                        title: "Monthly Summary",
                                        description: "Get monthly spending reports"
                                    )
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            
                            // Action Button
                            Button {
                                authManager.openNotificationSettings()
                            } label: {
                                HStack {
                                    Image(systemName: notificationStatus == .enabled ? "gear" : "bell.badge.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .padding(.trailing, 10)
                                    
                                    Text(notificationStatus == .enabled ? "Manage Notification Settings" : "Enable Notifications")
                                        .font(selectedFont.font(size: 16, bold: true))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            }
                            
                            // Adding some blank space at the bottom
                            Color.clear.frame(height: 30)
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            checkNotificationStatus()
        }
    }
    
    private func checkNotificationStatus() {
        // Set initial state
        notificationStatus = .checking
        
        // Check current status
        authManager.checkNotificationStatus { authorized in
            DispatchQueue.main.async {
                notificationStatus = authorized ? .enabled : .disabled
            }
        }
    }
}

struct NotificationTypeRow: View {
    let icon: String
    let title: String
    let description: String
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.blue)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(selectedFont.font(size: 15, bold: true))
                
                Text(description)
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView()
            .environmentObject(AuthManager.shared)
    }
} 

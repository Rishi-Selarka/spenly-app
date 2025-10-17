import SwiftUI
import CoreData
import UniformTypeIdentifiers
import UserNotifications
import CloudKit
import UIKit
import GoogleMobileAds
import MessageUI

enum AppFont: String, CaseIterable, Identifiable {
    // System Fonts
    case system = "System"
    
    // Sans-Serif Fonts (Modern & Clean)
    case helveticaNeue = "Helvetica Neue"
    case avenir = "Avenir"
    case futura = "Futura"
    case sfPro = "SF Pro"
    case gillSans = "Gill Sans"
    case avenirNext = "Avenir Next"
    case arialMT = "Arial"
    case verdana = "Verdana"
    case tahoma = "Tahoma"
    
    // Serif Fonts (Traditional & Elegant)
    case optima = "Optima"
    case didot = "Didot"
    case hoeflerText = "Hoefler Text"
    case cochin = "Cochin"
    case baskerville = "Baskerville"
    case georgia = "Georgia"
    case palatino = "Palatino"
    case timesNewRoman = "Times New Roman"
    case bodoni72 = "Bodoni 72"
    case charter = "Charter"
    
    // Display & Decorative
    case copperplate = "Copperplate"
    case snellRoundhand = "Snell Roundhand"
    case papyrus = "Papyrus"
    case zapfino = "Zapfino"
    case partyLET = "Party LET"
    
    // Modern Creative
    case rockwell = "Rockwell"
    case americanTypewriter = "American Typewriter"
    case courierNew = "Courier New"
    case menlo = "Menlo"
    case zapfDingbats = "Zapf Dingbats"
    
    // Casual & Handwritten
    case markerFelt = "Marker Felt"
    case noteworthy = "Noteworthy"
    case chalkboard = "Chalkboard SE"
    case bradleyHand = "Bradley Hand"
    case kailasa = "Kailasa"
    case academyEngravedLET = "Academy Engraved LET"
    case appleSDGothicNeo = "Apple SD Gothic Neo"
    case damascus = "Damascus"
    case gujarati = "Gujarati Sangam MN"
    case geezaPro = "Geeza Pro"
    
    var id: String { self.rawValue }
    
    var isPremium: Bool {
        // System font is free, all others require premium
        return self != .system
    }
    
    func font(size: CGFloat = 17, bold: Bool = false, italic: Bool = false) -> Font {
        switch self {
        case .system:
            var font = Font.system(size: size)
            if bold { font = font.weight(.bold) }
            if italic { font = font.italic() }
            return font
            
        case .helveticaNeue:
            let styleName = getFontStyleName("HelveticaNeue", bold: bold, italic: italic)
            return .custom(styleName, size: size)
            
        case .avenir:
            let styleName = getFontStyleName("Avenir", bold: bold, italic: italic, 
                boldVariant: "Heavy", italicVariant: "Oblique")
            return .custom(styleName, size: size)
            
        case .sfPro:
            let styleName = getFontStyleName("SFProText", bold: bold, italic: italic)
            return .custom(styleName, size: size)
            
        case .georgia:
            let styleName = getFontStyleName("Georgia", bold: bold, italic: italic)
            return .custom(styleName, size: size)
            
        case .palatino:
            let styleName = getFontStyleName("Palatino", bold: bold, italic: italic)
            return .custom(styleName, size: size)
            
        case .timesNewRoman:
            let styleName = getFontStyleName("TimesNewRoman", bold: bold, italic: italic)
            return .custom(styleName, size: size)
            
        // Add specific handling for other fonts that support styles
        default:
            // Try standard style naming conventions
            let baseName = self.rawValue
            let styleName = getFontStyleName(baseName, bold: bold, italic: italic)
            return .custom(styleName, size: size)
        }
    }
    
    private func getFontStyleName(_ baseName: String, bold: Bool, italic: Bool, 
        boldVariant: String = "Bold", italicVariant: String = "Italic") -> String {
        
        // Try different style combinations
        let possibleNames: [String] = {
            if bold && italic {
                return [
                    "\(baseName)-\(boldVariant)\(italicVariant)",
                    "\(baseName)-\(boldVariant)Oblique",
                    "\(baseName) \(boldVariant) \(italicVariant)",
                    "\(baseName)\(boldVariant)\(italicVariant)",
                    "\(baseName)-\(boldVariant)", // Fallback to just bold if both not available
                    baseName
                ]
            } else if bold {
                return [
                    "\(baseName)-\(boldVariant)",
                    "\(baseName) \(boldVariant)",
                    "\(baseName)\(boldVariant)",
                    baseName
                ]
            } else if italic {
                return [
                    "\(baseName)-\(italicVariant)",
                    "\(baseName) \(italicVariant)",
                    "\(baseName)\(italicVariant)",
                    "\(baseName)-Oblique",
                    "\(baseName) Oblique",
                    "\(baseName)Oblique",
                    baseName
                ]
            }
            return [baseName]
        }()
        
        // Return the first available font name
        return possibleNames.first { UIFont(name: $0, size: 12) != nil } ?? baseName
    }
    
    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .sfPro:
            return "SF Pro"
        case .timesNewRoman:
            return "Times New Roman"
        case .appleSDGothicNeo:
            return "Apple SD Gothic Neo"
        default:
            return self.rawValue
        }
    }
    
    var category: String {
        switch self {
        case .system:
            return "System"
        case .helveticaNeue, .avenir, .futura, .sfPro, .gillSans, .avenirNext, .arialMT, .verdana, .tahoma:
            return "Sans-Serif"
        case .optima, .didot, .hoeflerText, .cochin, .baskerville, .georgia, .palatino, .timesNewRoman, .bodoni72, .charter:
            return "Serif"
        case .copperplate, .snellRoundhand, .papyrus, .zapfino, .partyLET:
            return "Display"
        case .rockwell, .americanTypewriter, .courierNew, .menlo, .zapfDingbats:
            return "Modern"
        case .markerFelt, .noteworthy, .chalkboard, .bradleyHand, .kailasa, .academyEngravedLET, .appleSDGothicNeo, .damascus, .gujarati, .geezaPro:
            return "Casual"
        }
    }
}

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var iapManager = IAPManager.shared
    @AppStorage("selectedCurrency") private var selectedCurrency: Currency = .usd
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("showCalculator") private var showCalculator = true
    @AppStorage("showCurrencyRates") private var showCurrencyRates = true
    @AppStorage("showDemoDataButton") private var showDemoDataButton = true
    @AppStorage("templatesEnabled") private var templatesEnabled = true
    @AppStorage("aiEnabled") private var aiEnabled = true
    @State private var showingExportSheet = false
    @State private var showingPremiumSheet = false
    @State private var showingResetAlert = false
    @State private var showingLogoutAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var showAccountDeletionSuccess = false
    @State private var showNotificationSettingsAlert = false
    
    // CloudKit alert state
    @State private var showingCloudKitSignInAlert = false
    @State private var showingCloudKitUnavailableAlert = false
    @State private var showingCloudKitErrorAlert = false
    @State private var cloudKitErrorMessage: String = ""
    @State private var hasAppearedOnce = false
    // Share App
    @State private var showingShareAppSheet = false
    private var shareAppMessage: String {
        "Hey! I use Spenly — super easy and intuitive for managing money. Give it a try!\n\nApp Store: https://apps.apple.com/in/app/spenly/id6747989825"
    }
    // Feedback
    @State private var showingMailComposer = false
    @State private var mailComposeResultMessage: String = ""
    @StateObject private var medalManager = MedalManager.shared
    @State private var showPremium = false
    
    var body: some View {
        NavigationView {
            List {
                // Premium banner below the large Settings title
                premiumBanner

                // Account Section
                Section(header: Text("Account")) {
                    NavigationLink(destination: AccountSettingsView()) {
                        SettingsRow(
                            icon: "person.circle.fill",
                            iconColor: .blue,
                            title: "Account",
                            subtitle: accountManager.currentAccount?.name ?? "Default Account"
                        )
                    }
                    
                    // Account Transfer Feature
                    NavigationLink(destination: AccountTransferView()) {
                        SettingsRow(
                            icon: "arrow.left.arrow.right.circle.fill",
                            iconColor: .green,
                            title: "Account Transfer",
                            subtitle: "Transfer money between accounts"
                        )
                    }
                    
                    if authManager.isSignedIn && !authManager.isGuest {
                        CloudKitSyncToggle(showingCloudKitSignInAlert: $showingCloudKitSignInAlert)
                            .environmentObject(cloudKitSyncManager)
                    }

                    // Share Spenly
                    Button(action: { showingShareAppSheet = true }) {
                        SettingsRow(
                            icon: "square.and.arrow.up.fill",
                            iconColor: .blue,
                            title: "Share Spenly",
                            subtitle: "Invite your friends to Spenly"
                        )
                    }
                }
                
                // Appearance Section
                Section(header: Text("Appearance")) {
                    NavigationLink {
                        ThemeSelectionView(selectedTheme: $themeManager.selectedTheme)
                    } label: {
                        HStack {
                            SettingsRow(
                                icon: "paintbrush.fill",
                                iconColor: .purple,
                                title: "Theme",
                                subtitle: themeManager.selectedTheme.rawValue
                            )
                            
                            if !iapManager.isPremiumUnlocked {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                    
                    NavigationLink {
                        FontSelectionView(selectedFont: $selectedFont)
                    } label: {
                        HStack {
                            SettingsRow(
                                icon: "textformat",
                                iconColor: .orange,
                                title: "Font",
                                subtitle: selectedFont.rawValue
                            )
                            
                            if !iapManager.isPremiumUnlocked {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                    
                    NavigationLink {
                        CurrencySelectionView(selectedCurrency: $selectedCurrency)
                    } label: {
                        HStack(spacing: 12) {
                            // Custom flag icon in a circle
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.2))
                                    .frame(width: 30, height: 30)
                                
                                Text(selectedCurrency.flag)
                                    .font(.system(size: 16))
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Currency")
                                    .font(.system(size: 17))
                                Text("\(selectedCurrency.code) - \(selectedCurrency.symbol)")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Categories moved into Settings > Appearance
                    NavigationLink(destination: CategoriesView()) {
                        SettingsRow(
                            icon: "folder.fill",
                            iconColor: .blue,
                            title: "Categories",
                            subtitle: "Manage categories"
                        )
                    }
                }
                
                // Preferences Section
                Section(header: Text("Preferences")) {
                    CarryOverBalanceToggle()
                    
                    Toggle(isOn: $showCalculator) {
                        SettingsRow(
                            icon: "plusminus.circle.fill",
                            iconColor: .orange,
                            title: "Show Calculator",
                            subtitle: "Display calculator when entering transaction amount"
                        )
                    }
                    .tint(themeManager.getAccentColor(for: colorScheme))
                    
                    Toggle(isOn: $showCurrencyRates) {
                        SettingsRow(
                            icon: "dollarsign.circle.fill",
                            iconColor: .green,
                            title: "Global Rates Widget",
                            subtitle: "Show currency exchange rates on home screen"
                        )
                    }
                    .tint(themeManager.getAccentColor(for: colorScheme))
                    
                    Toggle(isOn: $showDemoDataButton) {
                        SettingsRow(
                            icon: "sparkles",
                            iconColor: .yellow,
                            title: "Show Demo Data Button",
                            subtitle: "Show demo data button in HomeView"
                        )
                    }
                    .tint(themeManager.getAccentColor(for: colorScheme))
                    
                    Toggle(isOn: $templatesEnabled) {
                        SettingsRow(
                            icon: "doc.text.below.ecg.fill",
                            iconColor: .purple,
                            title: "Transaction Templates",
                            subtitle: "Quick shortcuts for common transactions"
                        )
                    }
                    .tint(themeManager.getAccentColor(for: colorScheme))
                    
                    Toggle(isOn: $aiEnabled) {
                        SettingsRow(
                            icon: "brain.head.profile",
                            iconColor: .cyan,
                            title: "Spenly AI",
                            subtitle: "Intelligent financial assistant powered by Apple Intelligence"
                        )
                    }
                    .tint(themeManager.getAccentColor(for: colorScheme))
                    
                    NavigationLink {
                        ContactManagementView()
                            .environment(\.managedObjectContext, viewContext)
                            .environmentObject(themeManager)
                    } label: {
                        SettingsRow(
                            icon: "person.text.rectangle",
                            iconColor: themeManager.getAccentColor(for: colorScheme),
                            title: "Manage Contacts",
                            subtitle: "Add, edit, and organize payees and payers"
                        )
                    }
                    
                    NavigationLink(destination: ReminderSettingsView()) {
                        SettingsRow(
                            icon: "bell.fill",
                            iconColor: .orange,
                            title: "Reminders",
                            subtitle: "Manage transaction reminders"
                        )
                    }
                    
                    NavigationLink(destination: NotificationSettingsView()) {
                        SettingsRow(
                            icon: "bell.badge.fill",
                            iconColor: .blue,
                            title: "Notification Settings",
                            subtitle: "Manage app notification permissions"
                        )
                    }
                }
                
                // Data Management Section
                Section(header: Text("Data Management")) {
                    Button {
                        if iapManager.isPremiumUnlocked {
                            showingExportSheet = true
                        } else {
                            showingPremiumSheet = true
                        }
                    } label: {
                        HStack {
                            SettingsRow(
                                icon: "square.and.arrow.up.fill",
                                iconColor: .blue,
                                title: "Export Data",
                                subtitle: "Export transactions to PDF or CSV"
                            )
                            
                            if !iapManager.isPremiumUnlocked {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .padding(.trailing, 8)
                            }
                        }
                    }
                    
                    Button(action: { showingResetAlert = true }) {
                        SettingsRow(
                            icon: "trash.fill",
                            iconColor: .red,
                            title: "Reset Data",
                            subtitle: "Delete all transactions"
                        )
                    }
                }
                
                // Legal Section
                Section(header: Text("Legal Services")) {
                    Button(action: { 
                        if let url = URL(string: "https://rishi-selarka.github.io/spenly-legal/terms-of-service") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        SettingsRow(
                            icon: "doc.text.fill",
                            iconColor: .blue,
                            title: "Terms of Service",
                            subtitle: "View our terms of service"
                        )
                    }
                    
                    Button(action: { 
                        if let url = URL(string: "https://rishi-selarka.github.io/spenly-legal/privacy-policy") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        SettingsRow(
                            icon: "hand.raised.fill",
                            iconColor: .blue,
                            title: "Privacy Policy",
                            subtitle: "View our privacy policy"
                        )
                    }
                }

                // Feedback Section
                Section(header: Text("Feedback")) {
                    Button(action: {
                        if let url = URL(string: "itms-apps://itunes.apple.com/app/id6747989825?action=write-review") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        SettingsRow(
                            icon: "star.fill",
                            iconColor: .yellow,
                            title: "Rate Spenly",
                            subtitle: "Share your experience"
                        )
                    }

                    Button(action: { showingMailComposer = true }) {
                        SettingsRow(
                            icon: "envelope.fill",
                            iconColor: .green,
                            title: "Write a Feedback",
                            subtitle: "Report an issue or suggest a feature"
                        )
                    }
                }
                
                // Delete Account Section (for Apple ID users only)
                if authManager.isSignedIn && !authManager.isGuest {
                    Section {
                        Button(action: { showingDeleteAccountAlert = true }) {
                            SettingsRow(
                                icon: "person.crop.circle.badge.minus",
                                iconColor: .red,
                                title: "Delete Account",
                                subtitle: "Remove all data and account access"
                            )
                        }
                    }
                    .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete", role: .destructive) {
                            showingDeleteAccountConfirmation = true
                        }
                    } message: {
                        Text("⚠️ Warning: This will permanently delete your account and all associated data from both your device and iCloud.\n\nYour data CANNOT be recovered after deletion.")
                    }
                    .alert("Final Confirmation", isPresented: $showingDeleteAccountConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Yes, Delete Everything", role: .destructive) {
                            // Proceed with account deletion
                            authManager.deleteAccount { success in
                                if success {
                                    showAccountDeletionSuccess = true
                                } else {
                                    // Handle error
                                    print("Failed to delete account")
                                }
                            }
                        }
                    } message: {
                        Text("Are you absolutely sure? All your financial data, transactions, and settings will be permanently deleted from both your device and iCloud and cannot be recovered.\n\nThis includes all data synced to your Apple devices.")
                    }
                    .alert("Account Deleted", isPresented: $showAccountDeletionSuccess) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Your account has been successfully deleted along with all associated data from both your device and iCloud. All synced data has been removed from Apple's servers.")
                    }
                }
                
                // Small Centered Sign Out Button
                if authManager.isSignedIn {
                    HStack {
                        Spacer()
                        Button(action: { showingLogoutAlert = true }) {
                            Text(authManager.isGuest ? "Sign Out as Guest" : "Sign Out")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 20)
                                .background(
                                    Capsule()
                                        .fill(Color.red)
                                )
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .alert(authManager.isGuest ? "Sign Out as Guest" : "Sign Out", isPresented: $showingLogoutAlert) {
                            Button("Cancel", role: .cancel) { }
                            Button("Sign Out", role: .destructive) {
                                authManager.signOut()
                            }
                        } message: {
                            if authManager.isGuest {
                                Text("Warning: If you sign out as a guest, all your data will be lost and cannot be recovered. Are you sure you want to sign out?")
                            } else {
                                Text("You will be signed out of your Apple ID. Your data will remain synced to your account. You can sign in again at any time.")
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        Text(Bundle.main.appVersionString)
                            .font(.caption)
                            .foregroundColor(.gray)
                        if let m = medalManager.currentMedal(for: accountManager.currentAccount?.id) {
                            Image(systemName: m.name)
                                .foregroundColor(m.color)
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingShareAppSheet) {
                ShareSheet(activityItems: [shareAppMessage])
            }
            .sheet(isPresented: $showingMailComposer) {
                MailView(
                    recipients: ["teamspenlyapp@gmail.com"],
                    subject: "Spenly Feedback",
                    body: "Hey Spenly team,\n\nI wanted to share some feedback...",
                    isHTML: false
                )
            }
            .sheet(isPresented: $showPremium) {
                PremiumView()
            }
            .sheet(isPresented: $showingExportSheet, onDismiss: {
                // Handle any cleanup if needed
            }) {
                ExportSettingsView()
                    .environmentObject(accountManager)
                    .environmentObject(themeManager)
            }
            .sheet(isPresented: $showingPremiumSheet) {
                PremiumView()
            }
            .alert("Reset Data", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetAllData()
                }
            } message: {
                Text("This will permanently delete all transactions in '\(accountManager.currentAccount?.name ?? "current")' account. Your categories and settings will be preserved. This action cannot be undone.")
            }
            .alert("Notifications", isPresented: $showNotificationSettingsAlert) {
                Button("Settings", role: .none) {
                    authManager.openNotificationSettings()
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("Notifications are already enabled for this app. You can manage notification settings in the iOS Settings app.")
            }
        }
        .scrollContentBackground(.hidden)
        .overlay(alignment: .top) {
            LinearGradient(
                gradient: Gradient(colors: [
                    themeManager.getAccentColor(for: colorScheme).opacity(0.16),
                    themeManager.getAccentColor(for: colorScheme).opacity(0.06),
                    .clear
                ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 210)
                .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
        .onAppear {
            if !hasAppearedOnce {
                hasAppearedOnce = true
            setupCloudKitNotifications()
            }
        }
        .onDisappear {
            // Clean up notification observers to prevent memory leaks
            NotificationCenter.default.removeObserver(self)
        }
        .onReceive(cloudKitSyncManager.$syncStatus) { newStatus in
            // Monitor status changes
            switch newStatus {
            case .error(let message):
                // Check the message to determine the specific error type
                if message.contains("not signed in") {
                    showingCloudKitSignInAlert = true
                } else if message.contains("unavailable") || message.contains("restricted") {
                    showingCloudKitUnavailableAlert = true
                } else {
                    cloudKitErrorMessage = "iCloud sync error: \(message)"
                    showingCloudKitErrorAlert = true
                }
            default:
                break
            }
        }
        // CloudKit alerts moved out of the toggle and to the top level view
        .alert("iCloud Sign In Required", isPresented: $showingCloudKitSignInAlert) {
            Button("Cancel", role: .cancel) {
                if case .error(let message) = cloudKitSyncManager.syncStatus, message.contains("not signed in") {
                    cloudKitSyncManager.isSyncEnabled = false
                }
            }
            Button("Open Settings", role: .none) {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        } message: {
            Text("You need to sign in to iCloud in your device settings to enable sync.")
        }
        .alert("iCloud Unavailable", isPresented: $showingCloudKitUnavailableAlert) {
            Button("OK", role: .cancel) {
                if case .error(let message) = cloudKitSyncManager.syncStatus, 
                   message.contains("unavailable") || message.contains("restricted") {
                    cloudKitSyncManager.isSyncEnabled = false
                }
            }
        } message: {
            Text("iCloud sync is currently unavailable. Please check your internet connection and iCloud settings.")
        }
        .alert("iCloud Error", isPresented: $showingCloudKitErrorAlert) {
            Button("OK", role: .cancel) {
                // Reset toggle on error
                cloudKitSyncManager.isSyncEnabled = false
            }
        } message: {
            Text(cloudKitErrorMessage)
        }
        .onAppear { MedalManager.shared.refresh(for: accountManager.currentAccount?.id) }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MedalProgressUpdated"))) { _ in
            MedalManager.shared.refresh(for: accountManager.currentAccount?.id)
        }
    }

    // MARK: - Premium Banner
    private var premiumBanner: some View {
        Button(action: { showPremium = true }) {
            ZStack(alignment: .leading) {
                // Translucent multi-gradient background (no glass material)
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.purple.opacity(0.36), location: 0.0),
                                    .init(color: Color.pink.opacity(0.34), location: 0.28),
                                    .init(color: Color.blue.opacity(0.34), location: 0.62),
                                    .init(color: Color.cyan.opacity(0.36), location: 1.0)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            AngularGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.10), location: 0.0),
                                    .init(color: .clear, location: 0.25),
                                    .init(color: Color.white.opacity(0.06), location: 0.5),
                                    .init(color: .clear, location: 0.75),
                                    // Match first & last stop to avoid conic seam line
                                    .init(color: Color.white.opacity(0.10), location: 1.0)
                                ]),
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            )
                            .rotationEffect(.degrees(25))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .blendMode(.screen)
                            .opacity(0.45)
                            .allowsHitTesting(false)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        themeManager.getAccentColor(for: colorScheme).opacity(0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        Image(systemName: "sparkles")
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spenly Premium")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Tap to learn more")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Spacer()
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 12, trailing: 16))
        .listRowBackground(Color.clear)
    }
    
    // Helper computed properties for sync status display
    private var syncDetailText: String {
        let statusText = cloudKitSyncManager.syncStatus.description
        
        if cloudKitSyncManager.isSyncEnabled {
            if let lastSync = cloudKitSyncManager.lastSyncDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return "\(statusText)\n\nLast synced: \(formatter.string(from: lastSync))\n\nYour data is being synced across all your Apple devices."
            } else {
                return "\(statusText)\n\nYour data will be synced across all your Apple devices."
            }
        } else {
            return "\(statusText)\n\nPlease check your iCloud settings to enable sync."
        }
    }
    
    private func resetAllData() {
        guard let currentAccount = accountManager.currentAccount else { return }
        
        // Store the account ID before reset
        let accountId = currentAccount.id
        
        // First, find all carry-over transactions to mark them as deleted
        let carryOverFetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        carryOverFetchRequest.predicate = NSPredicate(format: "account == %@ AND isCarryOver == YES", currentAccount)
        
        if let carryOvers = try? viewContext.fetch(carryOverFetchRequest) {
            for transaction in carryOvers {
                if let date = transaction.date {
                    // Mark each carry-over as manually deleted
                    CarryOverManager.shared.markCarryOverDeleted(for: date, account: currentAccount)
                }
            }
        }
        
        // First, decrement contact usage for all transactions being deleted
        let contactFetchRequest: NSFetchRequest<Transaction> = Transaction.fetchRequest()
        contactFetchRequest.predicate = NSPredicate(format: "account == %@", currentAccount)
        contactFetchRequest.propertiesToFetch = ["contact"]
        
        if let transactionsToDelete = try? viewContext.fetch(contactFetchRequest) {
            for transaction in transactionsToDelete {
                if let contact = transaction.contact {
                    ContactManager.shared.decrementUsageCount(contact: contact, context: viewContext)
                }
            }
        }
        
        // Now delete all transactions for the current account
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Transaction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "account == %@", currentAccount)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        do {
            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
            
            // Save changes first
            try viewContext.save()
            
            // Reset the view context to ensure UI updates
            viewContext.reset()
            
            // Reload the current account after reset to maintain selection
            if let accountId = accountId {
                let accountFetchRequest = Account.fetchRequest()
                accountFetchRequest.predicate = NSPredicate(format: "id == %@", accountId as CVarArg)
                
                if let reloadedAccount = try? viewContext.fetch(accountFetchRequest).first {
                    DispatchQueue.main.async {
                        self.accountManager.currentAccount = reloadedAccount
                        print("✅ Restored current account after reset: \(reloadedAccount.name ?? "unknown")")
                    }
                }
            }
            
            // Force refresh the UI
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSManagedObjectContext.didSaveObjectsNotification, object: nil)
            }
        } catch {
            print("Failed to reset data: \(error)")
        }
    }
    
    private func setupCloudKitNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitSignInRequired"),
            object: nil,
            queue: .main
        ) { notification in
            self.showingCloudKitSignInAlert = true
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitUnavailable"),
            object: nil,
            queue: .main
        ) { notification in
            self.showingCloudKitUnavailableAlert = true
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitError"),
            object: nil,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?["error"] as? Error {
                self.cloudKitErrorMessage = "iCloud sync error: \(error.localizedDescription)"
            }
            self.showingCloudKitErrorAlert = true
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitSimulatorAlert"),
            object: nil,
            queue: .main
        ) { notification in
            self.cloudKitErrorMessage = "iCloud sync is not available in the simulator."
            self.showingCloudKitErrorAlert = true
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CloudKitSyncReset"),
            object: nil,
            queue: .main
        ) { notification in
            if let message = notification.userInfo?["message"] as? String {
                self.cloudKitErrorMessage = message
                self.showingCloudKitErrorAlert = true
            }
        }
    }
    
    private func removeCloudKitNotifications() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("CloudKitSignInRequired"),
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("CloudKitUnavailable"),
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("CloudKitError"), 
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("CloudKitSimulatorAlert"),
            object: nil
        )
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

enum Currency: String, CaseIterable, Identifiable {
    case usd, eur, gbp, jpy, aud, cad, inr
    case cny, hkd, sgd, chf, sek, nok, dkk
    case nzd, zar, brl, rub, mxn, ars
    case try_, krw, twd, thb, myr, idr
    case php, pkr, bdt, vnd, egp
    case ils, czk, pln, huf, ron
    case bgn, hrk, uah, aed, sar
    case qar, kwd, bhd, omr, jod
    case lkr, mmk, khr, lak, npr
    case all, amd, azn, bam, byn
    case gel, kzt, mdl, mkd, rsd
    
    var id: String { self.rawValue }
    
    var code: String {
        if self == .try_ {
            return "TRY"
        }
        return rawValue.uppercased()
    }
    
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy, .cny: return "¥"
        case .aud: return "A$"
        case .cad: return "C$"
        case .inr: return "₹"
        case .hkd: return "HK$"
        case .sgd: return "S$"
        case .chf: return "CHF"
        case .sek: return "kr"
        case .nok: return "kr"
        case .dkk: return "kr"
        case .nzd: return "NZ$"
        case .zar: return "R"
        case .brl: return "R$"
        case .rub: return "₽"
        case .mxn: return "Mex$"
        case .ars: return "AR$"
        case .try_: return "₺"
        case .krw: return "₩"
        case .twd: return "NT$"
        case .thb: return "฿"
        case .myr: return "RM"
        case .idr: return "Rp"
        case .php: return "₱"
        case .pkr: return "₨"
        case .bdt: return "৳"
        case .vnd: return "₫"
        case .egp: return "E£"
        case .ils: return "₪"
        case .czk: return "Kč"
        case .pln: return "zł"
        case .huf: return "Ft"
        case .ron: return "lei"
        case .bgn: return "лв"
        case .hrk: return "kn"
        case .uah: return "₴"
        case .aed: return "د.إ"
        case .sar: return "﷼"
        case .qar: return "ر.ق"
        case .kwd: return "د.ك"
        case .bhd: return ".د.ب"
        case .omr: return "ر.ع."
        case .jod: return "د.ا"
        case .lkr: return "රු"
        case .mmk: return "K"
        case .khr: return "៛"
        case .lak: return "₭"
        case .npr: return "رू"
        case .all: return "L"
        case .amd: return "֏"
        case .azn: return "₼"
        case .bam: return "KM"
        case .byn: return "Br"
        case .gel: return "₾"
        case .kzt: return "₸"
        case .mdl: return "L"
        case .mkd: return "ден"
        case .rsd: return "дин."
        }
    }
    
    var flag: String {
        switch self {
        case .usd: return "🇺🇸"
        case .eur: return "🇪🇺"
        case .gbp: return "🇬🇧"
        case .jpy: return "🇯🇵"
        case .aud: return "🇦🇺"
        case .cad: return "🇨🇦"
        case .inr: return "🇮🇳"
        case .cny: return "🇨🇳"
        case .hkd: return "🇭🇰"
        case .sgd: return "🇸🇬"
        case .chf: return "🇨🇭"
        case .sek: return "🇸🇪"
        case .nok: return "🇳🇴"
        case .dkk: return "🇩🇰"
        case .nzd: return "🇳🇿"
        case .zar: return "🇿🇦"
        case .brl: return "🇧🇷"
        case .rub: return "🇷🇺"
        case .mxn: return "🇲🇽"
        case .ars: return "🇦🇷"
        case .try_: return "🇹🇷"
        case .krw: return "🇰🇷"
        case .twd: return "🇹🇼"
        case .thb: return "🇹🇭"
        case .myr: return "🇲🇾"
        case .idr: return "🇮🇩"
        case .php: return "🇵🇭"
        case .pkr: return "🇵🇰"
        case .bdt: return "🇧🇩"
        case .vnd: return "🇻🇳"
        case .egp: return "🇪🇬"
        case .ils: return "🇮🇱"
        case .czk: return "🇨🇿"
        case .pln: return "🇵🇱"
        case .huf: return "🇭🇺"
        case .ron: return "🇷🇴"
        case .bgn: return "🇧🇬"
        case .hrk: return "🇭🇷"
        case .uah: return "🇺🇦"
        case .aed: return "🇦🇪"
        case .sar: return "🇸🇦"
        case .qar: return "🇶🇦"
        case .kwd: return "🇰🇼"
        case .bhd: return "🇧🇭"
        case .omr: return "🇴🇲"
        case .jod: return "🇯🇴"
        case .lkr: return "🇱🇰"
        case .mmk: return "🇲🇲"
        case .khr: return "🇰🇭"
        case .lak: return "🇱🇦"
        case .npr: return "🇳🇵"
        case .all: return "🇦🇱"
        case .amd: return "🇦🇲"
        case .azn: return "🇦🇿"
        case .bam: return "🇧🇦"
        case .byn: return "🇧🇾"
        case .gel: return "🇬🇪"
        case .kzt: return "🇰🇿"
        case .mdl: return "🇲🇩"
        case .mkd: return "🇲🇰"
        case .rsd: return "🇷🇸"
        }
    }
    
    var name: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .jpy: return "Japanese Yen"
        case .aud: return "Australian Dollar"
        case .cad: return "Canadian Dollar"
        case .inr: return "Indian Rupee"
        case .cny: return "Chinese Yuan"
        case .hkd: return "Hong Kong Dollar"
        case .sgd: return "Singapore Dollar"
        case .chf: return "Swiss Franc"
        case .sek: return "Swedish Krona"
        case .nok: return "Norwegian Krone"
        case .dkk: return "Danish Krone"
        case .nzd: return "New Zealand Dollar"
        case .zar: return "South African Rand"
        case .brl: return "Brazilian Real"
        case .rub: return "Russian Ruble"
        case .mxn: return "Mexican Peso"
        case .ars: return "Argentine Peso"
        case .try_: return "Turkish Lira"
        case .krw: return "South Korean Won"
        case .twd: return "New Taiwan Dollar"
        case .thb: return "Thai Baht"
        case .myr: return "Malaysian Ringgit"
        case .idr: return "Indonesian Rupiah"
        case .php: return "Philippine Peso"
        case .pkr: return "Pakistani Rupee"
        case .bdt: return "Bangladeshi Taka"
        case .vnd: return "Vietnamese Dong"
        case .egp: return "Egyptian Pound"
        case .ils: return "Israeli New Shekel"
        case .czk: return "Czech Koruna"
        case .pln: return "Polish Złoty"
        case .huf: return "Hungarian Forint"
        case .ron: return "Romanian Leu"
        case .bgn: return "Bulgarian Lev"
        case .hrk: return "Croatian Kuna"
        case .uah: return "Ukrainian Hryvnia"
        case .aed: return "UAE Dirham"
        case .sar: return "Saudi Riyal"
        case .qar: return "Qatari Riyal"
        case .kwd: return "Kuwaiti Dinar"
        case .bhd: return "Bahraini Dinar"
        case .omr: return "Omani Rial"
        case .jod: return "Jordanian Dinar"
        case .lkr: return "Sri Lankan Rupee"
        case .mmk: return "Myanmar Kyat"
        case .khr: return "Cambodian Riel"
        case .lak: return "Laotian Kip"
        case .npr: return "Nepalese Rupee"
        case .all: return "Albanian Lek"
        case .amd: return "Armenian Dram"
        case .azn: return "Azerbaijani Manat"
        case .bam: return "Bosnia-Herzegovina Mark"
        case .byn: return "Belarusian Ruble"
        case .gel: return "Georgian Lari"
        case .kzt: return "Kazakhstani Tenge"
        case .mdl: return "Moldovan Leu"
        case .mkd: return "Macedonian Denar"
        case .rsd: return "Serbian Dinar"
        }
    }
    
    var region: CurrencyRegion {
        switch self {
        case .usd, .cad:
            return .northAmerica
            
        case .eur, .gbp, .chf, .sek, .nok, .dkk, .czk, .pln, .huf, .ron, .bgn, .hrk, .uah, .rsd, .mkd, .mdl, .all, .bam, .byn:
            return .europe
            
        case .jpy, .cny, .krw, .twd, .sgd, .hkd, .myr, .idr, .php, .thb, .mmk, .khr, .lak, .vnd, .kzt, .gel, .azn, .amd:
            return .asia
            
        case .inr, .pkr, .bdt, .lkr, .npr:
            return .asia
            
        case .aed, .sar, .qar, .kwd, .bhd, .omr, .jod, .egp, .ils:
            return .middleEast
            
        case .aud, .nzd:
            return .oceania
            
        case .zar:
            return .africa
            
        case .brl, .mxn, .ars, .try_:
            return .latinAmerica
            
        default:
            return .all
        }
    }
}

extension Bundle {
    var appVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// New Views for Selection Screens
struct ThemeSelectionView: View {
    @Binding var selectedTheme: Theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @StateObject private var iapManager = IAPManager.shared
    @State private var showingPremiumSheet = false
    
    let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 170), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header text
                Text("Select a theme that matches your style")
                    .font(selectedFont.font(size: 16))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                // Banner ad placed below the header text (no space when premium)
                if !IAPManager.shared.isAdsRemoved {
                    AdBannerView(adPosition: .top, adPlacement: .settings)
                        .frame(height: 80)
                        .padding(.vertical, 16)
                }
                
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Theme.allCases) { theme in
                        ThemeCard(theme: theme, isSelected: theme == selectedTheme, isPremiumUnlocked: iapManager.isPremiumUnlocked)
                            .equatable()
                            .onTapGesture {
                                if theme.isPremium && !iapManager.isPremiumUnlocked {
                                    showingPremiumSheet = true
                                } else {
                                    withAnimation {
                                        selectedTheme = theme
                                        themeManager.setTheme(theme)
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal)
                // Prevent heavy implicit re-layout animations when content changes (e.g., ad loads)
                .transaction { $0.animation = nil }
                
            }
            .padding(.vertical)
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPremiumSheet) {
            PremiumView()
        }
    }
}

struct ThemeCard: View {
    let theme: Theme
    let isSelected: Bool
    let isPremiumUnlocked: Bool
    @Environment(\.colorScheme) private var colorScheme
}

extension ThemeCard: Equatable {
    static func == (lhs: ThemeCard, rhs: ThemeCard) -> Bool {
        lhs.theme == rhs.theme && lhs.isSelected == rhs.isSelected && lhs.isPremiumUnlocked == rhs.isPremiumUnlocked
    }
}

extension ThemeCard {
    var body: some View {
        VStack(spacing: 12) {
            // Theme color preview
            ZStack {
                // Dark mode background
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors(for: .dark).background)
                    .frame(height: 80)
                
                // UI elements preview
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(theme.colors(for: .dark).accent)
                            .frame(width: 18, height: 18)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.colors(for: .dark).secondaryBackground)
                            .frame(width: 70, height: 8)
                    }
                    
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.colors(for: .dark).secondaryBackground)
                            .frame(width: 35, height: 8)
                        
                        Circle()
                            .fill(theme.colors(for: .dark).accent)
                            .frame(width: 24, height: 24)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.colors(for: .dark).secondaryBackground)
                            .frame(width: 35, height: 8)
                    }
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors(for: .dark).accent.opacity(0.2))
                        .frame(height: 20)
                        .overlay(
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(theme.colors(for: .dark).accent)
                                    .frame(width: 6, height: 6)
                                Circle()
                                    .fill(theme.colors(for: .dark).accent)
                                    .frame(width: 6, height: 6)
                                Circle()
                                    .fill(theme.colors(for: .dark).accent)
                                    .frame(width: 6, height: 6)
                            }
                        )
                }
                .padding(.horizontal, 10)
            }
            
            // Theme name with premium badge
            HStack {
                Text(theme.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                
                    if theme.isPremium && !isPremiumUnlocked {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
            
            // Selected indicator
            if isSelected {
                Text("Selected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(theme.colors(for: .dark).accent)
                    .cornerRadius(12)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected 
                        ? theme.colors(for: .dark).accent
                        : Color.gray.opacity(0.2), 
                    lineWidth: isSelected ? 2 : 1
                )
        )
    }
}

struct AccountRow: View {
    @EnvironmentObject private var accountManager: AccountManager
    let account: Account
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(account.name ?? "Unnamed Account")
                if account.isDefault {
                    Text("Default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if accountManager.currentAccount?.id == account.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            accountManager.switchToAccount(account)
        }
    }
}

struct AppFontModifier: ViewModifier {
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    func body(content: Content) -> some View {
        content.font(selectedFont.font(size: 17))
    }
}

extension View {
    func appFont() -> some View {
        modifier(AppFontModifier())
    }
}

extension View {
    func transactionFont(size: CGFloat = 17) -> some View {
        modifier(TransactionFontModifier(size: size))
    }
}

struct TransactionFontModifier: ViewModifier {
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    let size: CGFloat
    
    func body(content: Content) -> some View {
        content.font(selectedFont.font(size: size))
    }
}

struct FontSelectionView: View {
    @Binding var selectedFont: AppFont
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var userFont: AppFont = .system
    @StateObject private var iapManager = IAPManager.shared
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showingPremiumSheet = false
    
    let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 16)
    ]
    
    var categories: [String] {
        var cats = ["All"]
        cats.append(contentsOf: AppFont.allCases.map { $0.category }.uniqued())
        return cats
    }
    
    var filteredFonts: [AppFont] {
        var fonts = AppFont.allCases
        
        // Filter by search text
        if !searchText.isEmpty {
            fonts = fonts.filter { $0.rawValue.lowercased().contains(searchText.lowercased()) }
        }
        
        // Filter by category
        if let category = selectedCategory, category != "All" {
            fonts = fonts.filter { $0.category == category }
        }
        
        return fonts
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search fonts", text: $searchText)
                }
                .padding(8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(10)
            }
            .padding()
            
            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(categories, id: \.self) { category in
                        Button {
                            withAnimation {
                                selectedCategory = category == "All" ? nil : category
                            }
                        } label: {
                            Text(category)
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill((selectedCategory == category || (category == "All" && selectedCategory == nil)) 
                                            ? themeManager.getAccentColor(for: colorScheme) : Color.black.opacity(0.06))
                                )
                                .foregroundColor((selectedCategory == category || (category == "All" && selectedCategory == nil)) 
                                    ? .white : .primary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 12)
            
            // Font grid
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if filteredFonts.isEmpty {
                        Text("No fonts match your search")
                            .font(userFont.font(size: 16))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredFonts) { font in
                                FontCard(font: font, isSelected: font == selectedFont, isPremiumUnlocked: iapManager.isPremiumUnlocked)
                                    .onTapGesture {
                                        if font.isPremium && !iapManager.isPremiumUnlocked {
                                            showingPremiumSheet = true
                                        } else {
                                            withAnimation {
                                                selectedFont = font
                                            }
                                        }
                                    }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Font")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPremiumSheet) {
            PremiumView()
        }
    }
}

struct FontCard: View {
    let font: AppFont
    let isSelected: Bool
    let isPremiumUnlocked: Bool
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            // Category tag
            HStack {
                Text(font.category)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(categoryColor(for: font.category).opacity(0.2))
                    .foregroundColor(categoryColor(for: font.category))
                    .cornerRadius(6)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)
            
            // Font preview area
            VStack(alignment: .leading, spacing: 8) {
                // Font name with premium badge
                HStack {
                    Text(font.displayName)
                        .font(font.font(size: 17, bold: true))
                        .lineLimit(1)
                    
                    if font.isPremium && !isPremiumUnlocked {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.bottom, 2)
                
                // Sample text
                Text("Abc 123")
                    .font(font.font(size: 22))
                
                Text("The quick brown fox jumps over the lazy dog")
                    .font(font.font(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    
                HStack(spacing: 4) {
                    Text("Bold")
                        .font(font.font(size: 12, bold: true))
                    
                    Text("Italic")
                        .font(font.font(size: 12, italic: true))
                }
                .foregroundColor(.secondary)
            }
            .frame(height: 105)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6).opacity(0.6))
            .cornerRadius(8)
            
            // Selected indicator
            if isSelected {
                Text("Selected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(themeManager.getAccentColor(for: colorScheme))
                    .cornerRadius(12)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? themeManager.getAccentColor(for: colorScheme) : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
    }
    
    private func categoryColor(for category: String) -> Color {
        switch category {
        case "System":
            return .purple
        case "Sans-Serif":
            return .blue
        case "Serif":
            return .green
        case "Display":
            return .orange
        case "Modern":
            return .red
        case "Casual":
            return .pink
        default:
            return .gray
        }
    }
}

// Extension to remove duplicates from arrays
extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// Add Currency Regions
enum CurrencyRegion: String, CaseIterable, Identifiable {
    case all
    case northAmerica
    case europe
    case asia
    case middleEast
    case oceania
    case africa
    case latinAmerica
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .northAmerica:
            return "North America"
        case .europe:
            return "Europe"
        case .asia:
            return "Asia"
        case .middleEast:
            return "Middle East"
        case .oceania:
            return "Oceania"
        case .africa:
            return "Africa"
        case .latinAmerica:
            return "Latin America"
        case .all:
            return "All Regions"
        }
    }
}

struct CurrencySelectionView: View {
    @Binding var selectedCurrency: Currency
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedRegion: CurrencyRegion? = nil
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 16)
    ]
    
    var regions: [CurrencyRegion] {
        var regions = [CurrencyRegion.all]
        regions.append(contentsOf: CurrencyRegion.allCases.filter { $0 != .all })
        return regions
    }
    
    var filteredCurrencies: [Currency] {
        var currencies = Currency.allCases
        
        // Filter by search text
        if !searchText.isEmpty {
            currencies = currencies.filter { currency in
                currency.rawValue.lowercased().contains(searchText.lowercased()) ||
                currency.symbol.lowercased().contains(searchText.lowercased()) ||
                currency.name.lowercased().contains(searchText.lowercased())
            }
        }
        
        // Filter by region
        if let region = selectedRegion, region != .all {
            currencies = currencies.filter { $0.region == region }
        }
        
        return currencies
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search currencies", text: $searchText)
                }
                .padding(8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(10)
            }
            .padding()
            
            // Region filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(regions, id: \.self) { region in
                        Button {
                            withAnimation {
                                selectedRegion = region == .all ? nil : region
                            }
                        } label: {
                            Text(region.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill((selectedRegion == region || (region == .all && selectedRegion == nil)) 
                                            ? themeManager.getAccentColor(for: colorScheme) : Color.black.opacity(0.06))
                                )
                                .foregroundColor((selectedRegion == region || (region == .all && selectedRegion == nil)) 
                                    ? .white : .primary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 12)
            
            // Currencies grid
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if filteredCurrencies.isEmpty {
                        Text("No currencies match your search")
                            .font(selectedFont.font(size: 16))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredCurrencies) { currency in
                                CurrencyCard(currency: currency, isSelected: currency == selectedCurrency)
                                    .equatable()
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedCurrency = currency }
                            }
                        }
                        .transaction { $0.animation = nil }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CurrencyCard: View {
    let currency: Currency
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    
}

extension CurrencyCard: Equatable {
    static func == (lhs: CurrencyCard, rhs: CurrencyCard) -> Bool {
        lhs.currency == rhs.currency && lhs.isSelected == rhs.isSelected
    }
}

extension CurrencyCard {
    var body: some View {
        VStack(spacing: 12) {
            // Region tag
            HStack {
                Text(currency.region.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(regionColor(for: currency.region).opacity(0.15))
                    )
                    .foregroundColor(regionColor(for: currency.region))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            
            // Currency preview
            VStack(spacing: 14) {
                // Symbol with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    regionColor(for: currency.region).opacity(0.3),
                                    regionColor(for: currency.region).opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Text(currency.flag)
                        .font(.system(size: 30))
                }
                // Remove extra shadows to reduce overdraw in large grids
                
                // Show currency symbol below flag
                Text(currency.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.top, -10)
                
                // Currency code with badge
                Text(currency.code)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.systemGray6).opacity(0.3))
                    )
                
                // Currency name
                Text(currency.name)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 36)
            }
            .padding(.vertical, 8)
            
            // Selected indicator
            if isSelected {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Selected")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            themeManager.getAccentColor(for: colorScheme),
                            themeManager.getAccentColor(for: colorScheme).opacity(0.85)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                // Remove chip shadow to reduce overdraw
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSelected 
                        ? themeManager.getAccentColor(for: colorScheme)
                        : Color.gray.opacity(0.15),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        // Removed expensive shadows for smoother scrolling
    }
    
    private func regionColor(for region: CurrencyRegion) -> Color {
        switch region {
        case .northAmerica:
            return .blue
        case .europe:
            return .green
        case .asia:
            return .red
        case .middleEast:
            return .orange
        case .oceania:
            return .purple
        case .africa:
            return .yellow
        case .latinAmerica:
            return .pink
        case .all:
            return .gray
        }
    }
}

// Add this after other view definitions
struct ThemedToggleStyle: ToggleStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            RoundedRectangle(cornerRadius: 16)
                .fill(configuration.isOn ? color : Color(.systemGray5))
                .frame(width: 50, height: 30)
                .overlay(
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1)
                        .frame(width: 26, height: 26)
                        .offset(x: configuration.isOn ? 10 : -10)
                )
                .animation(.spring(response: 0.2), value: configuration.isOn)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

struct CountBadge: View {
    let count: Int
    let color: Color
    
    var body: some View {
        Text("\(count)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color)
            )
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    @State private var isHovered = false
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 30)
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            .padding(.bottom, 4)
            
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemBackground))
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.08 : 0.05),
                    radius: isHovered ? 12 : 8,
                    x: 0,
                    y: isHovered ? 6 : 4
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct CustomToggleRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
        }
    }
}

struct NavigationLinkRow<Destination: View>: View {
    let title: String
    let icon: String
    var value: String? = nil
    let destination: Destination
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    init(title: String, icon: String, value: String? = nil, @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.icon = icon
        self.value = value
        self.destination = destination()
    }
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundColor(.accentColor)
                
                Text(title)
                
                Spacer()
                
                if let value = value {
                    Text(value)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(themeManager.getAccentColor(for: colorScheme))
            }
        }
    }
}

struct ActionRow: View {
    let title: String
    let icon: String
    let color: Color
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(color)
            
            Text(title)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.getAccentColor(for: colorScheme))
        }
    }
}

// Add a new view struct after the SettingsView definition
// This extracts the complex iCloud toggle into its own view
struct CloudKitSyncToggle: View {
    @EnvironmentObject private var cloudKitSyncManager: CloudKitSyncManager
    @EnvironmentObject private var authManager: AuthManager
    @Binding var showingCloudKitSignInAlert: Bool
    
    // Track loading state for UI
    @State private var isLoading = false
    @State private var showSyncStatusInfo = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(" iCloud Sync")
                        .font(.system(size: 17))
                    
                    if let lastSyncDate = cloudKitSyncManager.lastSyncDate {
                        Text(" Last sync: \(formatSyncDate(lastSyncDate))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if isLoading || cloudKitSyncManager.isSyncing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.7)
                        .padding(.trailing, 4)
                }
                
                if case .error = cloudKitSyncManager.syncStatus {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                        .onTapGesture {
                            withAnimation {
                                showSyncStatusInfo.toggle()
                            }
                        }
                        .padding(.trailing, 4)
                }
                
                Toggle("", isOn: Binding(
                    get: { cloudKitSyncManager.isSyncEnabled },
                    set: { newValue in
                        // Use toggleSync method which handles UserDefaults persistence
                        if authManager.isGuest {
                            showingCloudKitSignInAlert = true
                            return
                        }
                        
                        cloudKitSyncManager.toggleSync(enabled: newValue)
                        
                        // Brief loading indicator to show something is happening
                        withAnimation {
                            isLoading = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation {
                                isLoading = false
                            }
                        }
                    }
                ))
                .labelsHidden()
                .disabled(isLoading || cloudKitSyncManager.isSyncing || authManager.isGuest)
                .tint(ThemeManager.shared.getAccentColor(for: .dark))
            }
            .padding(.vertical, 4)
            
            if showSyncStatusInfo {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync Status: \(getSyncStatusText())")
                        .font(.caption)
                        .foregroundColor(getSyncStatusColor())
                        .padding(.top, 2)
                    
                    // Show retry button for error states
                    if case .error = cloudKitSyncManager.syncStatus {
                        HStack(spacing: 12) {
                        Button(action: {
                            cloudKitSyncManager.resetSyncState()
                            showSyncStatusInfo = false
                        }) {
                            Text("Reset Sync Status")
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            
                            Button(action: {
                                // Reset and try to enable sync again
                                cloudKitSyncManager.resetSyncState()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    cloudKitSyncManager.toggleSync(enabled: true)
                                }
                                showSyncStatusInfo = false
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                    Text("Retry Sync")
                                        .font(.caption)
                                }
                                .foregroundColor(.orange)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, 4)
                .transition(.opacity)
            }
        }
        .onAppear {
            // Show sync status info if there's an error
            if case .error = cloudKitSyncManager.syncStatus {
                showSyncStatusInfo = true
            }
        }
        // Listen for CloudKit setup events
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CoreDataReloadingStores"))) { _ in
            withAnimation {
                isLoading = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CoreDataReloadComplete"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation {
                    isLoading = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloudKitSyncDisabled"))) { _ in
            DispatchQueue.main.async {
                withAnimation {
                    showSyncStatusInfo = true
                }
            }
        }
    }
    
    private func formatSyncDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func getSyncStatusText() -> String {
        switch cloudKitSyncManager.syncStatus {
        case .idle:
            return cloudKitSyncManager.isSyncEnabled ? "Active" : "Disabled"
        case .syncing:
            return "Syncing..."
        case .error(let message):
            // Provide more helpful error messages
            if message.contains("network") || message.contains("internet") || message.contains("connection") {
                return "Network issue - will retry automatically"
            } else if message.contains("disabled") || message.contains("paused") {
                return "Sync paused - tap 'Force Retry' to restart"
            } else if message.contains("account") {
                return "iCloud account issue - check Settings > Apple ID"
            } else {
            return "Error: \(message)"
            }
        }
    }
    
    private func getSyncStatusColor() -> Color {
        switch cloudKitSyncManager.syncStatus {
        case .idle:
            return cloudKitSyncManager.isSyncEnabled ? .green : .gray
        case .syncing:
            return .blue
        case .error:
            return .orange
        }
    }
}

// Add after the CloudKitSyncToggle struct
struct CarryOverBalanceToggle: View {
    @ObservedObject private var carryOverManager = CarryOverManager.shared
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Toggle(isOn: Binding(
            get: { carryOverManager.isEnabled },
            set: { carryOverManager.toggleCarryOver($0) }
        )) {
            SettingsRow(
                icon: "arrow.forward.circle.fill",
                iconColor: .green,
                title: "Carry Over Balance",
                subtitle: "Automatically transfer positive month-end balance to next month"
            )
        }
        .tint(themeManager.getAccentColor(for: colorScheme))
    }
}

// MARK: - MailView Wrapper

struct MailView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    var isHTML: Bool = false

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: isHTML)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
}


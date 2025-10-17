import Foundation
import SwiftUI

// Manager to handle Apple Intelligence availability and integration
class AIManager: ObservableObject {
    static let shared = AIManager()
    
    @Published var isAvailable: Bool = false
    
    private init() {
        Task { @MainActor in
            checkAvailability()
        }
    }
    
    // Check if Apple Intelligence is available on this device
    @MainActor
    func checkAvailability() {
        // Apple Intelligence requires iOS 18+ and specific device capabilities
        if #available(iOS 18.0, *) {
            // Check for Apple Intelligence capabilities
            // For now, we'll use a basic check - in production this would check for actual AI capabilities
            isAvailable = true
        } else {
            isAvailable = false
        }
    }
    
    // Get compatibility message for users on incompatible devices
    func getCompatibilityMessage() -> String {
        if isAvailable {
            return "Your device supports Spenly AI"
        } else {
            if #available(iOS 18.0, *) {
                return "Apple Intelligence is not available on this device. Please update to a compatible device."
            } else {
                return "Spenly AI requires iOS 18 or later. Please update your device to use this feature."
            }
        }
    }
}

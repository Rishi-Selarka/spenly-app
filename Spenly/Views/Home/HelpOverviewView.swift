import SwiftUI

struct HelpOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Help & Support")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 10)
                    
                    Text("For assistance with using Spenly, please email us at teamspenlyapp@gmail.com")
                        .padding(.bottom, 20)
                    
                    Text("Getting Started")
                        .font(.headline)
                        .padding(.bottom, 8)
                    
                    Text("• Track your daily expenses")
                    Text("• View spending patterns")
                    Text("• Manage your budget")
                    Text("• Export data to PDF or CSV")
                    
                    Text("Features")
                        .font(.headline)
                        .padding(.top, 20)
                        .padding(.bottom, 8)
                    
                    Text("• Dark mode support")
                    Text("• Multiple currencies")
                    Text("• Demo data for testing")
                    Text("• Cloud sync with iCloud")
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

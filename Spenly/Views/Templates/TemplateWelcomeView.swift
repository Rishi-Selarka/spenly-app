import SwiftUI

struct TemplateWelcomeView: View {
    let onDismiss: () -> Void
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Animated Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                    
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Title and Description
                VStack(spacing: 16) {
                    Text("Transaction Templates")
                        .font(selectedFont.font(size: 32, bold: true))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Create shortcuts for your common transactions")
                        .font(selectedFont.font(size: 18))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                
                // Features List
                VStack(spacing: 20) {
                    TemplateFeatureRow(
                        icon: "bolt.fill",
                        title: "Quick Entry",
                        description: "Add transactions with one tap"
                    )
                    
                    TemplateFeatureRow(
                        icon: "slider.horizontal.3",
                        title: "Flexible Fields",
                        description: "Set fixed or variable amounts, notes, and dates"
                    )
                    
                    TemplateFeatureRow(
                        icon: "rectangle.3.group.fill",
                        title: "Beautiful Cards",
                        description: "Organize templates in a gorgeous grid"
                    )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Get Started Button
                Button("Get Started") {
                    onDismiss()
                }
                .buttonStyle(GradientButtonStyle())
                .frame(maxWidth: 280)
                
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Template Feature Row
private struct TemplateFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(selectedFont.font(size: 16, bold: true))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

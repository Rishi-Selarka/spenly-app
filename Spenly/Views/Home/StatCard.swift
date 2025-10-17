import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(selectedFont.font(size: 14))
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(selectedFont.font(size: 16))
                    .fontWeight(.semibold)
            }
            
            Spacer(minLength: 0) // This ensures consistent height
        }
                .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading) // Set a minimum height for consistency
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black)
                .shadow(color: color.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .foregroundColor(.white)
    }
}

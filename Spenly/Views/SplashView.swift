import SwiftUI

struct SplashView: View {
    @Binding var showSplash: Bool
    @State private var displayedText = ""
    @State private var isLoading = false
    private let finalText = "Spenly"
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text(displayedText)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            }
        }
        .onAppear {
            // Start typing animation immediately
            startTypingAnimation()
            
            // Show loading indicator after text completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                withAnimation {
                    isLoading = true
                }
            }
            
            // Dismiss splash with a minimum display time, unless manually dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    // Only auto-dismiss if no one else has already dismissed it
                    if showSplash {
                        showSplash = false
                    }
                }
            }
        }
    }
    
    private func startTypingAnimation() {
        var charIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { timer in
            if charIndex < finalText.count {
                let index = finalText.index(finalText.startIndex, offsetBy: charIndex)
                displayedText += String(finalText[index])
                charIndex += 1
            } else {
                timer.invalidate()
            }
        }
    }
} 

import SwiftUI
import AuthenticationServices
import CoreData
#if canImport(UIKit)
import UIKit
#endif

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var isAnimating = false
    @State private var showingGuestWarning = false
    @State private var featureIndex: Int = 0
    private let carouselItems: [(icon: String, title: String)] = [
        ("lock.shield.fill", "Private by design"),
        ("chart.bar.fill", "Powerful insights"),
        ("sparkles", "One‑time premium unlock"),
        ("arrow.down.doc.fill", "Export PDF & CSV"),
        ("camera.fill", "Snap receipt photos")
    ]
    private let carouselTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Layered animated background
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.black.opacity(0.95)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            Circle()
                .fill(themeManager.getAccentColor(for: .dark).opacity(0.25))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(x: -140, y: -260)
            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: 160, y: -220)
            
            VStack(spacing: 28) {
                // Branding
                VStack(spacing: 16) {
                    if let appIcon = UIApplication.shared.appIconImage {
                        Image(uiImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
                    } else {
                        Image(systemName: "app.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text("Smart, private money management")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 56)
                
                // Features carousel (fixed large box, centered content)
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06))

                    // Sliding content centered
                    ZStack {
                        ForEach(Array(carouselItems.enumerated()), id: \.offset) { idx, item in
                            if idx == featureIndex {
                                HStack(spacing: 10) {
                                    Image(systemName: item.icon)
                                        .symbolRenderingMode(.multicolor)
                                        .font(.system(size: 20, weight: .semibold))
                                    Text(item.title)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal, 12)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            }
                        }
                    }
                }
                .frame(height: 144)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .onReceive(carouselTimer) { _ in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        featureIndex = (featureIndex + 1) % carouselItems.count
                    }
                }
                .onDisappear {
                    carouselTimer.upstream.connect().cancel()
                }
                
                // Actions
                VStack(spacing: 16) {
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            let appleIDRequest = authManager.prepareSignInWithAppleRequest()
                            request.requestedScopes = appleIDRequest.requestedScopes
                            request.nonce = appleIDRequest.nonce
                        },
                        onCompletion: { result in
                            authManager.handleSignInWithAppleCompletion(result)
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
                    
                    Button {
                        showingGuestWarning = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill").foregroundColor(themeManager.getAccentColor(for: .dark))
                            Text("Continue as Guest").fontWeight(.semibold).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(themeManager.getAccentColor(for: .dark).opacity(0.5), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
                
                // Legal
                VStack(spacing: 8) {
                    Text("By continuing, you agree to our")
                        .font(.caption)
                        .foregroundColor(.gray)
                    HStack(spacing: 6) {
                        Button { if let url = URL(string: "https://rishi-selarka.github.io/spenly-legal/terms-of-service") { UIApplication.shared.open(url) } } label: { Text("Terms of Service").font(.caption).fontWeight(.medium).foregroundColor(themeManager.getAccentColor(for: .dark)) }
                        Text("and").font(.caption).foregroundColor(.gray)
                        Button { if let url = URL(string: "https://rishi-selarka.github.io/spenly-legal/privacy-policy") { UIApplication.shared.open(url) } } label: { Text("Privacy Policy").font(.caption).fontWeight(.medium).foregroundColor(themeManager.getAccentColor(for: .dark)) }
                    }
                }
                .padding(.bottom, 20)
            }
            .padding()
        }
        .onAppear {
            isAnimating = true
        }
        .alert("Guest Account Warning", isPresented: $showingGuestWarning) {
            Button("Cancel", role: .cancel) {
                // User cancelled, do nothing
            }
            Button("Continue as Guest", role: .destructive) {
                authManager.signInAsGuest()
        }
        } message: {
            Text("Using a guest account means your data will only be stored locally on this device and cannot be backed up or synced. If you delete the app or lose your device, all your financial data will be permanently lost.\n\nFor data backup and sync across devices, please sign in with Apple ID instead.")
        }
    }
}

private extension LoginView {
    func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.1)).frame(width: 34, height: 34)
                Image(systemName: icon).foregroundColor(themeManager.getAccentColor(for: .dark))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
            .environmentObject(AuthManager.shared)
            .environmentObject(ThemeManager.shared)
            .preferredColorScheme(.dark)
    }
} 

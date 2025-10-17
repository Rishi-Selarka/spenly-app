import SwiftUI
import StoreKit

struct PremiumView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager
    @AppStorage("selectedFont") private var selectedFont: AppFont = .system
    @StateObject private var iap = IAPManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showAlert: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    benefits
                        .padding(.top, 10) // extra space below title
                    actions
                        .padding(.top, 14) // move green button further down from details
                    footer
                }
                .padding(20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) { bottomConsent }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
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
        .task {
            // Configure once; avoid AppStore.sync here to prevent repeated Apple ID prompts
            await iap.configure()
        }
        .onChange(of: iap.alertMessage) { newValue in
            #if DEBUG
            showAlert = (newValue != nil)
            #endif
        }
        #if DEBUG
        .alert("Notice", isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                iap.alertMessage = nil
                showAlert = false
            }
        } message: {
            Text(iap.alertMessage ?? "")
        }
        #endif
    }
}

private extension PremiumView {
    var header: some View {
        VStack(spacing: 16) {
            Text("Spenly Premium")
                .font(selectedFont.font(size: 28, bold: true))
            Text("Unlock premium features. One-time purchase.")
                .font(selectedFont.font(size: 15))
                .foregroundColor(.secondary)
        }
        .padding(.top, 0)
    }

    var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(icon: "hand.raised.fill", title: "Ad-free experience", subtitle: "No banners or interstitials", color: .orange)
            featureRow(icon: "paintbrush.fill", title: "Premium themes", subtitle: "25+ beautiful color schemes", color: .purple)
            featureRow(icon: "textformat", title: "Custom fonts", subtitle: "40+ typography options", color: .blue)
            featureRow(icon: "square.and.arrow.up", title: "Export data", subtitle: "PDF & CSV export", color: .green)
            featureRow(icon: "doc.text.fill", title: "Templates", subtitle: "Quick transaction templates", color: .cyan)
            featureRow(icon: "brain.head.profile", title: "Spenly AI", subtitle: "Smart insights and chat assistance", color: .teal)
            featureRow(icon: "lock.fill", title: "One-time purchase", subtitle: "No subscriptions, lifetime access", color: .yellow)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    func featureRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(color.opacity(0.35), lineWidth: 1))
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(selectedFont.font(size: 15, bold: true))
                Text(subtitle).font(selectedFont.font(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    var actions: some View {
        VStack(spacing: 12) {
            Button(action: { Task { try? await iap.purchaseRemoveAds() } }) {
                HStack(spacing: 8) {
                    Spacer()
                    if iap.isPurchasing {
                        ProgressView().tint(.white)
                    } else if iap.isAdsRemoved {
                        Text("You are a premium user")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        let price = iap.formattedPrice(for: iap.removeAdsProduct)
                        Text(price.isEmpty ? "Unlock Now" : "Unlock Now \(price)")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.green))
            }
            .disabled(iap.isPurchasing || iap.removeAdsProduct == nil || iap.isAdsRemoved)
            .opacity((iap.isPurchasing || iap.removeAdsProduct == nil || iap.isAdsRemoved) ? 0.6 : 1)

            Button("Restore Purchases") { Task { await iap.restorePurchases() } }
                .font(selectedFont.font(size: 13))
                .foregroundColor(.secondary)

            if !iap.isAdsRemoved && ((iap.removeAdsProduct == nil && !iap.isPurchasing) || iap.unavailableReason != nil) {
                let message = iap.unavailableReason ?? (iap.isLoadingProducts ? "Loading price…" : "Price unavailable")
                Text(message)
                    .font(selectedFont.font(size: 11))
                    .foregroundColor(.secondary)
                Button(iap.isLoadingProducts ? "Please wait" : "Reload Price") { Task { await iap.loadProducts() } }
                    .font(selectedFont.font(size: 12, bold: true))
                    .disabled(iap.isLoadingProducts)
            }

            // Keep layout spacious without extra footers when already unlocked
        }
    }

    var footer: some View { EmptyView() }
}

private struct AlertWrapper: Identifiable {
    let id = UUID()
    let message: String
}

private extension PremiumView {
    var bottomConsent: some View {
        HStack(spacing: 6) {
            Text("By continuing you agree to our")
                .font(selectedFont.font(size: 11))
                .foregroundColor(.secondary)
            Button("Privacy Policy") {
                if let url = URL(string: "https://rishi-selarka.github.io/spenly-legal/privacy-policy") { UIApplication.shared.open(url) }
            }
            .font(selectedFont.font(size: 11))
            Text("&")
                .font(selectedFont.font(size: 11))
                .foregroundColor(.secondary)
            Button("Terms of Service") {
                if let url = URL(string: "https://rishi-selarka.github.io/spenly-legal/terms-of-service") { UIApplication.shared.open(url) }
            }
            .font(selectedFont.font(size: 11))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
    }
}

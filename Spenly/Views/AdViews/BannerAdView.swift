import SwiftUI
import GoogleMobileAds
import UIKit

struct AdBannerView: View {
    // RECORDING MODE FLAG - Set to true to hide banner ads for video recording
    // IMPORTANT: Change back to false after video recording is complete
    private let isRecordingMode = false
    
    var adPosition: AdPosition = .bottom
    var adPlacement: AdMobManager.BannerAdPlacement = .home
    var horizontalPadding: CGFloat = 16  // Reduced padding for full ad visibility
    
    enum AdPosition {
        case top
        case bottom
    }
    
    @StateObject private var iapManager = IAPManager.shared
    var body: some View {
        Group {
            // RECORDING MODE: Return empty view to hide banner ads during video recording
            if isRecordingMode || iapManager.isAdsRemoved {
                EmptyView()
            } else {
                // NORMAL MODE: Show banner ads as usual
                VStack(spacing: 0) {
                    BannerAdViewRepresentable(adPosition: adPosition, adPlacement: adPlacement, bannerSize: AdSizeBanner)
                        .frame(width: 320, height: 50) // Fixed standard banner size
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }
    
    // Moved inside AdBannerView to fix linter error
    struct BannerAdViewRepresentable: UIViewRepresentable {
        let adPosition: AdPosition
        let adPlacement: AdMobManager.BannerAdPlacement
        let bannerSize: AdSize
        
        func makeUIView(context: Context) -> BannerView {
            let banner = BannerView()
            
            // Use banner ad ID from AdMobManager with specific placement
            banner.adUnitID = AdMobManager.shared.getBannerAdUnitID(for: adPlacement)
            banner.rootViewController = AdMobManager.shared.getRootViewController()
            
            // Important: Set a valid size before loading the ad
            banner.adSize = bannerSize
            
            // Load the ad
            banner.load(Request())
            
            return banner
        }
        
        func updateUIView(_ uiView: BannerView, context: Context) {
            // No updates needed - banner size is fixed
        }
    }
}

// Preview for development
struct AdBannerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Content above ad")
            Spacer()
            AdBannerView(adPosition: .bottom, adPlacement: .home)
        }
    }
} 
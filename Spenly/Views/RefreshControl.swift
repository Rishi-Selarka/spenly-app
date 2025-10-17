import SwiftUI

struct PullToRefreshControl: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    // Cache values to reduce recalculations
    @State private var minY: CGFloat = 0
    @State private var hasTriggeredRefresh = false
    private let threshold: CGFloat = 70
    
    var body: some View {
        GeometryReader { geo in
            // Only check position when not refreshing to avoid constant updates
            Color.clear
                .preference(key: OffsetPreferenceKey.self, value: geo.frame(in: .global).minY)
                .onPreferenceChange(OffsetPreferenceKey.self) { value in
                    if !isRefreshing {
                        minY = value
                        
                        // Only trigger refresh once when threshold is crossed
                        if minY > threshold && !hasTriggeredRefresh {
                            hasTriggeredRefresh = true
                        onRefresh()
                        } else if minY <= 0 {
                            // Reset trigger state when scroll position returns to top
                            hasTriggeredRefresh = false
                        }
                    }
            }
            
            HStack {
                Spacer()
                VStack {
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                    } else {
                        // Optimize calculations by reducing precision
                        let rotationDegrees = min(minY * 8, 180)
                        let opacityValue = min(minY / threshold, 1)
                        
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .bold))
                            .rotationEffect(.degrees(minY > 0 ? rotationDegrees : 0))
                            .opacity(minY > 0 ? opacityValue : 0)
                    }
                    
                    Text(refreshText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .offset(y: -50 + (isRefreshing ? 0 : max(0, minY / 1.5)))
        }
    }
    
    private var refreshText: String {
        if isRefreshing {
            return "Loading..."
        } else if minY > threshold {
            return "Release to refresh"
        } else {
            return "Pull to refresh"
        }
    }
}

// Preference key to reduce calculation overhead
private struct OffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
} 
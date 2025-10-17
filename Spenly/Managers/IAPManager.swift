import Foundation
import StoreKit

@MainActor
final class IAPManager: ObservableObject {
    static let shared = IAPManager()

    // StoreKit Product ID configuration
    // Reads the preferred ID from Info.plist key `IAPRemoveAdsProductID` and
    // also tries common fallbacks to avoid misconfiguration blocking purchases.
    private static let preferredProductIdInfoPlistKey: String = "IAPRemoveAdsProductID"
    private static let fallbackProductIds: [String] = [
        "com.rishiselarka.Spenly.removeads",
        "com.spenly.removeads"
    ]

    @Published private(set) var removeAdsProduct: Product?
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isAdsRemoved: Bool = UserDefaults.standard.bool(forKey: "adsRemoved")
    @Published private(set) var isPremiumUnlocked: Bool = UserDefaults.standard.bool(forKey: "premiumUnlocked")
    @Published var alertMessage: String? = nil
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var unavailableReason: String? = nil

    private init() {}
    private var didStartListening = false

    // MARK: - Product ID Resolution
    private var productIdsToQuery: [String] {
        var ids: [String] = []
        if let configured = Bundle.main.object(forInfoDictionaryKey: Self.preferredProductIdInfoPlistKey) as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ids.append(configured)
        }
        ids.append(contentsOf: Self.fallbackProductIds)
        // de-duplicate while preserving order
        var seen = Set<String>()
        let unique = ids.filter { id in
            if seen.contains(id) { return false }
            seen.insert(id)
            return true
        }
        return unique
    }

    private var preferredProductId: String? {
        guard let configured = Bundle.main.object(forInfoDictionaryKey: Self.preferredProductIdInfoPlistKey) as? String else { return nil }
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func configure() async {
        await refreshEntitlements()
        // If products fail, we keep UI usable via unavailableReason
        await loadProducts()
        listenForTransactions()
    }

    func loadProducts() async {
        let ids = productIdsToQuery.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        // Small retry loop to tolerate transient storefront/init
        var lastError: Error?
        for _ in 1...3 {
            do {
                let products = try await Product.products(for: ids)
                if let preferred = preferredProductId, let exact = products.first(where: { $0.id == preferred }) {
                    removeAdsProduct = exact
                } else {
                    removeAdsProduct = products.first
                }
                if removeAdsProduct != nil { return }
            } catch {
                lastError = error
            }
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
        }
        if removeAdsProduct == nil {
            let storefront = await Storefront.current
            if let storefront = storefront {
                unavailableReason = "Premium is not available in your storefront (\(storefront.countryCode)) yet."
            } else if let e = lastError {
                unavailableReason = "We couldn't reach the App Store right now (\(e.localizedDescription))."
            } else {
                unavailableReason = "Premium is temporarily unavailable. Please try again later."
            }
            #if DEBUG
            // In debug builds, surface an alert to help diagnose
            alertMessage = unavailableReason
            #endif
        }
    }

    func refreshEntitlements() async {
        var hasRemoveAds = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if productIdsToQuery.contains(transaction.productID) {
                hasRemoveAds = true
            }
        }
        setPremiumUnlocked(hasRemoveAds)
    }

    func listenForTransactions() {
        if didStartListening { return }
        didStartListening = true
        Task { @MainActor in
            for await update in StoreKit.Transaction.updates {
                switch update {
                case .verified(let transaction):
                    if productIdsToQuery.contains(transaction.productID) {
                        if transaction.revocationDate != nil {
                            setPremiumUnlocked(false)
                        } else {
                            setPremiumUnlocked(true)
                        }
                    }
                    await transaction.finish()
                case .unverified:
                    // Ignore unverified
                    break
                }
            }
        }
    }

    func purchaseRemoveAds() async throws {
        guard let product = removeAdsProduct else {
            // Surface a gentle message; UI is already disabled
            #if DEBUG
            alertMessage = "Product unavailable. Try Reload Price."
            #endif
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                setPremiumUnlocked(true)
                await transaction.finish()
            case .unverified:
                alertMessage = "Purchase could not be verified. Please try again."
                throw NSError(domain: "IAP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Purchase could not be verified."])
            }
        case .userCancelled:
            alertMessage = "Purchase cancelled. You can try again anytime."
        case .pending:
            // Keep UI consistent but do not unlock. Let transactions listener update when finished.
            alertMessage = "Purchase is pending. We'll unlock Premium when it's complete."
        default:
            alertMessage = "Purchase did not complete. Please try again."
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isPremiumUnlocked {
                alertMessage = "Purchases restored successfully."
            } else {
                alertMessage = "No purchases to restore on this Apple ID."
            }
            
            // Trigger theme/font validation after restore
            NotificationCenter.default.post(
                name: NSNotification.Name("PremiumEntitlementChanged"),
                object: nil
            )
        } catch {
            #if DEBUG
            print("[IAP] Restore failed: \(error)")
            #endif
            alertMessage = "Restore failed. Please try again."
        }
    }

    /// Force-refresh entitlements from the App Store.
    /// Useful after clearing sandbox purchase history to immediately reflect changes.
    func hardRefreshEntitlements() async {
        // Avoid forcing AppStore.sync except when user explicitly taps Restore Purchases,
        // to prevent repeated Apple ID sign-in prompts.
        await refreshEntitlements()
    }

    func formattedPrice(for product: Product?) -> String {
        guard let product = product else { return "" }
        // Use StoreKit's formatted price to respect currency/locale
        return product.displayPrice
    }

    /// Reset local entitlement flags (used on sign-out/account deletion)
    func resetLocalEntitlements() {
        setPremiumUnlocked(false)
    }

    private func setPremiumUnlocked(_ value: Bool) {
        // Ensure we're on main thread for UI consistency
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setPremiumUnlocked(value)
            }
            return
        }
        
        // Single source of truth for premium entitlement from IAP
        UserDefaults.standard.set(value, forKey: "premiumUnlocked")
        isPremiumUnlocked = value
        // Backwards compatibility: adsRemoved mirrors premium for now
        UserDefaults.standard.set(value, forKey: "adsRemoved")
        isAdsRemoved = value
        NotificationCenter.default.post(name: NSNotification.Name("PremiumEntitlementChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("AdsRemovedChanged"), object: nil)
    }
    
}



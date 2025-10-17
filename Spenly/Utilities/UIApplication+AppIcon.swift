import UIKit

extension UIApplication {
    /// Attempts to retrieve the app's primary icon as a UIImage.
    /// Returns nil if not available at runtime.
    var appIconImage: UIImage? {
        guard
            let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let lastIcon = iconFiles.last
        else { return nil }

        return UIImage(named: lastIcon)
    }
}



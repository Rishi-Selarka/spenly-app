import SwiftUI
import UIKit

extension Color {
    func darker() -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: s, brightness: b * 0.7, alpha: a))
    }
}

extension UserDefaults {
    func color(forKey key: String) -> Color? {
        guard let colorData = data(forKey: key),
              let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData)
        else { return nil }
        return Color(uiColor)
    }
    
    func setColor(_ color: Color, forKey key: String) {
        let uiColor = UIColor(color)
        guard let colorData = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: true)
        else { return }
        set(colorData, forKey: key)
    }
} 
import SwiftUI

enum Theme: String, CaseIterable, Identifiable {
    case system = "System"
    case classic = "Classic"
    case midnight = "Midnight"
    case ocean = "Ocean"
    case forest = "Forest"
    case sunset = "Sunset"
    case grey = "Grey"
    case lavender = "Lavender"
    case mint = "Mint"
    case rose = "Rose"
    case coffee = "Coffee"
    case galaxy = "Galaxy"
    case desert = "Desert"
    case arctic = "Arctic"
    case autumn = "Autumn"
    case spring = "Spring"
    case neon = "Neon"
    case pastel = "Pastel"
    case royal = "Royal"
    case earth = "Earth"
    case cyber = "Cyber"
    case sapphire = "Sapphire"
    case ruby = "Ruby"
    case emerald = "Emerald"
    case amethyst = "Amethyst"
    case nordic = "Nordic"
    
    var id: String { rawValue }
    
    var isPremium: Bool {
        // Ocean is free, all others require premium
        return self != .ocean
    }
    
    func colors(for colorScheme: ColorScheme) -> ThemeColors {
        switch self {
        case .system:
            switch colorScheme {
            case .dark:
                return .systemDark
            default:
                return .systemLight
            }
        case .classic:
            switch colorScheme {
            case .dark:
                return .classicDark
            default:
                return .classicLight
            }
        case .midnight:
            switch colorScheme {
            case .dark:
                return .midnightDark
            default:
                return .midnightLight
            }
        case .ocean:
            switch colorScheme {
            case .dark:
                return .oceanDark
            default:
                return .oceanLight
            }
        case .forest:
            return colorScheme == .dark ? .forestDark : .forestLight
            
        case .sunset:
            return colorScheme == .dark ? .sunsetDark : .sunsetLight
            
        case .grey:
            return colorScheme == .dark ? .greyDark : .greyLight
            
        case .lavender:
            return colorScheme == .dark ? .lavenderDark : .lavenderLight
            
        case .mint:
            return colorScheme == .dark ? .mintDark : .mintLight
            
        case .rose:
            switch colorScheme {
            case .dark:
                return .roseDark
            default:
                return .roseLight
            }
        case .coffee:
            switch colorScheme {
            case .dark:
                return .coffeeDark
            default:
                return .coffeeLight
            }
        case .galaxy:
            switch colorScheme {
            case .dark:
                return .galaxyDark
            default:
                return .galaxyLight
            }
        case .desert:
            switch colorScheme {
            case .dark:
                return .desertDark
            default:
                return .desertLight
            }
        case .arctic:
            switch colorScheme {
            case .dark:
                return .arcticDark
            default:
                return .arcticLight
            }
        case .autumn:
            switch colorScheme {
            case .dark:
                return .autumnDark
            default:
                return .autumnLight
            }
        case .spring:
            switch colorScheme {
            case .dark:
                return .springDark
            default:
                return .springLight
            }
        case .neon:
            switch colorScheme {
            case .dark:
                return .neonDark
            default:
                return .neonLight
            }
        case .pastel:
            switch colorScheme {
            case .dark:
                return .pastelDark
            default:
                return .pastelLight
            }
        case .royal:
            switch colorScheme {
            case .dark:
                return .royalDark
            default:
                return .royalLight
            }
        case .earth:
            switch colorScheme {
            case .dark:
                return .earthDark
            default:
                return .earthLight
            }
        case .cyber:
            switch colorScheme {
            case .dark:
                return .cyberDark
            default:
                return .cyberLight
            }
        case .sapphire:
            switch colorScheme {
            case .dark:
                return .sapphireDark
            default:
                return .sapphireLight
            }
        case .ruby:
            switch colorScheme {
            case .dark:
                return .rubyDark
            default:
                return .rubyLight
            }
        case .emerald:
            switch colorScheme {
            case .dark:
                return .emeraldDark
            default:
                return .emeraldLight
            }
        case .amethyst:
            switch colorScheme {
            case .dark:
                return .amethystDark
            default:
                return .amethystLight
            }
        case .nordic:
            switch colorScheme {
            case .dark:
                return .nordicDark
            default:
                return .nordicLight
            }
        }
    }
    
    var allowsDarkMode: Bool {
        return true // Allow dark mode for all themes
    }
}

extension ThemeColors {
    static let systemLight = ThemeColors(
        accent: .blue,
        background: .white,
        secondaryBackground: Color(.systemGray6),
        text: .primary,
        secondaryText: .secondary
    )
    
    static let systemDark = ThemeColors(
        accent: .blue,
        background: .black,
        secondaryBackground: Color(.systemGray5),
        text: .white,
        secondaryText: .gray
    )
    
    static let classicLight = ThemeColors(
        accent: .blue,
        background: .white,
        secondaryBackground: Color(.systemGray6),
        text: .primary,
        secondaryText: .secondary
    )
    
    static let classicDark = ThemeColors(
        accent: .blue,
        background: .black,
        secondaryBackground: Color(.systemGray5),
        text: .white,
        secondaryText: .gray
    )
    
    static let midnightLight = ThemeColors(
        accent: Color(hex: "7B68EE"),
        background: .white,
        secondaryBackground: Color(hex: "F0F0F0"),
        text: Color(hex: "1A1A1A"),
        secondaryText: Color(hex: "666666")
    )
    
    static let midnightDark = ThemeColors(
        accent: Color(hex: "9D8FFF"),
        background: Color(hex: "1A1A2E"),
        secondaryBackground: Color(hex: "16213E"),
        text: .white,
        secondaryText: Color(hex: "B8B8B8")
    )
    
    static let oceanLight = ThemeColors(
        accent: Color(hex: "0077BE"),
        background: Color(hex: "F5FCFF"),
        secondaryBackground: Color(hex: "E6F7FF"),
        text: Color(hex: "003366"),
        secondaryText: Color(hex: "4D4D4D")
    )
    
    static let oceanDark = ThemeColors(
        accent: Color(hex: "00A3E0"),
        background: Color(hex: "001F3F"),
        secondaryBackground: Color(hex: "002B4D"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let forestLight = ThemeColors(
        accent: Color(hex: "2E7D32"),
        background: Color(hex: "F9FBF9"),
        secondaryBackground: Color(hex: "E8F5E9"),
        text: Color(hex: "1B5E20"),
        secondaryText: Color(hex: "4D4D4D")
    )
    
    static let forestDark = ThemeColors(
        accent: Color(hex: "4CAF50"),
        background: Color(hex: "1B2E1B"),
        secondaryBackground: Color(hex: "233B23"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let sunsetLight = ThemeColors(
        accent: Color(hex: "FF6B6B"),
        background: Color(hex: "FFF5F5"),
        secondaryBackground: Color(hex: "FFE9E9"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let sunsetDark = ThemeColors(
        accent: Color(hex: "FF8787"),
        background: Color(hex: "2D1F1F"),
        secondaryBackground: Color(hex: "3D2929"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let greyLight = ThemeColors(
        accent: Color(hex: "6B7280"),
        background: Color(hex: "F9FAFB"),
        secondaryBackground: Color(hex: "F3F4F6"),
        text: Color(hex: "1F2937"),
        secondaryText: Color(hex: "6B7280")
    )
    
    static let greyDark = ThemeColors(
        accent: Color(hex: "9CA3AF"),
        background: Color(hex: "111827"),
        secondaryBackground: Color(hex: "1F2937"),
        text: Color(hex: "F9FAFB"),
        secondaryText: Color(hex: "D1D5DB")
    )
    
    static let lavenderLight = ThemeColors(
        accent: Color(hex: "9B6B9E"),
        background: Color(hex: "F7F0F7"),
        secondaryBackground: Color(hex: "EDE2EE"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let lavenderDark = ThemeColors(
        accent: Color(hex: "C792EA"),
        background: Color(hex: "2D2438"),
        secondaryBackground: Color(hex: "382D45"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let mintLight = ThemeColors(
        accent: Color(hex: "40B3A2"),
        background: Color(hex: "F2FFFC"),
        secondaryBackground: Color(hex: "E5F6F3"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let mintDark = ThemeColors(
        accent: Color(hex: "64FFDA"),
        background: Color(hex: "1E3332"),
        secondaryBackground: Color(hex: "2A4745"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let roseLight = ThemeColors(
        accent: Color(hex: "FF6B81"),
        background: Color(hex: "FFF5F6"),
        secondaryBackground: Color(hex: "FFE9EC"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let roseDark = ThemeColors(
        accent: Color(hex: "FF8A9E"),
        background: Color(hex: "332629"),
        secondaryBackground: Color(hex: "453438"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let coffeeLight = ThemeColors(
        accent: Color(hex: "8B4513"),
        background: Color(hex: "FFF8F0"),
        secondaryBackground: Color(hex: "F5E6D3"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let coffeeDark = ThemeColors(
        accent: Color(hex: "D2691E"),
        background: Color(hex: "2C1810"),
        secondaryBackground: Color(hex: "3D2317"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let galaxyLight = ThemeColors(
        accent: Color(hex: "7B68EE"),
        background: Color(hex: "F8F7FF"),
        secondaryBackground: Color(hex: "E8E7FF"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let galaxyDark = ThemeColors(
        accent: Color(hex: "9D8FFF"),
        background: Color(hex: "0A0A2A"),
        secondaryBackground: Color(hex: "141438"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let desertLight = ThemeColors(
        accent: Color(hex: "D2691E"),
        background: Color(hex: "FFF8DC"),
        secondaryBackground: Color(hex: "F5E6CB"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let desertDark = ThemeColors(
        accent: Color(hex: "FF8C00"),
        background: Color(hex: "2B1D0E"),
        secondaryBackground: Color(hex: "3C2815"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let arcticLight = ThemeColors(
        accent: Color(hex: "48D1CC"),
        background: Color(hex: "F0FFFF"),
        secondaryBackground: Color(hex: "E1FFFF"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let arcticDark = ThemeColors(
        accent: Color(hex: "00CED1"),
        background: Color(hex: "102835"),
        secondaryBackground: Color(hex: "1A3B4A"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let autumnLight = ThemeColors(
        accent: Color(hex: "CD853F"),
        background: Color(hex: "FFF3E0"),
        secondaryBackground: Color(hex: "FFE0B2"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let autumnDark = ThemeColors(
        accent: Color(hex: "DEB887"),
        background: Color(hex: "2D1810"),
        secondaryBackground: Color(hex: "3D2317"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let springLight = ThemeColors(
        accent: Color(hex: "98FB98"),
        background: Color(hex: "F0FFF0"),
        secondaryBackground: Color(hex: "E0FFE0"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let springDark = ThemeColors(
        accent: Color(hex: "90EE90"),
        background: Color(hex: "1A321A"),
        secondaryBackground: Color(hex: "254525"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let neonLight = ThemeColors(
        accent: Color(hex: "FF1493"),
        background: Color(hex: "FFFFFF"),
        secondaryBackground: Color(hex: "F0F0F0"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let neonDark = ThemeColors(
        accent: Color(hex: "FF69B4"),
        background: Color(hex: "000000"),
        secondaryBackground: Color(hex: "1A1A1A"),
        text: Color(hex: "00FF00"),
        secondaryText: Color(hex: "FF00FF")
    )
    
    static let pastelLight = ThemeColors(
        accent: Color(hex: "FFB6C1"),
        background: Color(hex: "FFF0F5"),
        secondaryBackground: Color(hex: "FFE4E1"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let pastelDark = ThemeColors(
        accent: Color(hex: "FFC0CB"),
        background: Color(hex: "2D2D2D"),
        secondaryBackground: Color(hex: "3D3D3D"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let royalLight = ThemeColors(
        accent: Color(hex: "4169E1"),
        background: Color(hex: "F8F8FF"),
        secondaryBackground: Color(hex: "E6E6FA"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let royalDark = ThemeColors(
        accent: Color(hex: "6495ED"),
        background: Color(hex: "191970"),
        secondaryBackground: Color(hex: "000080"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let earthLight = ThemeColors(
        accent: Color(hex: "8B4513"),
        background: Color(hex: "FFFAF0"),
        secondaryBackground: Color(hex: "F5DEB3"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let earthDark = ThemeColors(
        accent: Color(hex: "DAA520"),
        background: Color(hex: "2F1F0F"),
        secondaryBackground: Color(hex: "3D2914"),
        text: .white,
        secondaryText: Color(hex: "B3B3B3")
    )
    
    static let cyberLight = ThemeColors(
        accent: Color(hex: "00FF00"),
        background: Color(hex: "FFFFFF"),
        secondaryBackground: Color(hex: "F0F0F0"),
        text: Color(hex: "2D2D2D"),
        secondaryText: Color(hex: "666666")
    )
    
    static let cyberDark = ThemeColors(
        accent: Color(hex: "00FF00"),
        background: Color(hex: "000000"),
        secondaryBackground: Color(hex: "1A1A1A"),
        text: Color(hex: "00FF00"),
        secondaryText: Color(hex: "008000")
    )
    
    // New themes
    static let sapphireLight = ThemeColors(
        accent: Color(hex: "0066CC"),
        background: Color(hex: "F0F8FF"),
        secondaryBackground: Color(hex: "E6F2FF"),
        text: Color(hex: "1A1A1A"),
        secondaryText: Color(hex: "555555")
    )
    
    static let sapphireDark = ThemeColors(
        accent: Color(hex: "4DA6FF"),
        background: Color(hex: "0A1929"),
        secondaryBackground: Color(hex: "152238"),
        text: Color(hex: "FFFFFF"),
        secondaryText: Color(hex: "AAAAAA")
    )
    
    static let rubyLight = ThemeColors(
        accent: Color(hex: "E0115F"),
        background: Color(hex: "FFF0F5"),
        secondaryBackground: Color(hex: "FFE4EA"),
        text: Color(hex: "1A1A1A"),
        secondaryText: Color(hex: "555555")
    )
    
    static let rubyDark = ThemeColors(
        accent: Color(hex: "FF3377"),
        background: Color(hex: "290A14"),
        secondaryBackground: Color(hex: "3D1523"),
        text: Color(hex: "FFFFFF"),
        secondaryText: Color(hex: "AAAAAA")
    )
    
    static let emeraldLight = ThemeColors(
        accent: Color(hex: "00A86B"),
        background: Color(hex: "F0FFF4"),
        secondaryBackground: Color(hex: "E6FFEC"),
        text: Color(hex: "1A1A1A"),
        secondaryText: Color(hex: "555555")
    )
    
    static let emeraldDark = ThemeColors(
        accent: Color(hex: "00D988"),
        background: Color(hex: "0A2918"),
        secondaryBackground: Color(hex: "153823"),
        text: Color(hex: "FFFFFF"),
        secondaryText: Color(hex: "AAAAAA")
    )
    
    static let amethystLight = ThemeColors(
        accent: Color(hex: "9966CC"),
        background: Color(hex: "F5F0FF"),
        secondaryBackground: Color(hex: "EAE4FF"),
        text: Color(hex: "1A1A1A"),
        secondaryText: Color(hex: "555555")
    )
    
    static let amethystDark = ThemeColors(
        accent: Color(hex: "B088FF"),
        background: Color(hex: "1A0A29"),
        secondaryBackground: Color(hex: "2E1547"),
        text: Color(hex: "FFFFFF"),
        secondaryText: Color(hex: "AAAAAA")
    )
    
    static let nordicLight = ThemeColors(
        accent: Color(hex: "5E81AC"),
        background: Color(hex: "ECEFF4"),
        secondaryBackground: Color(hex: "E5E9F0"),
        text: Color(hex: "2E3440"),
        secondaryText: Color(hex: "4C566A")
    )
    
    static let nordicDark = ThemeColors(
        accent: Color(hex: "88C0D0"),
        background: Color(hex: "2E3440"),
        secondaryBackground: Color(hex: "3B4252"),
        text: Color(hex: "ECEFF4"),
        secondaryText: Color(hex: "D8DEE9")
    )
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
} 
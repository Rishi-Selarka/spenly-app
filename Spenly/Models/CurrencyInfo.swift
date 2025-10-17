import Foundation

struct CurrencyInfo {
    let code: String
    let name: String
    let symbol: String
    let region: String
    
    static let allCurrencies: [CurrencyInfo] = [
        // Major Global Currencies
        CurrencyInfo(code: "USD", name: "US Dollar", symbol: "$", region: "North America"),
        CurrencyInfo(code: "EUR", name: "Euro", symbol: "€", region: "Europe"),
        CurrencyInfo(code: "GBP", name: "British Pound", symbol: "£", region: "Europe"),
        CurrencyInfo(code: "JPY", name: "Japanese Yen", symbol: "¥", region: "Asia"),
        CurrencyInfo(code: "CNY", name: "Chinese Yuan", symbol: "¥", region: "Asia"),
        CurrencyInfo(code: "CHF", name: "Swiss Franc", symbol: "CHF", region: "Europe"),
        CurrencyInfo(code: "CAD", name: "Canadian Dollar", symbol: "C$", region: "North America"),
        CurrencyInfo(code: "AUD", name: "Australian Dollar", symbol: "A$", region: "Oceania"),
        CurrencyInfo(code: "NZD", name: "New Zealand Dollar", symbol: "NZ$", region: "Oceania"),
        CurrencyInfo(code: "SEK", name: "Swedish Krona", symbol: "kr", region: "Europe"),
        
        // Asian Currencies
        CurrencyInfo(code: "INR", name: "Indian Rupee", symbol: "₹", region: "Asia"),
        CurrencyInfo(code: "KRW", name: "South Korean Won", symbol: "₩", region: "Asia"),
        CurrencyInfo(code: "SGD", name: "Singapore Dollar", symbol: "S$", region: "Asia"),
        CurrencyInfo(code: "HKD", name: "Hong Kong Dollar", symbol: "HK$", region: "Asia"),
        CurrencyInfo(code: "TWD", name: "Taiwan Dollar", symbol: "NT$", region: "Asia"),
        CurrencyInfo(code: "THB", name: "Thai Baht", symbol: "฿", region: "Asia"),
        CurrencyInfo(code: "MYR", name: "Malaysian Ringgit", symbol: "RM", region: "Asia"),
        CurrencyInfo(code: "IDR", name: "Indonesian Rupiah", symbol: "Rp", region: "Asia"),
        CurrencyInfo(code: "PHP", name: "Philippine Peso", symbol: "₱", region: "Asia"),
        CurrencyInfo(code: "VND", name: "Vietnamese Dong", symbol: "₫", region: "Asia"),
        CurrencyInfo(code: "PKR", name: "Pakistani Rupee", symbol: "₨", region: "Asia"),
        CurrencyInfo(code: "BDT", name: "Bangladeshi Taka", symbol: "৳", region: "Asia"),
        CurrencyInfo(code: "LKR", name: "Sri Lankan Rupee", symbol: "රු", region: "Asia"),
        CurrencyInfo(code: "NPR", name: "Nepalese Rupee", symbol: "रू", region: "Asia"),
        CurrencyInfo(code: "MMK", name: "Myanmar Kyat", symbol: "K", region: "Asia"),
        CurrencyInfo(code: "KHR", name: "Cambodian Riel", symbol: "៛", region: "Asia"),
        CurrencyInfo(code: "LAK", name: "Laotian Kip", symbol: "₭", region: "Asia"),
        
        // European Currencies
        CurrencyInfo(code: "NOK", name: "Norwegian Krone", symbol: "kr", region: "Europe"),
        CurrencyInfo(code: "DKK", name: "Danish Krone", symbol: "kr", region: "Europe"),
        CurrencyInfo(code: "PLN", name: "Polish Złoty", symbol: "zł", region: "Europe"),
        CurrencyInfo(code: "CZK", name: "Czech Koruna", symbol: "Kč", region: "Europe"),
        CurrencyInfo(code: "HUF", name: "Hungarian Forint", symbol: "Ft", region: "Europe"),
        CurrencyInfo(code: "RON", name: "Romanian Leu", symbol: "lei", region: "Europe"),
        CurrencyInfo(code: "BGN", name: "Bulgarian Lev", symbol: "лв", region: "Europe"),
        CurrencyInfo(code: "HRK", name: "Croatian Kuna", symbol: "kn", region: "Europe"),
        CurrencyInfo(code: "RSD", name: "Serbian Dinar", symbol: "дин", region: "Europe"),
        CurrencyInfo(code: "MKD", name: "Macedonian Denar", symbol: "ден", region: "Europe"),
        CurrencyInfo(code: "ALL", name: "Albanian Lek", symbol: "L", region: "Europe"),
        CurrencyInfo(code: "BAM", name: "Bosnia Mark", symbol: "KM", region: "Europe"),
        CurrencyInfo(code: "MDL", name: "Moldovan Leu", symbol: "L", region: "Europe"),
        CurrencyInfo(code: "UAH", name: "Ukrainian Hryvnia", symbol: "₴", region: "Europe"),
        CurrencyInfo(code: "BYN", name: "Belarusian Ruble", symbol: "Br", region: "Europe"),
        CurrencyInfo(code: "GEL", name: "Georgian Lari", symbol: "₾", region: "Europe"),
        CurrencyInfo(code: "AMD", name: "Armenian Dram", symbol: "֏", region: "Europe"),
        CurrencyInfo(code: "AZN", name: "Azerbaijani Manat", symbol: "₼", region: "Europe"),
        CurrencyInfo(code: "KZT", name: "Kazakhstani Tenge", symbol: "₸", region: "Asia"),
        
        // Middle Eastern & African Currencies
        CurrencyInfo(code: "AED", name: "UAE Dirham", symbol: "د.إ", region: "Middle East"),
        CurrencyInfo(code: "SAR", name: "Saudi Riyal", symbol: "﷼", region: "Middle East"),
        CurrencyInfo(code: "QAR", name: "Qatari Riyal", symbol: "ر.ق", region: "Middle East"),
        CurrencyInfo(code: "KWD", name: "Kuwaiti Dinar", symbol: "د.ك", region: "Middle East"),
        CurrencyInfo(code: "BHD", name: "Bahraini Dinar", symbol: ".د.ب", region: "Middle East"),
        CurrencyInfo(code: "OMR", name: "Omani Rial", symbol: "ر.ع.", region: "Middle East"),
        CurrencyInfo(code: "JOD", name: "Jordanian Dinar", symbol: "د.ا", region: "Middle East"),
        CurrencyInfo(code: "ILS", name: "Israeli Shekel", symbol: "₪", region: "Middle East"),
        CurrencyInfo(code: "TRY", name: "Turkish Lira", symbol: "₺", region: "Europe"),
        CurrencyInfo(code: "EGP", name: "Egyptian Pound", symbol: "E£", region: "Africa"),
        CurrencyInfo(code: "ZAR", name: "South African Rand", symbol: "R", region: "Africa"),
        CurrencyInfo(code: "NGN", name: "Nigerian Naira", symbol: "₦", region: "Africa"),
        CurrencyInfo(code: "KES", name: "Kenyan Shilling", symbol: "KSh", region: "Africa"),
        CurrencyInfo(code: "UGX", name: "Ugandan Shilling", symbol: "USh", region: "Africa"),
        CurrencyInfo(code: "TZS", name: "Tanzanian Shilling", symbol: "TSh", region: "Africa"),
        CurrencyInfo(code: "GHS", name: "Ghanaian Cedi", symbol: "₵", region: "Africa"),
        CurrencyInfo(code: "MAD", name: "Moroccan Dirham", symbol: "د.م.", region: "Africa"),
        CurrencyInfo(code: "TND", name: "Tunisian Dinar", symbol: "د.ت", region: "Africa"),
        CurrencyInfo(code: "DZD", name: "Algerian Dinar", symbol: "د.ج", region: "Africa"),
        
        // Americas Currencies
        CurrencyInfo(code: "BRL", name: "Brazilian Real", symbol: "R$", region: "South America"),
        CurrencyInfo(code: "MXN", name: "Mexican Peso", symbol: "$", region: "North America"),
        CurrencyInfo(code: "ARS", name: "Argentine Peso", symbol: "$", region: "South America"),
        CurrencyInfo(code: "CLP", name: "Chilean Peso", symbol: "$", region: "South America"),
        CurrencyInfo(code: "COP", name: "Colombian Peso", symbol: "$", region: "South America"),
        CurrencyInfo(code: "PEN", name: "Peruvian Sol", symbol: "S/", region: "South America"),
        CurrencyInfo(code: "UYU", name: "Uruguayan Peso", symbol: "$U", region: "South America"),
        CurrencyInfo(code: "PYG", name: "Paraguayan Guarani", symbol: "₲", region: "South America"),
        CurrencyInfo(code: "BOB", name: "Bolivian Boliviano", symbol: "Bs.", region: "South America"),
        CurrencyInfo(code: "VES", name: "Venezuelan Bolívar", symbol: "Bs.S", region: "South America"),
        CurrencyInfo(code: "GTQ", name: "Guatemalan Quetzal", symbol: "Q", region: "Central America"),
        CurrencyInfo(code: "HNL", name: "Honduran Lempira", symbol: "L", region: "Central America"),
        CurrencyInfo(code: "NIO", name: "Nicaraguan Córdoba", symbol: "C$", region: "Central America"),
        CurrencyInfo(code: "CRC", name: "Costa Rican Colón", symbol: "₡", region: "Central America"),
        CurrencyInfo(code: "PAB", name: "Panamanian Balboa", symbol: "B/.", region: "Central America"),
        CurrencyInfo(code: "DOP", name: "Dominican Peso", symbol: "RD$", region: "Caribbean"),
        CurrencyInfo(code: "JMD", name: "Jamaican Dollar", symbol: "J$", region: "Caribbean"),
        CurrencyInfo(code: "TTD", name: "Trinidad Dollar", symbol: "TT$", region: "Caribbean"),
        CurrencyInfo(code: "BBD", name: "Barbados Dollar", symbol: "Bds$", region: "Caribbean"),
        
        // Other Important Currencies
        CurrencyInfo(code: "RUB", name: "Russian Ruble", symbol: "₽", region: "Europe"),
        CurrencyInfo(code: "ISK", name: "Icelandic Króna", symbol: "kr", region: "Europe"),
        CurrencyInfo(code: "IRR", name: "Iranian Rial", symbol: "﷼", region: "Middle East"),
        CurrencyInfo(code: "AFN", name: "Afghan Afghani", symbol: "؋", region: "Asia"),
        
        // Digital Currencies
        CurrencyInfo(code: "BTC", name: "Bitcoin", symbol: "₿", region: "Digital"),
        CurrencyInfo(code: "ETH", name: "Ethereum", symbol: "Ξ", region: "Digital")
    ]
    
    static func getCurrencyInfo(for code: String) -> CurrencyInfo? {
        return allCurrencies.first { $0.code == code }
    }
    
    static func getCurrencyCodes() -> [String] {
        return allCurrencies.map { $0.code }
    }
    
    static func getCurrenciesByRegion() -> [String: [CurrencyInfo]] {
        return Dictionary(grouping: allCurrencies) { $0.region }
    }
} 
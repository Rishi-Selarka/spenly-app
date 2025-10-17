import SwiftUI

// MARK: - Image Caching
final class ImageCache {
    static let shared = ImageCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "com.spenly.imageCache", qos: .userInitiated)
    
    private init() {
        // Set cache limits to avoid memory issues
        cache.countLimit = 100
        
        // Register for memory warnings
        NotificationCenter.default.addObserver(
            self, selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        // Clean up NotificationCenter observers to prevent memory leaks
        NotificationCenter.default.removeObserver(self)
    }
    
    func getImage(named: String) -> UIImage? {
        return cache.object(forKey: named as NSString)
    }
    
    func setImage(_ image: UIImage, forKey key: String) {
        queue.async { [weak self] in
            self?.cache.setObject(image, forKey: key as NSString)
        }
    }
    
    @objc func clearCache() {
        queue.async { [weak self] in
            self?.cache.removeAllObjects()
            #if DEBUG
            print("🧹 ImageCache cleared due to memory warning")
            #endif
        }
    }
}

// MARK: - Cached System Image
struct CachedSystemImage: View {
    let name: String
    let size: CGFloat
    let color: Color?
    
    init(name: String, size: CGFloat = 20, color: Color? = nil) {
        self.name = name
        self.size = size
        self.color = color
    }
    
    var body: some View {
        if let uiImage = ImageCache.shared.getImage(named: cacheKey) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(color)
                .onAppear {
                    cacheSystemImage()
                }
        }
    }
    
    private var cacheKey: String {
        "\(name)_\(size)_\(color?.description ?? "default")"
    }
    
    private func cacheSystemImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let uiImage = UIImage(systemName: name)?.withRenderingMode(.alwaysTemplate) {
                // Create rendered image with correct tint
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
                let renderedImage = renderer.image { context in
                    if let uiColor = color?.uiColor {
                        uiColor.setFill()
                    } else {
                        UIColor.white.setFill()
                    }
                    uiImage.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
                }
                ImageCache.shared.setImage(renderedImage, forKey: cacheKey)
            }
        }
    }
}

extension View {
    func optimizedList() -> some View {
        self
            .listStyle(PlainListStyle())
            .scrollDismissesKeyboard(.immediately)
            .scrollContentBackground(.hidden)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.defaultMinListHeaderHeight, 0)
    }
    
    func optimizedScrollView<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 8, pinnedViews: []) {
                content()
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
    
    func optimizedGrid<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
            content()
        }
        .padding()
    }
    
    func optimizedHorizontalScroll<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 16) {
                content()
            }
            .padding(.horizontal)
        }
    }
}

extension Color {
    var uiColor: UIColor {
        if #available(iOS 14.0, *) {
            return UIColor(self)
        }
        
        // For iOS 13
        let components = self.components()
        return UIColor(red: components.r, green: components.g, blue: components.b, alpha: components.a)
    }
    
    private func components() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let scanner = Scanner(string: self.description.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        var r: CGFloat = 0.0, g: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 1.0
        
        let result = scanner.scanHexInt64(&hexNumber)
        if result {
            r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
            g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
            b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
            a = CGFloat(hexNumber & 0x000000ff) / 255
        }
        return (r, g, b, a)
    }
} 
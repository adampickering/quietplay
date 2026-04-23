import SwiftUI
import UIKit
import ImageIO
import Combine

/// Background-thread image loader that downsamples to the display size
/// BEFORE handing the UIImage to SwiftUI. SwiftUI's AsyncImage decodes
/// at full source resolution on the main thread — on a 2017 Apple TV
/// that drops frames every time a thumbnail scrolls into view. This
/// uses `CGImageSourceCreateThumbnailAtIndex` on a background queue so
/// the main thread only ever sees a pre-sized UIImage.
@MainActor
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?

    /// In-memory cache keyed by "url|target-size". `NSCache` evicts
    /// under memory pressure; on tvOS with 2 GB RAM that matters.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 512
        return c
    }()

    private var task: Task<Void, Never>?

    func load(url: URL, targetPixelSize: CGFloat) {
        let key = "\(url.absoluteString)|\(Int(targetPixelSize))" as NSString
        if let cached = Self.cache.object(forKey: key) {
            if image !== cached { image = cached }
            return
        }
        task?.cancel()
        task = Task.detached(priority: .utility) { [weak self] in
            let ui = await Self.fetchAndDownsample(url: url, targetPixelSize: targetPixelSize)
            guard let ui else { return }
            Self.cache.setObject(ui, forKey: key)
            await MainActor.run { [weak self] in
                self?.image = ui
            }
        }
    }

    func cancel() { task?.cancel() }

    private static func fetchAndDownsample(
        url: URL, targetPixelSize: CGFloat
    ) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return downsample(data: data, targetPixelSize: targetPixelSize)
    }

    private static func downsample(data: Data, targetPixelSize: CGFloat) -> UIImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(16, targetPixelSize),
        ]
        guard
            let src = CGImageSourceCreateWithData(data as CFData, nil),
            let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Drop-in replacement for AsyncImage whose main-thread cost is zero
/// (decode happens on a detached task). Use `targetPixelSize` to tell
/// the decoder how small it can go — avatars can be 128, grid
/// thumbnails ~600, hero art ~1400.
struct FastImage: View {
    let url: String?
    let targetPixelSize: CGFloat
    let contentMode: ContentMode

    @StateObject private var loader = ImageLoader()

    init(url: String?, targetPixelSize: CGFloat, contentMode: ContentMode = .fill) {
        self.url = url
        self.targetPixelSize = targetPixelSize
        self.contentMode = contentMode
    }

    var body: some View {
        ZStack {
            // Placeholder: a low-contrast dark rectangle fills the card
            // frame so the layout doesn't flash-in. Deterministic color
            // derived from the URL hash for a subtly unique tone per
            // video — reads like Netflix's color-first reveal.
            Color.placeholderTint(for: url)

            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: loader.image)
        .onChange(of: url, initial: true) { _, u in
            guard let u, let url = URL(string: u) else {
                return
            }
            loader.load(url: url, targetPixelSize: targetPixelSize)
        }
        .onDisappear { loader.cancel() }
    }
}

extension Color {
    /// Quiet, deterministic placeholder tint derived from a URL string.
    /// Hashed to a low-saturation hue so each card has its own gentle
    /// presence instead of a uniform "empty gray." Renders behind
    /// FastImage during decode.
    static func placeholderTint(for key: String?) -> Color {
        guard let key, !key.isEmpty else {
            return Color(hue: 0, saturation: 0, brightness: 0.12)
        }
        var hasher = Hasher()
        hasher.combine(key)
        let h = Double(UInt(truncatingIfNeeded: hasher.finalize()) % 360) / 360.0
        return Color(hue: h, saturation: 0.24, brightness: 0.14)
    }
}

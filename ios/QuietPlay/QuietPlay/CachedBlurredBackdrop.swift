import SwiftUI
import UIKit
import CoreImage
import Combine

/// Library backdrop that blurs the focused-channel thumbnail ONCE on a
/// background thread and caches the result. Previously SwiftUI's
/// `.blur(radius: 32)` ran on every render, which on a 2017 Apple TV
/// cost ~4–6 ms per frame just sitting there. Pre-blurring and caching
/// means the render path is a plain image draw — effectively free.
struct CachedBlurredBackdrop: View {
    let urlString: String

    @StateObject private var loader = BlurredImageLoader()

    var body: some View {
        ZStack {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.45), .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: loader.image)
        .onChange(of: urlString, initial: true) { _, u in
            loader.load(urlString: u)
        }
    }
}

@MainActor
final class BlurredImageLoader: ObservableObject {
    @Published var image: UIImage?
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()
    /// Reuse a single CIContext across calls — creating one per image
    /// is the #1 perf mistake with Core Image.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private var task: Task<Void, Never>?

    func load(urlString: String) {
        let key = urlString as NSString
        if let cached = Self.cache.object(forKey: key) {
            if image !== cached { image = cached }
            return
        }
        task?.cancel()
        task = Task.detached(priority: .utility) { [weak self] in
            let out = await Self.fetchAndBlur(urlString: urlString)
            guard let out else { return }
            Self.cache.setObject(out, forKey: key)
            await MainActor.run { [weak self] in
                self?.image = out
            }
        }
    }

    private static func fetchAndBlur(urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return blur(data: data)
    }

    private static func blur(data: Data) -> UIImage? {
        // Downsample the source before blurring. A 1920×1080 gaussian
        // blur is wildly more expensive than a 640×360 one, and the
        // result is visually indistinguishable once blurred.
        let downsampleOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        guard
            let src = CGImageSourceCreateWithData(data as CFData, nil),
            let smallCG = CGImageSourceCreateThumbnailAtIndex(src, 0, downsampleOpts as CFDictionary)
        else { return nil }
        let small = CIImage(cgImage: smallCG)

        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(small.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(18.0, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }

        let cropped = output.cropped(to: small.extent)
        guard let cg = ciContext.createCGImage(cropped, from: cropped.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

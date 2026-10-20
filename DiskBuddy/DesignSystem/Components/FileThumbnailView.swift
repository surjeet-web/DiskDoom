import SwiftUI
import AppKit
import ImageIO

// MARK: - Cached file thumbnail (ImageIO downsampling, no full decode)

struct FileThumbnailView: View {
    let path: String
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 6

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.secondary.opacity(0.12))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .task(id: path) {
            image = await FileThumbnailCache.shared.image(for: path, maxPixel: Int(size * 2))
        }
    }
}

final class FileThumbnailCache: @unchecked Sendable {
    static let shared = FileThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "diskbuddy.thumbnails", qos: .utility, attributes: .concurrent)

    private init() {
        cache.countLimit = 600
    }

    func image(for path: String, maxPixel: Int) async -> NSImage? {
        let key = "\(path)#\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) as CFURL
                guard let source = CGImageSourceCreateWithURL(url, nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                    kCGImageSourceShouldCacheImmediately: true,
                ]
                guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                self?.cache.setObject(image, forKey: key)
                continuation.resume(returning: image)
            }
        }
    }
}

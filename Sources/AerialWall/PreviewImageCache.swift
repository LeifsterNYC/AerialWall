import AppKit
import SwiftUI

/// Loads and caches catalog preview images. Unlike AsyncImage, a load
/// outlives the tile that started it (scrolling a lazy grid cancels
/// AsyncImage loads permanently) and failures are retried.
@MainActor
final class PreviewImageCache: ObservableObject {
    static let shared = PreviewImageCache()

    @Published private(set) var images: [URL: NSImage] = [:]
    private var inFlight: Set<URL> = []

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    func image(for url: URL) -> NSImage? { images[url] }

    func load(_ url: URL) {
        guard images[url] == nil, !inFlight.contains(url) else { return }
        inFlight.insert(url)
        Task {
            for attempt in 1...3 {
                if let (data, _) = try? await session.data(from: url), let image = NSImage(data: data) {
                    images[url] = image
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
            }
            inFlight.remove(url)
        }
    }
}

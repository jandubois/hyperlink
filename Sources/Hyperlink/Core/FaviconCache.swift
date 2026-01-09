import AppKit
import Foundation

/// Caches favicons fetched from websites
@MainActor
class FaviconCache {
    static let shared = FaviconCache()

    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    /// Get favicon for a URL, returns cached image or starts fetching
    /// Returns nil if not cached yet (will notify via callback when ready)
    func favicon(for url: URL, completion: @escaping @MainActor (NSImage?) -> Void) -> NSImage? {
        guard let host = url.host else {
            completion(nil)
            return nil
        }

        // Check cache first
        if let cached = cache[host] {
            return cached
        }

        // Don't start duplicate fetches
        if inFlight.contains(host) {
            return nil
        }

        inFlight.insert(host)

        // Fetch from Google's favicon service
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")!

        Task {
            do {
                let (data, response) = try await session.data(from: faviconURL)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let image = NSImage(data: data) else {
                    inFlight.remove(host)
                    completion(nil)
                    return
                }

                cache[host] = image
                inFlight.remove(host)
                completion(image)
            } catch {
                inFlight.remove(host)
                completion(nil)
            }
        }

        return nil
    }

    /// Preload favicons for a list of URLs
    func preload(urls: [URL]) {
        for url in urls {
            _ = favicon(for: url) { _ in }
        }
    }

    /// Clear the cache
    func clear() {
        cache.removeAll()
    }
}

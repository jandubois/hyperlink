import AppKit
import Foundation

/// Caches favicons fetched from websites
final class FaviconCache: @unchecked Sendable {
    static let shared = FaviconCache()

    private var cache: [String: NSImage] = [:]
    private var pendingCallbacks: [String: [@Sendable (NSImage?) -> Void]] = [:]
    private let lock = NSLock()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    /// Get favicon for a URL, returns cached image or nil if not yet loaded
    func favicon(for url: URL, completion: @escaping @Sendable (NSImage?) -> Void) -> NSImage? {
        guard let host = url.host else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }

        lock.lock()

        // Check cache first
        if let cached = cache[host] {
            lock.unlock()
            return cached
        }

        // Add callback to pending list
        if pendingCallbacks[host] != nil {
            pendingCallbacks[host]?.append(completion)
            lock.unlock()
            return nil
        }

        // Start new fetch
        pendingCallbacks[host] = [completion]
        lock.unlock()

        // Fetch from Google's favicon service
        let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")!

        let task = session.dataTask(with: faviconURL) { [weak self] data, response, error in
            guard let self = self else { return }

            var resultImage: NSImage? = nil
            if error == nil,
               let data = data,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                resultImage = NSImage(data: data)
            }

            self.lock.lock()
            if let img = resultImage {
                self.cache[host] = img
            }
            let callbacks = self.pendingCallbacks.removeValue(forKey: host) ?? []
            self.lock.unlock()

            let finalImage = resultImage
            RunLoop.main.perform {
                for callback in callbacks {
                    callback(finalImage)
                }
            }
        }
        task.resume()

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

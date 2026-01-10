import Foundation

/// Caches and fetches Open Graph metadata for URLs
actor OpenGraphCache {
    static let shared = OpenGraphCache()

    private var cache: [URL: OpenGraphMetadata] = [:]
    private var inFlight: [URL: Task<OpenGraphMetadata?, Never>] = [:]

    private let session: URLSession
    private let maxBytes = 32768  // Only need to read enough for <head>

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }

    /// Gets cached metadata if available
    func getCached(for url: URL) -> OpenGraphMetadata? {
        cache[url]
    }

    /// Fetches Open Graph metadata for a URL
    /// Returns cached result if available, otherwise fetches
    func fetch(for url: URL) async -> OpenGraphMetadata? {
        // Return cached if available
        if let cached = cache[url] {
            return cached
        }

        // Join existing request if in flight
        if let existing = inFlight[url] {
            return await existing.value
        }

        // Start new fetch
        let task = Task<OpenGraphMetadata?, Never> {
            await doFetch(url: url)
        }
        inFlight[url] = task

        let result = await task.value
        inFlight[url] = nil

        if let result = result {
            cache[url] = result
        }

        return result
    }

    private func doFetch(url: URL) async -> OpenGraphMetadata? {
        guard url.scheme == "http" || url.scheme == "https" else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")
            request.setValue("text/html", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) && httpResponse.statusCode != 206 {
                return nil
            }

            // Try UTF-8, fall back to Latin-1
            let html: String
            if let utf8 = String(data: data, encoding: .utf8) {
                html = utf8
            } else if let latin1 = String(data: data, encoding: .isoLatin1) {
                html = latin1
            } else {
                return nil
            }

            let metadata = OpenGraphParser.parse(html: html)
            return metadata.isEmpty ? nil : metadata
        } catch {
            return nil
        }
    }

    /// Prefetches Open Graph metadata for multiple URLs
    func prefetch(urls: [URL]) {
        for url in urls {
            Task {
                _ = await fetch(for: url)
            }
        }
    }
}

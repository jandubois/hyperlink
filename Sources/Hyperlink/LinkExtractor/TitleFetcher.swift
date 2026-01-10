import Foundation

/// Fetches page titles from URLs
actor TitleFetcher {
    private let session: URLSession
    private let maxRetries = 3
    private let timeoutSeconds: TimeInterval = 5
    private let maxBytes = 4096

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds
        self.session = URLSession(configuration: config)
    }

    /// Fetches the page title from a URL
    /// - Returns: The title if found, nil otherwise
    func fetchTitle(from url: URL) async -> String? {
        for attempt in 0..<maxRetries {
            if attempt > 0 {
                // Exponential backoff: 100ms, 200ms, 400ms
                let delay = UInt64(100_000_000 * (1 << attempt))
                try? await Task.sleep(nanoseconds: delay)
            }

            do {
                if let title = try await attemptFetch(url: url) {
                    return title
                }
            } catch {
                // Retry on error
            }
        }

        // Title fetch failed after all retries
        return nil
    }

    private func attemptFetch(url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        // Check for successful response (200-299 or 206 Partial Content)
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) ||
                  httpResponse.statusCode == 206 else {
                return nil
            }
        }

        // Try to decode as UTF-8, fall back to Latin-1
        let html: String
        if let utf8 = String(data: data, encoding: .utf8) {
            html = utf8
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            html = latin1
        } else {
            return nil
        }

        return extractTitle(from: html)
    }

    /// Extracts the title from HTML content
    private func extractTitle(from html: String) -> String? {
        // Pattern to match <title>...</title>
        let pattern = #"<title[^>]*>(.*?)</title>"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges >= 2,
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        var title = String(html[titleRange])

        // Decode HTML entities
        title = HTMLEntityDecoder.decode(title)

        // Normalize whitespace
        title = title.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return title.isEmpty ? nil : title
    }
}

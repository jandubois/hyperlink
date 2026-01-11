import Foundation

/// Parses HTML to extract hyperlinks
enum HTMLLinkParser {
    /// A link extracted from HTML
    struct ParsedLink: Hashable {
        let url: URL
        let anchorText: String?

        func hash(into hasher: inout Hasher) {
            hasher.combine(url)
        }

        static func == (lhs: ParsedLink, rhs: ParsedLink) -> Bool {
            lhs.url == rhs.url
        }
    }

    /// Extracts all http/https links from HTML source
    /// - Parameters:
    ///   - html: The HTML source string
    ///   - baseURL: Base URL for resolving relative links
    /// - Returns: Deduplicated array of links (HTTPS preferred over HTTP for same URL)
    static func extractLinks(from html: String, baseURL: URL) -> [ParsedLink] {
        // Track links by dedup key, preserving insertion order
        var linksByKey: [String: ParsedLink] = [:]
        var orderedKeys: [String] = []

        // Pattern to match <a ...href="..."...>...</a>
        // Captures href value and inner content
        let pattern = #"<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let href = String(html[hrefRange])
            let rawText = String(html[textRange])

            // Resolve and normalize the URL
            guard let url = resolveURL(href, baseURL: baseURL),
                  isHTTPURL(url) else {
                continue
            }

            let normalizedURL = normalizeURL(url)
            let dedupKey = deduplicationKey(for: normalizedURL)

            if let existing = linksByKey[dedupKey] {
                // If we have HTTP and found HTTPS, upgrade to HTTPS
                if existing.url.scheme == "http" && normalizedURL.scheme == "https" {
                    linksByKey[dedupKey] = ParsedLink(
                        url: normalizedURL,
                        anchorText: existing.anchorText  // Keep original anchor text
                    )
                }
                // Otherwise keep existing (first occurrence)
            } else {
                // New URL
                let anchorText = cleanAnchorText(rawText)
                linksByKey[dedupKey] = ParsedLink(
                    url: normalizedURL,
                    anchorText: anchorText.isEmpty ? nil : anchorText
                )
                orderedKeys.append(dedupKey)
            }
        }

        // Return links in original order
        return orderedKeys.compactMap { linksByKey[$0] }
    }

    /// Normalizes a URL (strips fragment, trailing slash) but preserves protocol
    private static func normalizeURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.fragment = nil

        // Strip trailing slash from path (but keep root "/" intact)
        if let path = components?.path, path.count > 1 && path.hasSuffix("/") {
            components?.path = String(path.dropLast())
        }

        return components?.url ?? url
    }

    /// Creates a deduplication key (URL without protocol)
    private static func deduplicationKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.scheme = nil
        // Result: "//host/path" - unique regardless of http/https
        return components?.string ?? url.absoluteString
    }

    /// Resolves a potentially relative URL against a base URL
    private static func resolveURL(_ href: String, baseURL: URL) -> URL? {
        // Skip javascript:, mailto:, tel:, etc.
        let lowercased = href.lowercased().trimmingCharacters(in: .whitespaces)
        if lowercased.hasPrefix("javascript:") ||
           lowercased.hasPrefix("mailto:") ||
           lowercased.hasPrefix("tel:") ||
           lowercased.hasPrefix("#") ||
           lowercased.hasPrefix("data:") {
            return nil
        }

        // Try as absolute URL first
        if let url = URL(string: href), url.scheme != nil {
            return url
        }

        // Resolve as relative URL
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    /// Checks if URL is http or https
    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Strips HTML tags and normalizes whitespace in anchor text
    private static func cleanAnchorText(_ text: String) -> String {
        // Remove HTML tags
        var cleaned = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        cleaned = HTMLEntityDecoder.decode(cleaned)

        // Normalize whitespace
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return cleaned
    }
}

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
    /// - Returns: Deduplicated array of links (first occurrence kept)
    static func extractLinks(from html: String, baseURL: URL) -> [ParsedLink] {
        var seen = Set<URL>()
        var links: [ParsedLink] = []

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

            // Resolve the URL
            guard let url = resolveURL(href, baseURL: baseURL),
                  isHTTPURL(url),
                  !seen.contains(url) else {
                continue
            }

            seen.insert(url)

            // Clean up anchor text (strip HTML tags, normalize whitespace)
            let anchorText = cleanAnchorText(rawText)

            links.append(ParsedLink(
                url: url,
                anchorText: anchorText.isEmpty ? nil : anchorText
            ))
        }

        return links
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

        // Decode common HTML entities
        cleaned = cleaned
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Normalize whitespace
        cleaned = cleaned.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return cleaned
    }
}

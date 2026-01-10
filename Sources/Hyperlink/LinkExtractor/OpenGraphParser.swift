import Foundation

/// Open Graph metadata extracted from a page
struct OpenGraphMetadata {
    let title: String?
    let description: String?
    let imageURL: URL?

    var isEmpty: Bool {
        title == nil && description == nil && imageURL == nil
    }
}

/// Parses Open Graph metadata from HTML
enum OpenGraphParser {
    /// Extracts Open Graph metadata from HTML source
    static func parse(html: String) -> OpenGraphMetadata {
        let title = extractMetaContent(html: html, property: "og:title")
        let description = extractMetaContent(html: html, property: "og:description")
        let imageURLString = extractMetaContent(html: html, property: "og:image")

        let imageURL: URL?
        if let urlString = imageURLString {
            imageURL = URL(string: urlString)
        } else {
            imageURL = nil
        }

        return OpenGraphMetadata(
            title: title.map { HTMLEntityDecoder.decode($0) },
            description: description.map { HTMLEntityDecoder.decode($0) },
            imageURL: imageURL
        )
    }

    /// Extracts content attribute from a meta tag with given property
    private static func extractMetaContent(html: String, property: String) -> String? {
        // Match <meta property="og:..." content="...">
        // Also handles content before property, and both quote styles
        let patterns = [
            #"<meta[^>]+property\s*=\s*["']\#(property)["'][^>]+content\s*=\s*["']([^"']+)["']"#,
            #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+property\s*=\s*["']\#(property)["']"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: .caseInsensitive
            ) else { continue }

            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, options: [], range: range) {
                // Content is in capture group 1 for first pattern, group 1 for second
                let contentRange: NSRange
                if pattern.contains("property.*content") {
                    contentRange = match.range(at: 2)
                } else {
                    contentRange = match.range(at: 1)
                }

                if let swiftRange = Range(contentRange, in: html) {
                    return String(html[swiftRange])
                }
            }
        }

        return nil
    }
}

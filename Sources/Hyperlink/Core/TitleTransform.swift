import Foundation

/// Transforms applied to tab titles before output
struct TitleTransform: Sendable {
    var removeBackticks: Bool
    var trimGitHubSuffix: Bool

    /// Default transform with all options enabled
    static let `default` = TitleTransform(
        removeBackticks: true,
        trimGitHubSuffix: true
    )

    /// No transformations applied
    static let none = TitleTransform(
        removeBackticks: false,
        trimGitHubSuffix: false
    )

    /// Apply all enabled transformations to a title
    func apply(to title: String) -> String {
        var result = title

        if removeBackticks {
            result = result.replacingOccurrences(of: "`", with: "")
        }

        if trimGitHubSuffix {
            result = Self.trimGitHubSuffix(from: result)
        }

        return result
    }

    /// Remove GitHub repository suffix from page titles
    /// Matches patterns like " · owner/repo" or " - owner/repo"
    private static func trimGitHubSuffix(from title: String) -> String {
        // GitHub uses " · owner/repo" format
        // Also handle " - owner/repo" as a fallback
        let patterns = [
            #" · [a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$"#,
            #" - [a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(
                   in: title,
                   range: NSRange(title.startIndex..., in: title)
               ) {
                let range = Range(match.range, in: title)!
                return String(title[..<range.lowerBound])
            }
        }

        return title
    }
}

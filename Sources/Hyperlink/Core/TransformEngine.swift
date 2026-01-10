import Foundation

/// Engine that applies transformation rules to titles and URLs
struct TransformEngine: Sendable {
    let settings: TransformSettings
    let targetBundleID: String?

    /// Result of applying transforms
    struct Result: Sendable {
        let title: String
        let url: String
    }

    init(settings: TransformSettings, targetBundleID: String? = nil) {
        self.settings = settings
        self.targetBundleID = targetBundleID
    }

    /// Apply all matching rules to a title and URL
    func apply(title: String, url: URL) -> Result {
        var currentTitle = title
        var currentURL = url.absoluteString

        // Apply global rules first
        for rule in settings.globalGroup.rules where rule.isEnabled {
            if urlMatches(currentURL, pattern: rule.urlMatch) {
                (currentTitle, currentURL) = applyRule(rule, title: currentTitle, url: currentURL)
            }
        }

        // Apply app-specific rules if we have a target app
        if let bundleID = targetBundleID,
           let appGroup = settings.appGroups.first(where: { $0.bundleID == bundleID && $0.isEnabled }) {
            for rule in appGroup.rules where rule.isEnabled {
                if urlMatches(currentURL, pattern: rule.urlMatch) {
                    (currentTitle, currentURL) = applyRule(rule, title: currentTitle, url: currentURL)
                }
            }
        }

        return Result(title: currentTitle, url: currentURL)
    }

    /// Check if a URL matches a pattern (prefix match, empty = match all)
    private func urlMatches(_ urlString: String, pattern: String) -> Bool {
        if pattern.isEmpty {
            return true
        }
        return urlString.hasPrefix(pattern)
    }

    /// Apply a single rule's transforms
    private func applyRule(_ rule: TransformRule, title: String, url: String) -> (String, String) {
        var currentTitle = title
        var currentURL = url

        for transform in rule.transforms where transform.isEnabled {
            switch transform.target {
            case .title:
                currentTitle = applyTransform(transform, to: currentTitle)
            case .url:
                currentURL = applyTransform(transform, to: currentURL)
            }
        }

        return (currentTitle, currentURL)
    }

    /// Apply a single regex transform to a string
    private func applyTransform(_ transform: Transform, to value: String) -> String {
        guard !transform.pattern.isEmpty else {
            return value
        }

        do {
            let regex = try NSRegularExpression(pattern: transform.pattern)
            let range = NSRange(value.startIndex..., in: value)
            return regex.stringByReplacingMatches(
                in: value,
                range: range,
                withTemplate: transform.replacement
            )
        } catch {
            // Invalid regex - skip this transform
            return value
        }
    }

    /// Validate a regex pattern, returning an error message if invalid
    static func validatePattern(_ pattern: String) -> String? {
        guard !pattern.isEmpty else {
            return nil
        }

        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch let error as NSError {
            return error.localizedDescription
        }
    }
}

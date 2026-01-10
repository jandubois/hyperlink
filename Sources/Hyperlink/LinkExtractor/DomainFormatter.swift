import Foundation

/// Formats domain names for display in the Link Extractor pseudo-tabs
enum DomainFormatter {
    /// Common TLDs that should be stripped from display names
    private static let commonTLDs = Set(["com", "org", "net"])

    /// Formats a URL's domain for display
    /// - Returns: Apex domain with common TLDs stripped (e.g., "github.com" → "github")
    static func displayName(for url: URL) -> String {
        guard let host = url.host?.lowercased() else {
            return url.absoluteString
        }

        let apex = apexDomain(from: host)
        return stripCommonTLD(from: apex)
    }

    /// Extracts the apex domain (registrable domain) from a host
    /// e.g., "docs.github.com" → "github.com"
    private static func apexDomain(from host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)

        guard parts.count >= 2 else {
            return host
        }

        // Handle common two-part TLDs like .co.uk, .com.au
        let twoPartTLDs = Set(["co.uk", "com.au", "co.nz", "co.jp", "org.uk"])
        if parts.count >= 3 {
            let possibleTwoPartTLD = "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
            if twoPartTLDs.contains(possibleTwoPartTLD) {
                // Return the third-to-last part plus the two-part TLD
                return "\(parts[parts.count - 3]).\(possibleTwoPartTLD)"
            }
        }

        // Return last two parts (apex domain)
        return "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
    }

    /// Strips common TLDs from an apex domain for display
    /// e.g., "github.com" → "github", but "example.io" → "example.io"
    private static func stripCommonTLD(from apex: String) -> String {
        let parts = apex.split(separator: ".").map(String.init)

        guard parts.count >= 2 else {
            return apex
        }

        let tld = parts[parts.count - 1]
        if commonTLDs.contains(tld) {
            // Remove the TLD, return everything before it
            return parts.dropLast().joined(separator: ".")
        }

        return apex
    }
}

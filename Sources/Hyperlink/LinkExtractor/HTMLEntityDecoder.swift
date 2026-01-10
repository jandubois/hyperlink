import Foundation

/// Decodes HTML entities in text
enum HTMLEntityDecoder {
    /// Decodes all HTML entities (named and numeric) in the given text
    static func decode(_ text: String) -> String {
        var result = text

        // Decode numeric entities (hex): &#x...; or &#X...;
        if let hexPattern = try? NSRegularExpression(pattern: "&#[xX]([0-9a-fA-F]+);") {
            let range = NSRange(result.startIndex..., in: result)
            let matches = hexPattern.matches(in: result, range: range).reversed()
            for match in matches {
                if let fullRange = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let codePoint = UInt32(result[codeRange], radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }

        // Decode numeric entities (decimal): &#...;
        if let decPattern = try? NSRegularExpression(pattern: "&#([0-9]+);") {
            let range = NSRange(result.startIndex..., in: result)
            let matches = decPattern.matches(in: result, range: range).reversed()
            for match in matches {
                if let fullRange = Range(match.range, in: result),
                   let codeRange = Range(match.range(at: 1), in: result),
                   let codePoint = UInt32(result[codeRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(fullRange, with: String(Character(scalar)))
                }
            }
        }

        // Decode common named entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&ndash;", with: "\u{2013}")
            .replacingOccurrences(of: "&mdash;", with: "\u{2014}")
            .replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
            .replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
            .replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
            .replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
            .replacingOccurrences(of: "&hellip;", with: "\u{2026}")
            .replacingOccurrences(of: "&copy;", with: "\u{00A9}")
            .replacingOccurrences(of: "&reg;", with: "\u{00AE}")
            .replacingOccurrences(of: "&trade;", with: "\u{2122}")

        return result
    }
}

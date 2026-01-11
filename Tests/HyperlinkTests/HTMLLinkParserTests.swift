import Testing
import Foundation
@testable import hyperlink

@Suite("HTMLLinkParser Tests")
struct HTMLLinkParserTests {

    let baseURL = URL(string: "https://example.com/page")!

    @Test("Extracts absolute URLs")
    func extractsAbsoluteURLs() {
        let html = """
            <a href="https://other.com/link">Link</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].url.absoluteString == "https://other.com/link")
        #expect(links[0].anchorText == "Link")
    }

    @Test("Resolves relative URLs")
    func resolvesRelativeURLs() {
        let html = """
            <a href="/about">About</a>
            <a href="contact">Contact</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 2)
        #expect(links[0].url.absoluteString == "https://example.com/about")
        #expect(links[1].url.absoluteString == "https://example.com/contact")
    }

    @Test("Filters to HTTP/HTTPS only")
    func filtersToHTTPOnly() {
        let html = """
            <a href="https://valid.com">Valid</a>
            <a href="mailto:test@example.com">Email</a>
            <a href="javascript:void(0)">JS</a>
            <a href="tel:+1234567890">Phone</a>
            <a href="#section">Anchor</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].url.absoluteString == "https://valid.com")
    }

    @Test("Deduplicates by URL")
    func deduplicatesByURL() {
        let html = """
            <a href="https://example.com">First</a>
            <a href="https://example.com">Second</a>
            <a href="https://other.com">Other</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 2)
        #expect(links[0].anchorText == "First") // Keeps first occurrence
    }

    @Test("Normalizes URLs for deduplication (fragments, trailing slashes)")
    func normalizesURLsForDeduplication() {
        let html = """
            <a href="https://example.com/page">First</a>
            <a href="https://example.com/page#section1">With fragment</a>
            <a href="https://other.com#top">Other</a>
            <a href="https://slash.com/path/">With slash</a>
            <a href="https://slash.com/path">Without slash</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 3)
        #expect(links[0].url.absoluteString == "https://example.com/page")
        #expect(links[0].anchorText == "First") // Keeps first occurrence
        #expect(links[1].url.absoluteString == "https://other.com")
        #expect(links[1].url.fragment == nil) // Fragment stripped
        #expect(links[2].url.absoluteString == "https://slash.com/path")
        #expect(links[2].anchorText == "With slash") // Keeps first occurrence, trailing slash stripped
    }

    @Test("Upgrades HTTP to HTTPS when both exist")
    func upgradesHTTPtoHTTPS() {
        let html = """
            <a href="http://example.com/page">HTTP first</a>
            <a href="https://example.com/page">HTTPS later</a>
            <a href="http://httponly.com/path">HTTP only</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 2)
        // First URL upgraded to HTTPS, but keeps original anchor text
        #expect(links[0].url.absoluteString == "https://example.com/page")
        #expect(links[0].anchorText == "HTTP first")
        // HTTP-only URL stays as HTTP
        #expect(links[1].url.absoluteString == "http://httponly.com/path")
        #expect(links[1].anchorText == "HTTP only")
    }

    @Test("Cleans anchor text")
    func cleansAnchorText() {
        let html = """
            <a href="https://example.com"><span>Nested</span> Text</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].anchorText == "Nested Text")
    }

    @Test("Decodes HTML entities in anchor text")
    func decodesHTMLEntities() {
        let html = """
            <a href="https://example.com">R&amp;D &gt; Sales</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].anchorText == "R&D > Sales")
    }

    @Test("Decodes numeric HTML entities")
    func decodesNumericEntities() {
        let html = """
            <a href="https://example.com">SUSE &#x2013; L&#xF6;sungen f&#xFC;r Server</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].anchorText == "SUSE – Lösungen für Server")
    }

    @Test("Handles empty anchor text")
    func handlesEmptyAnchorText() {
        let html = """
            <a href="https://example.com">   </a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].anchorText == nil)
    }

    @Test("Handles single quotes in href")
    func handlesSingleQuotes() {
        let html = """
            <a href='https://example.com'>Link</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].url.absoluteString == "https://example.com")
    }

    @Test("Handles attributes before href")
    func handlesAttributesBeforeHref() {
        let html = """
            <a class="link" id="main" href="https://example.com">Link</a>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
        #expect(links[0].url.absoluteString == "https://example.com")
    }

    @Test("Case insensitive tag matching")
    func caseInsensitiveTagMatching() {
        let html = """
            <A HREF="https://example.com">Link</A>
            """
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.count == 1)
    }

    @Test("Returns empty array for no links")
    func returnsEmptyForNoLinks() {
        let html = "<p>No links here</p>"
        let links = HTMLLinkParser.extractLinks(from: html, baseURL: baseURL)

        #expect(links.isEmpty)
    }
}

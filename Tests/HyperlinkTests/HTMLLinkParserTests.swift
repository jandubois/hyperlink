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

import Testing
import Foundation
@testable import hyperlink

@Suite("OpenGraphParser Tests")
struct OpenGraphParserTests {

    @Test("Extracts og:title")
    func extractsTitle() {
        let html = """
            <html><head>
            <meta property="og:title" content="Test Title">
            </head></html>
            """
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.title == "Test Title")
    }

    @Test("Extracts og:description")
    func extractsDescription() {
        let html = """
            <html><head>
            <meta property="og:description" content="A test description">
            </head></html>
            """
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.description == "A test description")
    }

    @Test("Extracts og:image")
    func extractsImage() {
        let html = """
            <html><head>
            <meta property="og:image" content="https://example.com/image.jpg">
            </head></html>
            """
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.imageURL?.absoluteString == "https://example.com/image.jpg")
    }

    @Test("Handles content before property")
    func handlesContentBeforeProperty() {
        let html = """
            <html><head>
            <meta content="Reversed Order" property="og:title">
            </head></html>
            """
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.title == "Reversed Order")
    }

    @Test("Handles single quotes")
    func handlesSingleQuotes() {
        let html = """
            <html><head>
            <meta property='og:title' content='Single Quotes'>
            </head></html>
            """
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.title == "Single Quotes")
    }

    @Test("Decodes HTML entities")
    func decodesHTMLEntities() {
        let html = """
            <html><head>
            <meta property="og:title" content="R&amp;D &gt; Sales">
            </head></html>
            """
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.title == "R&D > Sales")
    }

    @Test("Returns empty for missing metadata")
    func returnsEmptyForMissing() {
        let html = "<html><head><title>No OG</title></head></html>"
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.isEmpty)
    }

    @Test("Extracts all metadata")
    func extractsAllMetadata() {
        let html = """
            <html><head>
            <meta property="og:title" content="Full Test">
            <meta property="og:description" content="Complete metadata">
            <meta property="og:image" content="https://example.com/og.png">
            </head></html>
            """
        let metadata = OpenGraphParser.parse(html: html)

        #expect(metadata.title == "Full Test")
        #expect(metadata.description == "Complete metadata")
        #expect(metadata.imageURL?.absoluteString == "https://example.com/og.png")
        #expect(!metadata.isEmpty)
    }
}

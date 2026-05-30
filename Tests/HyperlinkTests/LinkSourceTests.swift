import Testing
import Foundation
@testable import hyperlink

@Suite("LinkSource Tests")
struct LinkSourceTests {
    @Test("Active-tab result parses index, URL, and title")
    func activeTabResultParses() {
        let tab = TabInfo(activeTabResult: "2\nhttps://example.com\nExample Title")
        #expect(tab?.index == 2)
        #expect(tab?.url == URL(string: "https://example.com"))
        #expect(tab?.title == "Example Title")
        #expect(tab?.isActive == true)
    }

    @Test("Active-tab title keeps embedded newlines")
    func activeTabResultKeepsNewlines() {
        let tab = TabInfo(activeTabResult: "3\nhttps://example.com\nLine one\nLine two")
        #expect(tab?.title == "Line one\nLine two")
    }

    @Test("Active-tab result falls back to URL when title is empty")
    func activeTabResultEmptyTitle() {
        let tab = TabInfo(activeTabResult: "1\nhttps://example.com")
        #expect(tab?.title == "https://example.com")
    }

    @Test("Active-tab result returns nil for empty input")
    func activeTabResultEmpty() {
        #expect(TabInfo(activeTabResult: "") == nil)
    }

    @Test("Active-tab result returns nil for a non-numeric index")
    func activeTabResultBadIndex() {
        #expect(TabInfo(activeTabResult: "x\nhttps://example.com\nTitle") == nil)
    }
}

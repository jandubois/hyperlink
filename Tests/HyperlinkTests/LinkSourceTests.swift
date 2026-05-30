import Testing
import Foundation
@testable import hyperlink

@Suite("LinkSource Tests")
struct LinkSourceTests {
    @Test("Source warnings have distinct user-facing messages")
    func sourceWarningMessages() {
        #expect(SourceWarning.permissionDenied.message == "Pinned tabs need Accessibility permission")
        #expect(SourceWarning.pinnedQueryFailed("detail").message == "Couldn't detect pinned tabs")
    }

    @Test("pinnedQueryFailed detail appends the underlying cause")
    func sourceWarningDetailIncludesCause() {
        let warning = SourceWarning.pinnedQueryFailed("error -1728")
        #expect(warning.detail == "Couldn't detect pinned tabs: error -1728")
        // permissionDenied has no extra cause, so detail matches message.
        #expect(SourceWarning.permissionDenied.detail == SourceWarning.permissionDenied.message)
    }

    @Test("MockLinkSource loads windows with no warning")
    func mockLoadsWithoutWarning() throws {
        let tab = TabInfo(index: 1, title: "T", url: URL(string: "https://example.com")!, isActive: true)
        let source = MockLinkSource(name: "Safari", windows: [WindowInfo(index: 1, name: nil, tabs: [tab])])

        let result = try source.loadWindows(includePinnedCounts: true)
        #expect(result.windows.count == 1)
        #expect(result.warning == nil)
    }

    @Test("instancesSync carries the load warning onto the instance")
    func instancesCarryWarning() throws {
        // The default instancesSync wraps loadWindows; a warningless source
        // produces a warningless instance.
        let tab = TabInfo(index: 1, title: "T", url: URL(string: "https://example.com")!, isActive: true)
        let source = MockLinkSource(name: "Safari", windows: [WindowInfo(index: 1, name: nil, tabs: [tab])])

        let instances = try source.instancesSync()
        #expect(instances.count == 1)
        #expect(instances.first?.warning == nil)
    }

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

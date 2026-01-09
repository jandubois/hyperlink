import Testing
import AppKit
@testable import hyperlink

@Suite("ClipboardWriter Tests", .serialized)
struct ClipboardWriterTests {

    static func makeTab(title: String, url: String, active: Bool = false) -> TabInfo {
        TabInfo(
            index: 1,
            title: title,
            url: URL(string: url)!,
            isActive: active
        )
    }

    @Test("Single tab writes markdown to clipboard")
    func singleTabMarkdown() {
        let tab = Self.makeTab(title: "Example", url: "https://example.com")

        ClipboardWriter.write(tab, transform: .none)

        let result = NSPasteboard.general.string(forType: .string)
        #expect(result == "[Example](https://example.com)")
    }

    @Test("Single tab applies title transform")
    func singleTabTransform() {
        let tab = Self.makeTab(title: "`Code` Example · owner/repo", url: "https://example.com")

        ClipboardWriter.write(tab, transform: .default)

        let result = NSPasteboard.general.string(forType: .string)
        #expect(result == "[Code Example](https://example.com)")
    }

    @Test("Multiple tabs list format")
    func multipleTabsListFormat() {
        let tabs = [
            Self.makeTab(title: "Tab 1", url: "https://example.com/1"),
            Self.makeTab(title: "Tab 2", url: "https://example.com/2")
        ]

        ClipboardWriter.write(tabs, format: .list, transform: .none)

        let result = NSPasteboard.general.string(forType: .string)
        let expected = """
            - [Tab 1](https://example.com/1)
            - [Tab 2](https://example.com/2)
            """
        #expect(result == expected)
    }

    @Test("Multiple tabs plain format")
    func multipleTabsPlainFormat() {
        let tabs = [
            Self.makeTab(title: "Tab 1", url: "https://example.com/1"),
            Self.makeTab(title: "Tab 2", url: "https://example.com/2")
        ]

        ClipboardWriter.write(tabs, format: .plain, transform: .none)

        let result = NSPasteboard.general.string(forType: .string)
        let expected = """
            [Tab 1](https://example.com/1)
            [Tab 2](https://example.com/2)
            """
        #expect(result == expected)
    }

    @Test("RTF data is written for single tab")
    func singleTabWritesRTF() {
        let tab = Self.makeTab(title: "Example", url: "https://example.com")

        ClipboardWriter.write(tab, transform: .none)

        let rtfData = NSPasteboard.general.data(forType: .rtf)
        #expect(rtfData != nil)

        // RTF should contain the URL
        if let data = rtfData, let rtfString = String(data: data, encoding: .utf8) {
            #expect(rtfString.contains("example.com"))
        }
    }

    @Test("Special characters in title are preserved in markdown")
    func specialCharactersMarkdown() {
        let tab = Self.makeTab(title: "Test & <script>", url: "https://example.com")

        ClipboardWriter.write(tab, transform: .none)

        let result = NSPasteboard.general.string(forType: .string)
        // Markdown should preserve the characters (no escaping in markdown links)
        #expect(result == "[Test & <script>](https://example.com)")
    }
}

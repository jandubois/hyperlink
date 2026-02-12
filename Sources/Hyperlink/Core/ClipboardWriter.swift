import AppKit

/// Writes hyperlinks to the clipboard in multiple formats
enum ClipboardWriter {
    /// Write a single tab to the clipboard as markdown (plain text) and RTF (rich text)
    static func write(_ tab: TabInfo, transform: TitleTransform = .default) {
        let transformedTitle = transform.apply(to: tab.title)
        let markdown = "[\(transformedTitle)](\(tab.url.absoluteString))"

        write(markdown: markdown, title: transformedTitle, url: tab.url)
    }

    /// Write a single tab with pre-transformed title and URL
    static func write(title: String, url: URL, transformedURL: String) {
        // Use the transformed URL if it differs, otherwise use the original
        let urlString = transformedURL.isEmpty ? url.absoluteString : transformedURL
        let markdown = "[\(title)](\(urlString))"

        // For RTF, we need a valid URL
        let rtfURL = URL(string: urlString) ?? url
        write(markdown: markdown, title: title, url: rtfURL)
    }

    /// Write multiple tabs to the clipboard
    static func write(_ tabs: [TabInfo], format: MultiSelectionFormat, transform: TitleTransform = .default) {
        let lines = tabs.map { tab in
            let transformedTitle = transform.apply(to: tab.title)
            return "[\(transformedTitle)](\(tab.url.absoluteString))"
        }

        let markdown: String
        switch format {
        case .list:
            markdown = lines.map { "- \($0)" }.joined(separator: "\n")
        case .plain:
            markdown = lines.joined(separator: "\n")
        case .html:
            markdown = lines.map { "- \($0)" }.joined(separator: "\n")
        }

        // For multi-selection, we create RTF with multiple links
        let rtfData = createRTF(tabs: tabs, format: format, transform: transform)
        writeToClipboard(markdown: markdown, rtfData: rtfData)
    }

    /// Write multiple tabs using TransformEngine
    static func write(_ tabs: [TabInfo], format: MultiSelectionFormat, engine: TransformEngine) {
        let transformedTabs = tabs.map { tab -> (title: String, url: String) in
            let result = engine.apply(title: tab.title, url: tab.url)
            return (result.title, result.url)
        }

        let lines = transformedTabs.map { "[\($0.title)](\($0.url))" }

        let markdown: String
        switch format {
        case .list:
            markdown = lines.map { "- \($0)" }.joined(separator: "\n")
        case .plain:
            markdown = lines.joined(separator: "\n")
        case .html:
            markdown = lines.map { "- \($0)" }.joined(separator: "\n")
        }

        // For multi-selection, we create RTF with multiple links
        let rtfData = createRTF(transformedTabs: transformedTabs, format: format)
        writeToClipboard(markdown: markdown, rtfData: rtfData)
    }

    /// Write markdown and RTF to clipboard
    private static func write(markdown: String, title: String, url: URL) {
        let html = "<font face=\"Helvetica Neue\"><a href=\"\(url.absoluteString)\">\(escapeHTML(title))</a></font>"

        guard let rtfData = htmlToRTF(html) else {
            // Fallback: just write plain text
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
            return
        }

        writeToClipboard(markdown: markdown, rtfData: rtfData)
    }

    private static func writeToClipboard(markdown: String, rtfData: Data?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        pasteboard.setString(markdown, forType: .string)

        if let rtfData {
            pasteboard.setData(rtfData, forType: .rtf)
        }
    }

    private static func createRTF(tabs: [TabInfo], format: MultiSelectionFormat, transform: TitleTransform) -> Data? {
        let links = tabs.map { tab in
            let title = escapeHTML(transform.apply(to: tab.title))
            return "<a href=\"\(tab.url.absoluteString)\">\(title)</a>"
        }

        let html: String
        switch format {
        case .list, .html:
            html = "<font face=\"Helvetica Neue\"><ul>" +
                   links.map { "<li>\($0)</li>" }.joined() +
                   "</ul></font>"
        case .plain:
            html = "<font face=\"Helvetica Neue\">" +
                   links.joined(separator: "<br>") +
                   "</font>"
        }

        return htmlToRTF(html)
    }

    private static func createRTF(transformedTabs: [(title: String, url: String)], format: MultiSelectionFormat) -> Data? {
        let links = transformedTabs.map { tab in
            let title = escapeHTML(tab.title)
            return "<a href=\"\(tab.url)\">\(title)</a>"
        }

        let html: String
        switch format {
        case .list, .html:
            html = "<font face=\"Helvetica Neue\"><ul>" +
                   links.map { "<li>\($0)</li>" }.joined() +
                   "</ul></font>"
        case .plain:
            html = "<font face=\"Helvetica Neue\">" +
                   links.joined(separator: "<br>") +
                   "</font>"
        }

        return htmlToRTF(html)
    }

    private static func htmlToRTF(_ html: String) -> Data? {
        // Append a word joiner (U+2060) outside the link so the RTF ends
        // with default formatting. Without this, the link's blue/underline
        // style bleeds into text typed after pasting. U+200B (zero-width
        // space) gets stripped by textutil; U+2060 survives.
        let terminated = html + "\u{2060}"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = [
            "-format", "html",
            "-inputencoding", "UTF-8",
            "-convert", "rtf",
            "-stdin", "-stdout"
        ]

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(Data(terminated.utf8))
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
        } catch {
            // Fall through to return nil
        }

        return nil
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Format for multi-selection clipboard output
enum MultiSelectionFormat: String, CaseIterable, Codable {
    case list   // Markdown bullet list
    case plain  // Plain lines (no bullets)
    case html   // HTML list for RTF
}

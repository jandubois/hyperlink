import AppKit

/// LinkSource implementation for Safari
struct SafariSource: LinkSource {
    let name = "Safari"
    let bundleIdentifier = "com.apple.Safari"

    /// Fetch only the active tab of the front window with a single lightweight
    /// query, skipping full tab enumeration and the slow pinned-tab count.
    func activeTabSync() throws -> TabInfo? {
        guard isRunning else {
            throw LinkSourceError.browserNotRunning(name)
        }

        let script = """
            tell application "Safari"
                if (count of windows) is 0 then return ""
                set theTab to current tab of front window
                return (index of theTab as text) & linefeed & (URL of theTab) & linefeed & (name of theTab)
            end tell
            """

        return TabInfo(activeTabResult: try AppleScriptRunner.run(script))
    }

    func loadWindows(includePinnedCounts: Bool) throws -> LoadResult {
        guard isRunning else {
            throw LinkSourceError.browserNotRunning(name)
        }

        // Pinned tab counts require slow accessibility scripting; only pay for
        // them when the caller needs them. A failure here is non-fatal: report
        // it as a warning and leave tabs unmarked.
        var pinnedCounts: [Int: Int] = [:]
        var warning: SourceWarning?
        if includePinnedCounts {
            switch loadPinnedTabCounts() {
            case .success(let counts):
                pinnedCounts = counts
            case .permissionDenied:
                warning = .permissionDenied
            case .failed(let detail):
                warning = .pinnedQueryFailed(detail)
            }
        }

        // AppleScript that outputs JSON for easier parsing
        let script = """
            tell application "Safari"
                set output to "["
                set windowCount to count of windows
                repeat with w from 1 to windowCount
                    set theWindow to window w
                    set tabCount to count of tabs of theWindow
                    set activeTabIndex to 0
                    try
                        set activeTabIndex to index of current tab of theWindow
                    end try

                    set output to output & "{\\"windowIndex\\":" & w & ",\\"tabs\\":["

                    repeat with t from 1 to tabCount
                        set theTab to tab t of theWindow
                        set tabTitle to name of theTab
                        set tabURL to URL of theTab

                        -- Escape special characters in title
                        set tabTitle to my escapeJSON(tabTitle)

                        set isActive to "false"
                        if t = activeTabIndex then set isActive to "true"

                        set output to output & "{\\"index\\":" & t & ",\\"title\\":\\"" & tabTitle & "\\",\\"url\\":\\"" & tabURL & "\\",\\"active\\":" & isActive & "}"
                        if t < tabCount then set output to output & ","
                    end repeat

                    set output to output & "]}"
                    if w < windowCount then set output to output & ","
                end repeat
                set output to output & "]"
                return output
            end tell

            on escapeJSON(theText)
                set output to ""
                repeat with c in theText
                    set c to c as text
                    if c is "\\\\" then
                        set output to output & "\\\\\\\\"
                    else if c is "\\"" then
                        set output to output & "\\\\\\""
                    else if c is (ASCII character 10) then
                        set output to output & "\\\\n"
                    else if c is (ASCII character 13) then
                        set output to output & "\\\\r"
                    else if c is (ASCII character 9) then
                        set output to output & "\\\\t"
                    else
                        set output to output & c
                    end if
                end repeat
                return output
            end escapeJSON
            """

        let result = try AppleScriptRunner.run(script)
        let windows = try parseJSON(result)

        // Apply pinned counts to windows
        let withPinned = windows.map { window in
            let pinnedCount = pinnedCounts[window.index] ?? 0
            return WindowInfo(
                index: window.index,
                name: window.name,
                tabs: window.tabs,
                pinnedTabCount: pinnedCount
            )
        }
        return LoadResult(windows: withPinned, warning: warning)
    }

    /// Outcome of querying Safari's UI for pinned-tab counts.
    private enum PinnedCountResult {
        case success([Int: Int])  // window index (1-based) -> pinned count
        case permissionDenied
        case failed(String)
    }

    /// Count pinned tabs per window using System Events UI scripting.
    /// Pinned tabs carry the accessibility description "pinned tab".
    /// Unlike the tab data (read via Automation), this needs Accessibility
    /// permission and depends on Safari's tab-bar UI structure, so it can fail
    /// independently.
    private func loadPinnedTabCounts() -> PinnedCountResult {
        let script = """
            tell application "System Events"
                tell process "Safari"
                    set windowCount to count of windows
                    if windowCount = 0 then return ""

                    set output to ""
                    repeat with w from 1 to windowCount
                        tell group "tab bar" of window w
                            set pinnedCount to count of (radio buttons whose description is "pinned tab")
                            set output to output & pinnedCount
                        end tell
                        if w < windowCount then set output to output & ","
                    end repeat
                    return output
                end tell
            end tell
            """

        let result: String
        do {
            result = try AppleScriptRunner.run(script)
        } catch LinkSourceError.permissionDenied {
            return .permissionDenied
        } catch {
            return .failed("\(error)")
        }

        if result.isEmpty {
            return .success([:])  // No windows open
        }

        // Parse comma-separated counts: "2,0,1" -> {1: 2, 2: 0, 3: 1}
        var counts: [Int: Int] = [:]
        let parts = result.split(separator: ",")
        for (index, part) in parts.enumerated() {
            if let count = Int(part.trimmingCharacters(in: .whitespaces)) {
                counts[index + 1] = count  // Window indices are 1-based
            }
        }
        return .success(counts)
    }

    private func parseJSON(_ jsonString: String) throws -> [WindowInfo] {
        guard let data = jsonString.data(using: .utf8) else {
            throw LinkSourceError.scriptError("Invalid JSON encoding")
        }

        struct WindowJSON: Decodable {
            let windowIndex: Int
            let tabs: [TabJSON]
        }

        struct TabJSON: Decodable {
            let index: Int
            let title: String
            let url: String
            let active: Bool
        }

        let decoder = JSONDecoder()
        let windowsJSON = try decoder.decode([WindowJSON].self, from: data)

        return windowsJSON.map { window in
            let tabs = window.tabs.compactMap { tab -> TabInfo? in
                guard let url = URL(string: tab.url) else { return nil }
                return TabInfo(
                    index: tab.index,
                    title: tab.title.isEmpty ? tab.url : tab.title,
                    url: url,
                    isActive: tab.active
                )
            }
            return WindowInfo(index: window.windowIndex, name: nil, tabs: tabs)
        }
    }
}

/// Utility for running AppleScript
enum AppleScriptRunner {
    static func run(_ source: String) throws -> String {
        // Use osascript instead of NSAppleScript to avoid main run loop issues
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw LinkSourceError.scriptError("Failed to run osascript: \(error)")
        }

        // IMPORTANT: Read stdout/stderr BEFORE waitUntilExit to avoid pipe buffer deadlock.
        // If the output is large enough to fill the pipe buffer (~64KB), the child process
        // will block waiting to write, and we'll block waiting for it to exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"

            if errorMessage.contains("not allowed") || errorMessage.contains("-1743") {
                throw LinkSourceError.permissionDenied
            }
            throw LinkSourceError.scriptError(errorMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

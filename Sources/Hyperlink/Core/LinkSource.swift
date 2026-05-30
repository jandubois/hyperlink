import AppKit

/// Information about a single browser tab
struct TabInfo: Sendable, Codable, Hashable {
    let index: Int
    let title: String
    let url: URL
    let isActive: Bool

    var markdownLink: String {
        "[\(title)](\(url.absoluteString))"
    }
}

extension TabInfo {
    /// Parse the active-tab fast-path AppleScript result.
    /// Format is "<index>\n<URL>\n<title>". A URL never contains a newline,
    /// so the title (which may contain newlines) is everything after the second.
    init?(activeTabResult result: String) {
        guard !result.isEmpty else { return nil }
        let parts = result.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let index = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let url = URL(string: String(parts[1])) else {
            return nil
        }
        let title = parts.count >= 3 ? String(parts[2]) : ""
        self.init(index: index, title: title.isEmpty ? url.absoluteString : title, url: url, isActive: true)
    }
}

/// Information about a browser window
struct WindowInfo: Sendable, Codable {
    let index: Int
    let name: String?
    let tabs: [TabInfo]
    let pinnedTabCount: Int

    init(index: Int, name: String?, tabs: [TabInfo], pinnedTabCount: Int = 0) {
        self.index = index
        self.name = name
        self.tabs = tabs
        self.pinnedTabCount = pinnedTabCount
    }

    /// The currently active tab in this window, if any
    var activeTab: TabInfo? {
        tabs.first { $0.isActive }
    }

    /// Tabs that are pinned (first pinnedTabCount tabs)
    var pinnedTabs: [TabInfo] {
        Array(tabs.prefix(pinnedTabCount))
    }

    /// Tabs that are not pinned
    var unpinnedTabs: [TabInfo] {
        Array(tabs.dropFirst(pinnedTabCount))
    }
}

/// A non-fatal problem encountered while loading tabs. The tabs still load;
/// some derived data (e.g. pinned-tab marking) is missing.
enum SourceWarning: Sendable {
    case permissionDenied
    case pinnedQueryFailed(String)  // detail for logging; message() is user-facing

    /// Short, user-facing description for a toast.
    var message: String {
        switch self {
        case .permissionDenied:
            return "Pinned tabs need Accessibility permission"
        case .pinnedQueryFailed:
            return "Couldn't detect pinned tabs"
        }
    }

    /// Longer description including the underlying cause, for stderr and logs.
    var detail: String {
        switch self {
        case .permissionDenied:
            return message
        case .pinnedQueryFailed(let cause):
            return "\(message): \(cause)"
        }
    }
}

/// The windows from a source, plus any non-fatal warning raised while loading.
struct LoadResult: Sendable {
    let windows: [WindowInfo]
    let warning: SourceWarning?

    init(windows: [WindowInfo], warning: SourceWarning? = nil) {
        self.windows = windows
        self.warning = warning
    }
}

/// Information about a browser instance (may represent a profile)
struct BrowserInstance: Sendable {
    let source: any LinkSource
    let profileName: String?
    let windows: [WindowInfo]
    let warning: SourceWarning?

    init(source: any LinkSource, profileName: String?, windows: [WindowInfo], warning: SourceWarning? = nil) {
        self.source = source
        self.profileName = profileName
        self.windows = windows
        self.warning = warning
    }

    var displayName: String {
        if let profileName {
            return "\(source.name) (\(profileName))"
        }
        return source.name
    }

    var icon: NSImage {
        source.icon
    }

    /// All tabs across all windows
    var allTabs: [TabInfo] {
        windows.flatMap { $0.tabs }
    }

    /// The active tab in the frontmost window
    var activeTab: TabInfo? {
        windows.first?.activeTab
    }
}

/// Protocol for sources that can provide hyperlinks
protocol LinkSource: Sendable {
    /// Display name for this source (e.g., "Safari", "Google Chrome")
    var name: String { get }

    /// Bundle identifier for this source's application
    var bundleIdentifier: String { get }

    /// Application icon
    var icon: NSImage { get }

    /// Whether the source application is currently running
    var isRunning: Bool { get }

    /// Fetch all windows and tabs, plus any non-fatal warning.
    /// Computing pinned counts can be expensive (Safari uses slow accessibility
    /// scripting), so callers that don't need them pass `false`. A failure to
    /// load pinned counts is reported as a warning, not thrown: the tabs still
    /// load.
    func loadWindows(includePinnedCounts: Bool) throws -> LoadResult

    /// Fetch only the active tab of the frontmost window.
    /// Browser sources override this with a lightweight query that avoids
    /// enumerating every tab and computing pinned counts.
    func activeTabSync() throws -> TabInfo?

    /// Fetch all windows and tabs from this source (async wrapper)
    func windows() async throws -> [WindowInfo]

    /// Fetch windows grouped by profile (for browsers that support profiles) - sync version
    func instancesSync() throws -> [BrowserInstance]

    /// Fetch windows grouped by profile (for browsers that support profiles)
    func instances() async throws -> [BrowserInstance]
}

extension LinkSource {
    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "Browser")
            ?? NSImage()
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
    }

    /// Fetch all windows and tabs, discarding any warning. Convenience for
    /// callers (CLI, mock) that don't surface warnings.
    func windowsSync() throws -> [WindowInfo] {
        try loadWindows(includePinnedCounts: true).windows
    }

    /// Fetch all windows and tabs with pinned counts optional, discarding any
    /// warning.
    func windowsSync(includePinnedCounts: Bool) throws -> [WindowInfo] {
        try loadWindows(includePinnedCounts: includePinnedCounts).windows
    }

    // Default derives the active tab from a full window fetch.
    func activeTabSync() throws -> TabInfo? {
        let windows = try windowsSync()
        return windows.first?.activeTab ?? windows.first?.tabs.first
    }

    // Default async implementation calls the sync method
    func windows() async throws -> [WindowInfo] {
        try windowsSync()
    }

    // Default sync implementation for sources that don't support profiles.
    // Carries any load warning through to the single instance.
    func instancesSync() throws -> [BrowserInstance] {
        let result = try loadWindows(includePinnedCounts: true)
        return [BrowserInstance(source: self, profileName: nil, windows: result.windows, warning: result.warning)]
    }

    // Default async implementation for sources that don't support profiles
    func instances() async throws -> [BrowserInstance] {
        try instancesSync()
    }
}

/// Errors that can occur when fetching from a link source
enum LinkSourceError: Error, CustomStringConvertible {
    case browserNotRunning(String)
    case scriptError(String)
    case permissionDenied
    case tabNotFound(Int)
    case noActiveTab

    var description: String {
        switch self {
        case .browserNotRunning(let name):
            return "\(name) is not running"
        case .scriptError(let message):
            return "Script error: \(message)"
        case .permissionDenied:
            return "Permission denied. Please grant Accessibility access in System Preferences."
        case .tabNotFound(let index):
            return "Tab \(index) not found"
        case .noActiveTab:
            return "No active tab found"
        }
    }
}

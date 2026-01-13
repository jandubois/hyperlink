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

/// Information about a browser instance (may represent a profile)
struct BrowserInstance: Sendable {
    let source: any LinkSource
    let profileName: String?
    let windows: [WindowInfo]

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

    /// Fetch all windows and tabs from this source (synchronous)
    func windowsSync() throws -> [WindowInfo]

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

    // Default async implementation calls the sync method
    func windows() async throws -> [WindowInfo] {
        try windowsSync()
    }

    // Default sync implementation for sources that don't support profiles
    func instancesSync() throws -> [BrowserInstance] {
        let windows = try windowsSync()
        return [BrowserInstance(source: self, profileName: nil, windows: windows)]
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

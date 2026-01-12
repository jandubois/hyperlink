import AppKit
import Foundation

/// A snapshot of all browser data, suitable for JSON serialization
struct BrowserSnapshot: Codable {
    let browsers: [BrowserData]

    struct BrowserData: Codable {
        let name: String
        let windows: [WindowInfo]
    }
}

/// A mock implementation of LinkSource that returns pre-loaded data
struct MockLinkSource: LinkSource {
    let name: String
    let bundleIdentifier: String
    private let mockWindows: [WindowInfo]

    init(name: String, windows: [WindowInfo]) {
        self.name = name
        self.mockWindows = windows
        // Use a placeholder bundle identifier for mock sources
        self.bundleIdentifier = "com.mock.\(name.lowercased().replacingOccurrences(of: " ", with: ""))"
    }

    var icon: NSImage {
        // Return a generic browser icon for mock sources
        NSImage(systemSymbolName: "globe", accessibilityDescription: "Browser")
            ?? NSImage()
    }

    var isRunning: Bool {
        // Mock sources are always "running"
        true
    }

    func windowsSync() throws -> [WindowInfo] {
        mockWindows
    }
}

/// Global storage for mock data when --mock-data is used
enum MockDataStore {
    /// The loaded mock snapshot, if any
    /// This is set once at startup and then read-only, so it's safe to use nonisolated(unsafe)
    nonisolated(unsafe) static var snapshot: BrowserSnapshot?

    /// Load mock data from a JSON file
    static func load(from path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        snapshot = try decoder.decode(BrowserSnapshot.self, from: data)
    }

    /// Save browser data to a JSON file
    static func save(_ snapshot: BrowserSnapshot, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let url = URL(fileURLWithPath: path)
        try data.write(to: url)
    }

    /// Get mock sources from loaded snapshot
    static func mockSources() -> [MockLinkSource] {
        guard let snapshot = snapshot else { return [] }
        return snapshot.browsers.map { browser in
            MockLinkSource(name: browser.name, windows: browser.windows)
        }
    }

    /// Get a specific mock source by CLI name or display name (case-insensitive)
    static func mockSource(forName name: String) -> MockLinkSource? {
        // Map CLI names to display names for matching
        let displayName: String
        if let browser = BrowserDetector.KnownBrowser.from(cliName: name) {
            displayName = BrowserDetector.displayName(for: browser)
        } else {
            displayName = name
        }
        let normalizedName = displayName.lowercased().replacingOccurrences(of: " ", with: "")
        return mockSources().first { source in
            source.name.lowercased().replacingOccurrences(of: " ", with: "") == normalizedName
        }
    }

    /// Whether mock mode is active
    static var isActive: Bool {
        snapshot != nil
    }
}

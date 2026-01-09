import AppKit

/// Detects running browsers and determines the frontmost one
enum BrowserDetector {
    /// Known browser bundle identifiers
    enum KnownBrowser: String, CaseIterable {
        case safari = "com.apple.Safari"
        case chrome = "com.google.Chrome"
        case arc = "company.thebrowser.Browser"
        case brave = "com.brave.Browser"
        case edge = "com.microsoft.edgemac"
        case orion = "com.kagi.kagimacOS"

        var cliName: String {
            switch self {
            case .safari: return "safari"
            case .chrome: return "chrome"
            case .arc: return "arc"
            case .brave: return "brave"
            case .edge: return "edge"
            case .orion: return "orion"
            }
        }

        static func from(cliName: String) -> KnownBrowser? {
            allCases.first { $0.cliName == cliName.lowercased() }
        }
    }

    /// Get all currently running browsers, ordered by window z-order (frontmost first)
    static func runningBrowsers() -> [KnownBrowser] {
        let runningApps = NSWorkspace.shared.runningApplications

        // Get the order of apps by their activation time/z-order
        // The frontmost app appears first in the ordering
        let orderedBundleIds = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { app1, app2 in
                // frontmostApplication is a single app, so we check if each is it
                if app1 == NSWorkspace.shared.frontmostApplication { return true }
                if app2 == NSWorkspace.shared.frontmostApplication { return false }
                // For other apps, maintain their order (which is roughly by recency)
                return false
            }
            .compactMap { $0.bundleIdentifier }

        // Filter to only known browsers and maintain z-order
        var result: [KnownBrowser] = []
        for bundleId in orderedBundleIds {
            if let browser = KnownBrowser.allCases.first(where: { $0.rawValue == bundleId }) {
                result.append(browser)
            }
        }

        // Add any running browsers that might not be in the ordered list
        for browser in KnownBrowser.allCases {
            if !result.contains(browser) && runningApps.contains(where: { $0.bundleIdentifier == browser.rawValue }) {
                result.append(browser)
            }
        }

        return result
    }

    /// Get the frontmost browser, if any
    static func frontmostBrowser() -> KnownBrowser? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleId = frontmost.bundleIdentifier,
           let browser = KnownBrowser.allCases.first(where: { $0.rawValue == bundleId }) {
            return browser
        }

        // If frontmost app isn't a browser, return the first running browser
        return runningBrowsers().first
    }

    /// Check if a specific browser is running
    static func isRunning(_ browser: KnownBrowser) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == browser.rawValue
        }
    }

    /// Get the display name for a browser
    static func displayName(for browser: KnownBrowser) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue) {
            return FileManager.default.displayName(atPath: url.path)
        }

        // Fallback names
        switch browser {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave Browser"
        case .edge: return "Microsoft Edge"
        case .orion: return "Orion"
        }
    }

    /// Get the icon for a browser
    static func icon(for browser: KnownBrowser) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "Browser") ?? NSImage()
    }
}

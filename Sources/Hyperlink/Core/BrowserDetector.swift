import AppKit
import CoreGraphics

/// Detects running browsers and determines the frontmost one
enum BrowserDetector {
    /// Cache the frontmost browser at launch (before our window takes focus)
    nonisolated(unsafe) private static var cachedFrontmostBrowser: KnownBrowser?
    nonisolated(unsafe) private static var hasCachedFrontmost = false

    /// Cache the frontmost app bundle ID at launch (for paste functionality)
    nonisolated(unsafe) private(set) static var capturedFrontmostBundleID: String?

    /// Call this early at launch to capture the frontmost browser
    static func captureFrontmostBrowser() {
        guard !hasCachedFrontmost else { return }
        hasCachedFrontmost = true
        cachedFrontmostBrowser = detectFrontmostBrowser()

        // Also capture the frontmost app (may not be a browser)
        capturedFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private static func detectFrontmostBrowser() -> KnownBrowser? {
        // Use CGWindowListCopyWindowInfo to get actual window z-order
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // Find the first browser window in z-order (frontmost first)
        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { continue }

            if let app = NSRunningApplication(processIdentifier: ownerPID),
               let bundleId = app.bundleIdentifier,
               let browser = KnownBrowser.allCases.first(where: { $0.rawValue == bundleId }) {
                return browser
            }
        }

        return nil
    }

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

        // Get all running browsers
        var browsers: [KnownBrowser] = []
        for browser in KnownBrowser.allCases {
            if runningApps.contains(where: { $0.bundleIdentifier == browser.rawValue }) {
                browsers.append(browser)
            }
        }

        // Put the cached frontmost browser first
        if let frontmost = cachedFrontmostBrowser, browsers.contains(frontmost) {
            browsers.removeAll { $0 == frontmost }
            browsers.insert(frontmost, at: 0)
        }

        return browsers
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

    /// Get the display name for a browser (short form for UI)
    static func displayName(for browser: KnownBrowser) -> String {
        switch browser {
        case .safari: return "Safari"
        case .chrome: return "Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave"
        case .edge: return "Edge"
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

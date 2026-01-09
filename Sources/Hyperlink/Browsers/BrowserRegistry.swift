import AppKit

/// Registry of all available browser sources
enum BrowserRegistry {
    /// Get the LinkSource for a known browser
    static func source(for browser: BrowserDetector.KnownBrowser) -> any LinkSource {
        switch browser {
        case .safari:
            return SafariSource()
        case .chrome, .arc, .brave, .edge:
            return ChromiumSource(browser: browser)
        case .orion:
            return OrionSource()
        }
    }

    /// Get the LinkSource for a browser by CLI name
    static func source(forCLIName name: String) -> (any LinkSource)? {
        guard let browser = BrowserDetector.KnownBrowser.from(cliName: name) else {
            return nil
        }
        return source(for: browser)
    }

    /// Get all currently running browser sources, ordered by window z-order
    static func runningSources() -> [any LinkSource] {
        BrowserDetector.runningBrowsers().map { source(for: $0) }
    }

    /// Get the frontmost browser source, if any
    static func frontmostSource() -> (any LinkSource)? {
        guard let browser = BrowserDetector.frontmostBrowser() else {
            return nil
        }
        return source(for: browser)
    }

    /// Fetch windows from a browser synchronously
    static func windowsSync(for browser: BrowserDetector.KnownBrowser) throws -> [WindowInfo] {
        let browserSource = source(for: browser)
        return try browserSource.windowsSync()
    }

    /// Fetch all browser instances from all running browsers
    static func allInstances() async throws -> [BrowserInstance] {
        var instances: [BrowserInstance] = []

        for source in runningSources() {
            do {
                let browserInstances = try await source.instances()
                instances.append(contentsOf: browserInstances)
            } catch {
                // Skip browsers that fail (e.g., permission denied)
                // Could log this error in a real app
            }
        }

        return instances
    }
}

import ArgumentParser
import AppKit
import Foundation

// NOTE: Using ParsableCommand (not AsyncParsableCommand) is critical for GUI mode.
// Launching NSApplication.run() from within an async context causes the cursor to
// disappear in text fields. The synchronous entry point avoids this issue.
@main
struct Hyperlink: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hyperlink",
        abstract: "Extract hyperlinks from browser tabs",
        discussion: """
            Fetches the title and URL from browser tabs and copies them to the clipboard
            as both markdown (for plain text paste) and RTF (for rich text paste).

            When run without arguments, opens a GUI picker. Use flags for CLI mode.
            """,
        version: "0.1.0"
    )

    @Option(name: .long, help: "Browser to query: safari, chrome, arc, brave, edge, orion")
    var browser: String?

    @Option(name: .long, help: "Tab to get: 1-based index, 'active', or 'all'")
    var tab: String = "active"

    @Flag(name: .long, help: "Output to stdout instead of clipboard")
    var stdout: Bool = false

    @Option(name: .long, help: "Output format for --stdout: markdown, json")
    var format: OutputFormat = .markdown

    @Flag(name: .long, help: "Enable test mode: verbose logging and stdin command input")
    var test: Bool = false

    @Option(name: .long, help: "Save all browser data to a JSON file")
    var saveData: String?

    @Option(name: .long, help: "Load mock data from a JSON file instead of querying browsers")
    var mockData: String?

    mutating func run() throws {
        // Enable test logging if --test flag is set
        TestLogger.isEnabled = test

        // Load mock data if specified
        if let mockPath = mockData {
            do {
                try MockDataStore.load(from: mockPath)
            } catch {
                fputs("Error: Failed to load mock data from '\(mockPath)': \(error.localizedDescription)\n", stderr)
                throw ExitCode(1)
            }
        }

        // Handle --save-data: save all browser data and exit
        if let savePath = saveData {
            try saveAllBrowserData(to: savePath)
            return
        }

        // If no arguments provided (or only --test/--mock-data), launch GUI
        let hasOnlyGUICompatibleFlags = browser == nil && !stdout && saveData == nil
        let argCount = CommandLine.arguments.count
        let shouldLaunchGUI = hasOnlyGUICompatibleFlags && (
            argCount == 1 ||
            (argCount == 2 && test) ||
            (argCount == 2 && mockData != nil) ||
            (argCount == 3 && test && mockData != nil) ||
            (argCount == 4 && test && mockData != nil)
        )

        if shouldLaunchGUI {
            launchGUIApp(testMode: test)
            return
        }

        try runCLI()
    }

    private func launchGUIApp(testMode: Bool) {
        // Capture the frontmost browser before our window takes focus
        BrowserDetector.captureFrontmostBrowser()

        // Launch the GUI application synchronously on the main thread.
        // This must run from a synchronous context (not async) for cursors to work.
        // See comment at top of file about ParsableCommand vs AsyncParsableCommand.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            delegate.testMode = testMode
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
        }
    }

    private func saveAllBrowserData(to path: String) throws {
        var browserDataList: [BrowserSnapshot.BrowserData] = []

        // Get all running browsers
        let runningBrowsers = BrowserDetector.runningBrowsers()
        if runningBrowsers.isEmpty {
            fputs("Error: No browsers running\n", stderr)
            throw ExitCode(4)
        }

        for browser in runningBrowsers {
            let source = BrowserRegistry.source(for: browser)
            guard source.isRunning else { continue }

            do {
                let windows = try source.windowsSync()
                if !windows.isEmpty {
                    browserDataList.append(BrowserSnapshot.BrowserData(
                        name: source.name,
                        windows: windows
                    ))
                }
            } catch let error as LinkSourceError {
                if case .permissionDenied = error {
                    fputs("Error: \(error.description)\n", stderr)
                    throw ExitCode(3)
                }
                // Skip other errors for individual browsers
                fputs("Warning: Failed to read \(source.name): \(error.description)\n", stderr)
            }
        }

        if browserDataList.isEmpty {
            fputs("Error: No tabs found in any browser\n", stderr)
            throw ExitCode(1)
        }

        let snapshot = BrowserSnapshot(browsers: browserDataList)
        do {
            try MockDataStore.save(snapshot, to: path)
            fputs("Saved \(browserDataList.count) browser(s) to \(path)\n", stderr)
        } catch {
            fputs("Error: Failed to save data to '\(path)': \(error.localizedDescription)\n", stderr)
            throw ExitCode(1)
        }
    }

    private func runCLI() throws {
        // Get the browser source (use mock if loaded)
        let source: any LinkSource
        if MockDataStore.isActive {
            // Use mock data
            if let browserName = browser {
                guard let s = MockDataStore.mockSource(forName: browserName) else {
                    fputs("Error: Browser '\(browserName)' not found in mock data\n", stderr)
                    throw ExitCode(4)
                }
                source = s
            } else {
                // Use first mock source
                guard let s = MockDataStore.mockSources().first else {
                    fputs("Error: No browsers in mock data\n", stderr)
                    throw ExitCode(4)
                }
                source = s
            }
        } else {
            // Use real browser
            if let browserName = browser {
                guard let s = BrowserRegistry.source(forCLIName: browserName) else {
                    throw ExitCode(4) // Browser not found
                }
                source = s
            } else {
                guard let s = BrowserRegistry.frontmostSource() else {
                    fputs("Error: No browser is running\n", stderr)
                    throw ExitCode(4)
                }
                source = s
            }

            // Check if browser is running (only for real browsers)
            guard source.isRunning else {
                fputs("Error: \(source.name) is not running\n", stderr)
                throw ExitCode(4)
            }
        }

        // Fetch windows and tabs
        let windows: [WindowInfo]
        do {
            windows = try source.windowsSync()
        } catch let error as LinkSourceError {
            fputs("Error: \(error.description)\n", stderr)
            switch error {
            case .permissionDenied:
                throw ExitCode(3)
            default:
                throw ExitCode(1)
            }
        }

        // Handle tab selection
        switch tab.lowercased() {
        case "active":
            guard let activeTab = windows.first?.activeTab ?? windows.first?.tabs.first else {
                fputs("Error: No active tab found\n", stderr)
                throw ExitCode(1)
            }
            outputTab(activeTab, source: source)

        case "all":
            let allTabs = windows.flatMap { $0.tabs }
            if allTabs.isEmpty {
                fputs("Error: No tabs found\n", stderr)
                throw ExitCode(1)
            }
            outputAllTabs(allTabs, source: source, windows: windows)

        default:
            guard let index = Int(tab), index > 0 else {
                fputs("Error: Invalid tab specifier '\(tab)'. Use a number, 'active', or 'all'\n", stderr)
                throw ExitCode(2)
            }

            // Find tab by index (1-based, counting across all windows)
            let allTabs = windows.flatMap { $0.tabs }
            guard index <= allTabs.count else {
                fputs("Error: Tab \(index) not found (only \(allTabs.count) tabs open)\n", stderr)
                throw ExitCode(1)
            }
            let selectedTab = allTabs[index - 1]
            outputTab(selectedTab, source: source)
        }
    }

    private func outputTab(_ tab: TabInfo, source: any LinkSource) {
        let prefs = Preferences.shared
        // CLI uses only global rules (no target app)
        let engine = TransformEngine(settings: prefs.transformSettings, targetBundleID: nil)

        if stdout {
            switch format {
            case .markdown:
                let result = engine.apply(title: tab.title, url: tab.url)
                print("[\(result.title)](\(result.url))")
            case .json:
                let output = SingleTabJSON(
                    browser: source.name.lowercased().replacingOccurrences(of: " ", with: ""),
                    window: 1,
                    tab: tab.index,
                    title: tab.title,
                    url: tab.url.absoluteString
                )
                if let data = try? JSONEncoder().encode(output),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            }
        } else {
            let result = engine.apply(title: tab.title, url: tab.url)
            ClipboardWriter.write(title: result.title, url: tab.url, transformedURL: result.url)
        }
    }

    private func outputAllTabs(_ tabs: [TabInfo], source: any LinkSource, windows: [WindowInfo]) {
        let prefs = Preferences.shared
        // CLI uses only global rules (no target app)
        let engine = TransformEngine(settings: prefs.transformSettings, targetBundleID: nil)

        if stdout {
            switch format {
            case .markdown:
                for tab in tabs {
                    let result = engine.apply(title: tab.title, url: tab.url)
                    print("[\(result.title)](\(result.url))")
                }
            case .json:
                let output = AllTabsJSON(
                    browser: source.name.lowercased().replacingOccurrences(of: " ", with: ""),
                    windows: windows.map { window in
                        AllTabsJSON.WindowJSON(
                            index: window.index,
                            tabs: window.tabs.map { tab in
                                AllTabsJSON.TabJSON(
                                    index: tab.index,
                                    title: tab.title,
                                    url: tab.url.absoluteString,
                                    active: tab.isActive
                                )
                            }
                        )
                    }
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let data = try? encoder.encode(output),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
            }
        } else {
            ClipboardWriter.write(tabs, format: prefs.multiSelectionFormat, engine: engine)
        }
    }
}

// MARK: - Output Format

enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case markdown
    case json
}

// MARK: - JSON Output Structures

struct SingleTabJSON: Encodable {
    let browser: String
    let window: Int
    let tab: Int
    let title: String
    let url: String
}

struct AllTabsJSON: Encodable {
    let browser: String
    let windows: [WindowJSON]

    struct WindowJSON: Encodable {
        let index: Int
        let tabs: [TabJSON]
    }

    struct TabJSON: Encodable {
        let index: Int
        let title: String
        let url: String
        let active: Bool
    }
}

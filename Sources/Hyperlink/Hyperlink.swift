import ArgumentParser
import AppKit
import Foundation

@main
struct Hyperlink: AsyncParsableCommand {
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

    mutating func run() async throws {
        // If no arguments provided, launch GUI
        if browser == nil && !stdout && CommandLine.arguments.count == 1 {
            await launchGUI()
            return
        }

        try await runCLI()
    }

    @MainActor
    private func launchGUI() {
        // Launch the GUI application
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    private func runCLI() async throws {
        // Get the browser source
        let source: any LinkSource
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

        // Check if browser is running
        guard source.isRunning else {
            fputs("Error: \(source.name) is not running\n", stderr)
            throw ExitCode(4)
        }

        // Fetch windows and tabs
        let windows: [WindowInfo]
        do {
            windows = try await source.windows()
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
        let transform = prefs.titleTransform

        if stdout {
            switch format {
            case .markdown:
                let title = transform.apply(to: tab.title)
                print("[\(title)](\(tab.url.absoluteString))")
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
            ClipboardWriter.write(tab, transform: transform)
        }
    }

    private func outputAllTabs(_ tabs: [TabInfo], source: any LinkSource, windows: [WindowInfo]) {
        let prefs = Preferences.shared
        let transform = prefs.titleTransform

        if stdout {
            switch format {
            case .markdown:
                for tab in tabs {
                    let title = transform.apply(to: tab.title)
                    print("[\(title)](\(tab.url.absoluteString))")
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
            ClipboardWriter.write(tabs, format: prefs.multiSelectionFormat, transform: transform)
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

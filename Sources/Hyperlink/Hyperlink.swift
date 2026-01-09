import ArgumentParser
import AppKit

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
    var format: String = "markdown"

    mutating func run() throws {
        // If no arguments provided (just the executable name), launch GUI
        // ArgumentParser will have already parsed, so we check if browser was specified
        // For now, we always run CLI mode; GUI mode will be added in Phase 5

        if browser == nil && !stdout && CommandLine.arguments.count == 1 {
            launchGUI()
        } else {
            try runCLI()
        }
    }

    private func launchGUI() {
        // Placeholder for Phase 5
        print("GUI mode not yet implemented")
        // Will launch NSApplication with SwiftUI
    }

    private func runCLI() throws {
        // Placeholder for Phase 4
        let browserName = browser ?? "frontmost"
        print("CLI mode: browser=\(browserName), tab=\(tab), stdout=\(stdout), format=\(format)")
        print("Not yet implemented - coming in Phase 4")
    }
}

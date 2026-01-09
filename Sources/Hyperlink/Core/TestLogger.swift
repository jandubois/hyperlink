import Foundation

/// Logging utility for test mode
/// Outputs structured JSON-like messages to stderr for integration testing
@MainActor
enum TestLogger {
    /// Whether test logging is enabled
    nonisolated(unsafe) static var isEnabled = false

    /// Log a browser data event
    static func logBrowserData(browser: String, windows: Int, tabs: Int) {
        log("BROWSER_DATA", [
            "browser": browser,
            "windows": windows,
            "tabs": tabs
        ])
    }

    /// Log a tab loaded event
    static func logTab(browser: String, windowIndex: Int, tabIndex: Int, title: String, url: String, active: Bool) {
        log("TAB", [
            "browser": browser,
            "window": windowIndex,
            "index": tabIndex,
            "title": title,
            "url": url,
            "active": active
        ])
    }

    /// Log a user action
    static func logAction(_ action: String, details: [String: Any] = [:]) {
        var data = details
        data["action"] = action
        log("ACTION", data)
    }

    /// Log a key press
    static func logKeyPress(_ key: String, modifiers: [String] = []) {
        log("KEY", [
            "key": key,
            "modifiers": modifiers
        ])
    }

    /// Log state change
    static func logState(_ name: String, value: Any) {
        log("STATE", [
            "name": name,
            "value": value
        ])
    }

    /// Log result (copy action, dismissal, etc.)
    static func logResult(_ type: String, details: [String: Any] = [:]) {
        var data = details
        data["type"] = type
        log("RESULT", data)
    }

    /// Log that the GUI is ready
    static func logReady() {
        log("READY", [:])
    }

    /// Generic log function
    private static func log(_ category: String, _ data: [String: Any]) {
        guard isEnabled else { return }

        var output = "[\(category)]"
        if !data.isEmpty {
            let pairs = data.map { key, value -> String in
                let valueStr: String
                switch value {
                case let s as String:
                    valueStr = "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
                case let b as Bool:
                    valueStr = b ? "true" : "false"
                case let arr as [String]:
                    valueStr = "[\(arr.map { "\"\($0)\"" }.joined(separator: ","))]"
                default:
                    valueStr = "\(value)"
                }
                return "\(key)=\(valueStr)"
            }
            output += " " + pairs.joined(separator: " ")
        }

        fputs(output + "\n", stderr)
        fflush(stderr)
    }
}

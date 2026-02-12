import AppKit
import Carbon.HIToolbox

/// Handles output operations including pasting to apps
enum OutputHandler {
    /// Error types for output operations
    enum OutputError: Error, LocalizedError {
        case appNotFound(String)
        case appNotRunning(String)
        case pasteFailedNoFrontmostApp
        case pasteFailedActivation

        var errorDescription: String? {
            switch self {
            case .appNotFound(let app):
                return "App '\(app)' not found"
            case .appNotRunning(let app):
                return "App '\(app)' is not running"
            case .pasteFailedNoFrontmostApp:
                return "No frontmost app to paste to"
            case .pasteFailedActivation:
                return "Failed to activate target app"
            }
        }
    }

    /// Paste clipboard contents to target app
    /// - Parameter appIdentifier: App name or bundle ID (nil = frontmost app)
    static func pasteToApp(_ appIdentifier: String?) throws {
        let targetApp: NSRunningApplication

        if let identifier = appIdentifier {
            guard let app = findRunningApp(identifier) else {
                throw OutputError.appNotFound(identifier)
            }
            targetApp = app
        } else {
            // Use frontmost app (excluding our own app)
            guard let app = frontmostApp() else {
                throw OutputError.pasteFailedNoFrontmostApp
            }
            targetApp = app
        }

        // In GUI mode NSApplication is already running — activate and paste
        // directly. In CLI mode we need a brief headless NSApplication to
        // give CGEvent and activate a window server connection.
        let guiRunning = MainActor.assumeIsolated { NSApp?.isRunning == true }
        if guiRunning {
            activateAndPaste(targetApp)
        } else {
            activateAndPasteWithApp(targetApp)
        }
    }

    /// Activate target and send paste keystroke (GUI mode, NSApp running)
    private static func activateAndPaste(_ target: NSRunningApplication) {
        target.activate(options: .activateAllWindows)
        Thread.sleep(forTimeInterval: 0.1)
        sendPasteKeystroke()
    }

    /// Start a headless NSApplication, activate target, paste, terminate
    private static func activateAndPasteWithApp(_ target: NSRunningApplication) {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)

            DispatchQueue.main.async {
                activateAndPaste(target)
                app.terminate(nil)
            }

            app.run()
        }
    }

    /// Find a running app by name or bundle ID
    /// - Parameter identifier: App name (case-insensitive) or bundle ID (contains dots)
    /// - Returns: The running app if found
    static func findRunningApp(_ identifier: String) -> NSRunningApplication? {
        let isBundleID = identifier.contains(".")

        if isBundleID {
            // Search by bundle ID (exact match)
            return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
        } else {
            // Search by app name (case-insensitive)
            let lowercasedName = identifier.lowercased()
            return NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .first { app in
                    app.localizedName?.lowercased() == lowercasedName
                }
        }
    }

    /// Get the frontmost app (excluding Hyperlink itself)
    /// - Returns: The frontmost running application
    static func frontmostApp() -> NSRunningApplication? {
        let ownBundleID = Bundle.main.bundleIdentifier

        // Try to get the app that was frontmost before Hyperlink launched
        // This is captured by BrowserDetector.captureFrontmostBrowser()
        if let capturedBundleID = BrowserDetector.capturedFrontmostBundleID,
           capturedBundleID != ownBundleID,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: capturedBundleID).first {
            return app
        }

        // Fallback: get current frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != ownBundleID {
            return frontmost
        }

        // Last resort: find any regular app that isn't us
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != ownBundleID }
            .first
    }

    /// Send Cmd+V keystroke to paste clipboard contents
    private static func sendPasteKeystroke() {
        // Key code for 'V' key
        let vKeyCode: CGKeyCode = 9

        // Create key down event with Command modifier
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) else {
            return
        }
        keyDown.flags = .maskCommand

        // Create key up event with Command modifier
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyUp.flags = .maskCommand

        // Post events to the system
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

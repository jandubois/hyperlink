import AppKit
import ApplicationServices

/// Checks and requests Accessibility permissions
enum PermissionChecker {
    /// Check if Accessibility permissions are granted
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt for Accessibility permission if not already granted
    /// Returns true if permission is already granted, false otherwise
    @discardableResult
    static func promptForAccessibilityIfNeeded() -> Bool {
        if hasAccessibilityPermission {
            return true
        }

        // Prompt the user - this will show the system dialog
        // Use the string value directly to avoid concurrency issues
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Show an alert explaining the permission requirement
    @MainActor
    static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Hyperlink needs Accessibility permission to read browser tabs.

            Please grant access in System Settings > Privacy & Security > Accessibility.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    /// Open the Accessibility pane in System Settings
    @MainActor
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Show an error alert for script execution failures
    @MainActor
    static func showScriptErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error Reading Browser Tabs"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

import AppKit

/// LinkSource implementation for Chromium-based browsers
/// Works with Chrome, Arc, Brave, Edge, and other Chromium browsers
struct ChromiumSource: LinkSource {
    let name: String
    let bundleIdentifier: String
    private let appName: String
    private let browser: BrowserDetector.KnownBrowser

    init(browser: BrowserDetector.KnownBrowser) {
        self.browser = browser
        self.bundleIdentifier = browser.rawValue
        self.appName = Self.appName(for: browser)
        self.name = BrowserDetector.displayName(for: browser)
    }

    private static func appName(for browser: BrowserDetector.KnownBrowser) -> String {
        switch browser {
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave Browser"
        case .edge: return "Microsoft Edge"
        default: return "Google Chrome"
        }
    }

    /// Suffix used in window titles (e.g., "- Google Chrome")
    private var windowTitleSuffix: String {
        switch browser {
        case .chrome: return "Google Chrome"
        case .arc: return "Arc"
        case .brave: return "Brave Browser"
        case .edge: return "Microsoft Edge"
        default: return "Google Chrome"
        }
    }

    func windowsSync() throws -> [WindowInfo] {
        guard isRunning else {
            throw LinkSourceError.browserNotRunning(name)
        }

        // Chromium browsers use similar AppleScript but with different terminology
        // Chrome uses "active tab" instead of "current tab"
        let script = """
            tell application "\(appName)"
                set output to "["
                set windowCount to count of windows
                repeat with w from 1 to windowCount
                    set theWindow to window w
                    set tabCount to count of tabs of theWindow
                    set activeTabIndex to 0
                    try
                        set activeTabIndex to active tab index of theWindow
                    end try

                    set output to output & "{\\"windowIndex\\":" & w & ",\\"tabs\\":["

                    repeat with t from 1 to tabCount
                        set theTab to tab t of theWindow
                        set tabTitle to title of theTab
                        set tabURL to URL of theTab

                        -- Escape special characters in title
                        set tabTitle to my escapeJSON(tabTitle)
                        set tabURL to my escapeJSON(tabURL)

                        set isActive to "false"
                        if t = activeTabIndex then set isActive to "true"

                        set output to output & "{\\"index\\":" & t & ",\\"title\\":\\"" & tabTitle & "\\",\\"url\\":\\"" & tabURL & "\\",\\"active\\":" & isActive & "}"
                        if t < tabCount then set output to output & ","
                    end repeat

                    set output to output & "]}"
                    if w < windowCount then set output to output & ","
                end repeat
                set output to output & "]"
                return output
            end tell

            on escapeJSON(theText)
                set output to ""
                repeat with c in theText
                    set c to c as text
                    if c is "\\\\" then
                        set output to output & "\\\\\\\\"
                    else if c is "\\"" then
                        set output to output & "\\\\\\""
                    else if c is (ASCII character 10) then
                        set output to output & "\\\\n"
                    else if c is (ASCII character 13) then
                        set output to output & "\\\\r"
                    else if c is (ASCII character 9) then
                        set output to output & "\\\\t"
                    else
                        set output to output & c
                    end if
                end repeat
                return output
            end escapeJSON
            """

        let result = try AppleScriptRunner.run(script)
        return try parseJSON(result)
    }

    private func parseJSON(_ jsonString: String) throws -> [WindowInfo] {
        guard let data = jsonString.data(using: .utf8) else {
            throw LinkSourceError.scriptError("Invalid JSON encoding")
        }

        struct WindowJSON: Decodable {
            let windowIndex: Int
            let tabs: [TabJSON]
        }

        struct TabJSON: Decodable {
            let index: Int
            let title: String
            let url: String
            let active: Bool
        }

        let decoder = JSONDecoder()
        let windowsJSON = try decoder.decode([WindowJSON].self, from: data)

        return windowsJSON.map { window in
            let tabs = window.tabs.compactMap { tab -> TabInfo? in
                guard let url = URL(string: tab.url) else { return nil }
                return TabInfo(
                    index: tab.index,
                    title: tab.title.isEmpty ? tab.url : tab.title,
                    url: url,
                    isActive: tab.active
                )
            }
            return WindowInfo(index: window.windowIndex, name: nil, tabs: tabs)
        }
    }

    /// Fetch windows grouped by profile
    func instancesSync() throws -> [BrowserInstance] {
        let windows = try windowsSync()
        guard !windows.isEmpty else {
            return []
        }

        // Get window titles from System Events to extract profile names
        let profileNames = getWindowProfiles()

        // If we couldn't get profile info or there's only one profile, return single instance
        let uniqueProfiles = Set(profileNames.values.map { $0 ?? "" })
        if profileNames.isEmpty || uniqueProfiles.count <= 1 {
            return [BrowserInstance(source: self, profileName: nil, windows: windows)]
        }

        // Group windows by profile
        var windowsByProfile: [String?: [WindowInfo]] = [:]
        for window in windows {
            let profile = profileNames[window.index] ?? nil  // Flatten String?? to String?
            windowsByProfile[profile, default: []].append(window)
        }

        // Create instances for each profile
        return windowsByProfile.map { profile, profileWindows in
            BrowserInstance(source: self, profileName: profile, windows: profileWindows)
        }.sorted { ($0.profileName ?? "") < ($1.profileName ?? "") }
    }

    /// Override instances() to use profile detection
    func instances() async throws -> [BrowserInstance] {
        try instancesSync()
    }

    /// Get profile names for each window by parsing System Events window titles
    /// Returns a dictionary mapping window index to profile name (nil for default profile)
    private func getWindowProfiles() -> [Int: String?] {
        // Use System Events to get window titles which include profile names
        // Format: "Tab Title - Browser Name" (default) or "Tab Title - Browser Name - Profile Name"
        let script = """
            tell application "System Events"
                tell process "\(appName)"
                    set windowNames to {}
                    set windowCount to count of windows
                    repeat with w from 1 to windowCount
                        set end of windowNames to name of window w
                    end repeat
                    return windowNames
                end tell
            end tell
            """

        guard let result = try? AppleScriptRunner.run(script) else {
            return [:]
        }

        // Load profile name mappings from Local State file
        let profileMapping = loadProfileNameMapping()

        // Parse the AppleScript list result
        // Result looks like: "Title1 - Chrome, Title2 - Chrome - Profile"
        var profiles: [Int: String?] = [:]
        let windowNames = parseAppleScriptList(result)

        for (index, windowName) in windowNames.enumerated() {
            let profile = extractProfileName(from: windowName, using: profileMapping)
            profiles[index + 1] = profile  // Window indices are 1-based
        }

        return profiles
    }

    /// Profile name mapping loaded from Chrome's Local State file
    private struct ProfileMapping {
        let defaultProfileName: String?  // Name of the "Default" profile, to return nil for it
        let personToName: [String: String]  // "Person 1" -> actual profile name
    }

    /// Load profile name mappings from Chrome's Local State JSON file
    private func loadProfileNameMapping() -> ProfileMapping {
        // Build path to Local State file based on browser
        let localStatePath: String
        switch browser {
        case .chrome:
            localStatePath = NSHomeDirectory() + "/Library/Application Support/Google/Chrome/Local State"
        case .edge:
            localStatePath = NSHomeDirectory() + "/Library/Application Support/Microsoft Edge/Local State"
        case .brave:
            localStatePath = NSHomeDirectory() + "/Library/Application Support/BraveSoftware/Brave-Browser/Local State"
        case .arc:
            localStatePath = NSHomeDirectory() + "/Library/Application Support/Arc/Local State"
        default:
            return ProfileMapping(defaultProfileName: nil, personToName: [:])
        }

        guard let data = FileManager.default.contents(atPath: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return ProfileMapping(defaultProfileName: nil, personToName: [:])
        }

        var defaultProfileName: String?
        var personToName: [String: String] = [:]

        for (profileDir, profileInfo) in infoCache {
            guard let info = profileInfo as? [String: Any],
                  let name = info["name"] as? String else {
                continue
            }

            if profileDir == "Default" {
                // Store the default profile's display name so we can return nil for it
                defaultProfileName = name
            } else if profileDir.hasPrefix("Profile ") {
                // Extract the number from "Profile N" to create "Person N" mapping
                let profileNum = profileDir.dropFirst("Profile ".count)
                personToName["Person \(profileNum)"] = name
            }
        }

        return ProfileMapping(defaultProfileName: defaultProfileName, personToName: personToName)
    }

    /// Parse an AppleScript list result into an array of strings
    private func parseAppleScriptList(_ result: String) -> [String] {
        // AppleScript returns lists like: "item1, item2, item3"
        result.components(separatedBy: ", ")
    }

    /// Extract profile name from a window title
    /// Window titles are formatted as:
    /// - Default profile: "Tab Title - Browser Name"
    /// - Other profiles: "Tab Title - Browser Name - Profile Name"
    private func extractProfileName(from windowTitle: String, using mapping: ProfileMapping) -> String? {
        let suffix = " - \(windowTitleSuffix)"

        // Check if the window title contains the browser suffix
        guard let suffixRange = windowTitle.range(of: suffix) else {
            return nil
        }

        // Get everything after "- Browser Name"
        let afterSuffix = windowTitle[suffixRange.upperBound...]

        // If there's more content after the browser name, it's the profile
        guard afterSuffix.hasPrefix(" - ") else {
            return nil  // No profile suffix = default profile
        }

        let rawProfileName = String(afterSuffix.dropFirst(3))  // Remove " - "
        guard !rawProfileName.isEmpty else {
            return nil
        }

        // Check if this is the default profile's name
        if rawProfileName == mapping.defaultProfileName {
            return nil  // Return nil for default profile to keep title short
        }

        // Check if this is a "Person N" placeholder that needs mapping
        if let actualName = mapping.personToName[rawProfileName] {
            return actualName
        }

        // Return the profile name as-is (it's already the custom name)
        return rawProfileName
    }
}

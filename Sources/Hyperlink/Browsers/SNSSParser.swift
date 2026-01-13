import Foundation

/// Parser for Chrome's SNSS (Session/Tabs) binary format
/// Used to extract pinned tab status which isn't available via AppleScript
struct SNSSParser {
    /// Result of parsing a session file - pinned tab count per window
    struct SessionData {
        /// Map of window index (1-based) to number of pinned tabs
        let pinnedCountPerWindow: [Int: Int]
    }

    /// Parse a Chrome session file and extract pinned tab counts per window
    /// - Parameter profilePath: Path to the Chrome profile directory (e.g., "Default" or "Profile 1")
    /// - Returns: Map of window index to pinned tab count, or nil if parsing fails
    static func parsePinnedTabs(profilePath: String) -> [Int: Int]? {
        // Find the most recent Session file
        let sessionsDir = (profilePath as NSString).appendingPathComponent("Sessions")
        guard let sessionFile = findMostRecentSessionFile(in: sessionsDir) else {
            return nil
        }

        guard let data = FileManager.default.contents(atPath: sessionFile) else {
            return nil
        }

        return parseSessionData(data)
    }

    /// Find the most recent Session_* file in the Sessions directory
    private static func findMostRecentSessionFile(in directory: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        // Find Session_* files (not Tabs_*)
        let sessionFiles = contents
            .filter { $0.hasPrefix("Session_") }
            .map { (directory as NSString).appendingPathComponent($0) }

        // Return the most recently modified one
        return sessionFiles
            .compactMap { path -> (String, Date)? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let modDate = attrs[.modificationDate] as? Date else {
                    return nil
                }
                return (path, modDate)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Parse SNSS session data and extract pinned tab counts per window
    /// Note: Window correlation is complex, so we count total pinned tabs per profile
    /// and assign to window 1 (pinned tabs are always in the frontmost window anyway)
    private static func parseSessionData(_ data: Data) -> [Int: Int]? {
        var offset = 0

        // Verify header: "SNSS" magic + version
        guard data.count >= 8 else { return nil }

        let magic = String(data: data[0..<4], encoding: .ascii)
        guard magic == "SNSS" else { return nil }

        let version = BinaryReader.readUInt32(from: data, at: 4)
        guard version >= 1 && version <= 3 else { return nil }

        offset = 8

        // Track final pinned state per tab (last state wins)
        var tabPinnedState: [UInt32: Bool] = [:]

        // Parse commands
        while offset + 3 <= data.count {
            let size = BinaryReader.readUInt16(from: data, at: offset)
            if size == 0 { break }

            let cmdId = data[offset + 2]
            let payloadStart = offset + 3
            let payloadSize = Int(size) - 1

            guard payloadStart + payloadSize <= data.count else { break }

            let payload = data[payloadStart..<(payloadStart + payloadSize)]

            if cmdId == 12 {  // kCommandSetPinnedState
                if let (tabId, pinned) = parsePinnedStateCommand(payload) {
                    tabPinnedState[tabId] = pinned
                }
            }

            offset += Int(size) + 2  // size field (2 bytes) + command data
        }

        // Count total pinned tabs
        let pinnedCount = tabPinnedState.values.filter { $0 }.count

        // Return count for window 1 (pinned tabs are at the start of the window)
        if pinnedCount > 0 {
            return [1: pinnedCount]
        }
        return [:]
    }

    /// Parse command 12 (SetPinnedState): tab_id (4 bytes) + pinned (1 byte)
    private static func parsePinnedStateCommand(_ payload: Data.SubSequence) -> (UInt32, Bool)? {
        guard payload.count >= 5 else { return nil }
        let tabId = BinaryReader.readUInt32(fromSlice: payload, at: payload.startIndex)
        let pinned = payload[payload.startIndex + 4] != 0
        return (tabId, pinned)
    }

}

// MARK: - Binary Reading Helpers

private enum BinaryReader {
    static func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    static func readUInt32(fromSlice slice: Data.SubSequence, at index: Data.Index) -> UInt32 {
        let offset = slice.distance(from: slice.startIndex, to: index)
        return readUInt32(from: Data(slice), at: offset)
    }
}

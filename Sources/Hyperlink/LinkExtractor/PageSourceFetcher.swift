import Foundation

/// Errors that can occur when fetching page source
enum PageSourceError: Error, CustomStringConvertible {
    case browserNotSupported(String)
    case scriptError(String)
    case permissionDenied
    case httpFetchFailed(String)
    case noSource

    var description: String {
        switch self {
        case .browserNotSupported(let browser):
            return "\(browser) does not support page source fetching"
        case .scriptError(let message):
            return "Script error: \(message)"
        case .permissionDenied:
            return "Permission denied. Enable 'Allow JavaScript from Apple Events' in the browser's Developer menu."
        case .httpFetchFailed(let message):
            return "HTTP fetch failed: \(message)"
        case .noSource:
            return "Could not retrieve page source"
        }
    }
}

/// Result of fetching page source
struct PageSourceResult {
    let html: String
    let usedHTTPFallback: Bool
}

/// Fetches page source from browser tabs
enum PageSourceFetcher {
    /// Fetches the HTML source of a tab
    /// - Parameters:
    ///   - browserName: The browser's display name (e.g., "Safari", "Google Chrome")
    ///   - bundleIdentifier: The browser's bundle identifier
    ///   - windowIndex: 1-based window index
    ///   - tabIndex: 1-based tab index
    ///   - tabURL: The URL of the tab (for HTTP fallback)
    /// - Returns: The page source result
    static func fetchSource(
        browserName: String,
        bundleIdentifier: String,
        windowIndex: Int,
        tabIndex: Int,
        tabURL: URL,
        onFallback: (@Sendable () -> Void)? = nil
    ) async throws -> PageSourceResult {
        // Try browser-specific methods first, running on background thread
        // to avoid blocking the main thread with AppleScript execution
        do {
            let html = try await fetchFromBrowserAsync(
                browserName: browserName,
                bundleIdentifier: bundleIdentifier,
                windowIndex: windowIndex,
                tabIndex: tabIndex
            )
            return PageSourceResult(html: html, usedHTTPFallback: false)
        } catch PageSourceError.browserNotSupported {
            // Fall through to HTTP
        } catch PageSourceError.permissionDenied {
            // Fall through to HTTP for Chromium without JS enabled
        } catch {
            // For other errors (including timeout), try HTTP fallback
        }

        // Notify caller we're falling back to HTTP
        onFallback?()

        // HTTP fallback
        let html = try await fetchViaHTTP(url: tabURL)
        return PageSourceResult(html: html, usedHTTPFallback: true)
    }

    /// Runs the browser fetch on a background queue with timeout
    private static func fetchFromBrowserAsync(
        browserName: String,
        bundleIdentifier: String,
        windowIndex: Int,
        tabIndex: Int
    ) async throws -> String {
        let timeoutSeconds = 10.0

        return try await withCheckedThrowingContinuation { continuation in
            // Use a class to track whether we've already resumed
            final class State: @unchecked Sendable {
                var hasResumed = false
                let lock = NSLock()

                func tryResume(with result: Result<String, Error>, continuation: CheckedContinuation<String, Error>) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(with: result)
                }
            }

            let state = State()

            // Run fetch on background queue
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let html = try fetchFromBrowser(
                        browserName: browserName,
                        bundleIdentifier: bundleIdentifier,
                        windowIndex: windowIndex,
                        tabIndex: tabIndex
                    )
                    state.tryResume(with: .success(html), continuation: continuation)
                } catch {
                    state.tryResume(with: .failure(error), continuation: continuation)
                }
            }

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                state.tryResume(
                    with: .failure(PageSourceError.scriptError("Timed out after \(Int(timeoutSeconds))s")),
                    continuation: continuation
                )
            }
        }
    }

    private static func fetchFromBrowser(
        browserName: String,
        bundleIdentifier: String,
        windowIndex: Int,
        tabIndex: Int
    ) throws -> String {
        switch bundleIdentifier {
        case "com.apple.Safari":
            return try fetchFromSafari(windowIndex: windowIndex, tabIndex: tabIndex)
        case "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac":
            return try fetchFromChromium(
                appName: chromiumAppName(for: bundleIdentifier),
                windowIndex: windowIndex,
                tabIndex: tabIndex
            )
        default:
            throw PageSourceError.browserNotSupported(browserName)
        }
    }

    private static func chromiumAppName(for bundleID: String) -> String {
        switch bundleID {
        case "com.google.Chrome": return "Google Chrome"
        case "company.thebrowser.Browser": return "Arc"
        case "com.brave.Browser": return "Brave Browser"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        default: return "Google Chrome"
        }
    }

    private static func fetchFromSafari(windowIndex: Int, tabIndex: Int) throws -> String {
        let script = """
            tell application "Safari"
                return source of tab \(tabIndex) of window \(windowIndex)
            end tell
            """

        return try AppleScriptRunner.run(script)
    }

    private static func fetchFromChromium(appName: String, windowIndex: Int, tabIndex: Int) throws -> String {
        // Chromium browsers need "Allow JavaScript from Apple Events" enabled
        let script = """
            tell application "\(appName)"
                set theTab to tab \(tabIndex) of window \(windowIndex)
                return execute theTab javascript "document.documentElement.outerHTML"
            end tell
            """

        do {
            return try AppleScriptRunner.run(script)
        } catch LinkSourceError.scriptError(let message) {
            // Check for permission-related errors
            if message.contains("not allowed") || message.contains("-1743") {
                throw PageSourceError.permissionDenied
            }
            throw PageSourceError.scriptError(message)
        }
    }

    private static func fetchViaHTTP(url: URL) async throws -> String {
        guard url.scheme == "http" || url.scheme == "https" else {
            throw PageSourceError.httpFetchFailed("URL scheme not supported: \(url.scheme ?? "none")")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw PageSourceError.httpFetchFailed("HTTP \(httpResponse.statusCode)")
            }

            // Try UTF-8, fall back to Latin-1
            if let html = String(data: data, encoding: .utf8) {
                return html
            } else if let html = String(data: data, encoding: .isoLatin1) {
                return html
            } else {
                throw PageSourceError.httpFetchFailed("Could not decode response")
            }
        } catch let error as PageSourceError {
            throw error
        } catch {
            throw PageSourceError.httpFetchFailed(error.localizedDescription)
        }
    }
}

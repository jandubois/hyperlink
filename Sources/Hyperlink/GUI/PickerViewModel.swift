import SwiftUI
import Combine

/// View model for the picker
@MainActor
class PickerViewModel: ObservableObject {
    @Published var browsers: [BrowserData] = []
    @Published var selectedBrowserIndex: Int = 0
    @Published var searchText: String = ""
    @Published var selectedTabs: Set<TabIdentifier> = []
    @Published var highlightedIndex: Int? = nil
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var permissionDenied: Bool = false

    /// Whether settings or help overlays are shown (used by keyboard handler)
    @Published var isShowingOverlay: Bool = false

    /// Whether the search field has focus (vs the tab list)
    @Published var searchFieldHasFocus: Bool = false

    /// The bundle ID of the app that was frontmost before Hyperlink opened
    let targetAppBundleID: String?

    let preferences = Preferences.shared

    init(targetAppBundleID: String? = nil) {
        self.targetAppBundleID = targetAppBundleID
    }

    struct BrowserData: Identifiable {
        let id = UUID()
        let name: String
        let icon: NSImage
        let windows: [WindowInfo]
    }

    struct TabIdentifier: Hashable {
        let browserIndex: Int
        let windowIndex: Int
        let tabIndex: Int
    }

    var currentWindows: [WindowInfo] {
        guard selectedBrowserIndex < browsers.count else { return [] }
        return browsers[selectedBrowserIndex].windows
    }

    var allCurrentTabs: [TabInfo] {
        currentWindows.flatMap { $0.tabs }
    }

    var filteredTabs: [TabInfo] {
        let tabs = allCurrentTabs
        if searchText.isEmpty {
            return tabs
        }
        let query = searchText.lowercased()
        return tabs.filter { tab in
            tab.title.lowercased().contains(query) ||
            tab.url.absoluteString.lowercased().contains(query)
        }
    }

    /// Synchronous version for use when async Tasks aren't running
    func loadBrowsersSync() {
        isLoading = true
        errorMessage = nil
        permissionDenied = false

        // Use mock data if loaded
        if MockDataStore.isActive {
            loadFromMockData()
            return
        }

        // Check for Accessibility permission
        if !PermissionChecker.hasAccessibilityPermission {
            PermissionChecker.promptForAccessibilityIfNeeded()
            // Brief pause to let user respond
            Thread.sleep(forTimeInterval: 0.5)

            if !PermissionChecker.hasAccessibilityPermission {
                permissionDenied = true
                errorMessage = "Accessibility permission required"
                isLoading = false
                return
            }
        }

        let runningBrowsers = BrowserDetector.runningBrowsers()
        if runningBrowsers.isEmpty {
            errorMessage = "No browsers running"
            isLoading = false
            return
        }

        var browserDataList: [BrowserData] = []
        var lastError: Error?

        for browser in runningBrowsers {
            do {
                let windows = try BrowserRegistry.windowsSync(for: browser)
                if !windows.isEmpty {
                    let source = BrowserRegistry.source(for: browser)
                    browserDataList.append(BrowserData(
                        name: source.name,
                        icon: source.icon,
                        windows: windows
                    ))
                }
            } catch let error as LinkSourceError {
                if case .permissionDenied = error {
                    permissionDenied = true
                    errorMessage = "Accessibility permission required"
                    isLoading = false
                    return
                }
                lastError = error
            } catch {
                lastError = error
            }
        }

        if browserDataList.isEmpty {
            if let error = lastError {
                errorMessage = "Failed to read tabs: \(error.localizedDescription)"
            } else {
                errorMessage = "No tabs found"
            }
            isLoading = false
            return
        }

        browsers = browserDataList
        selectedBrowserIndex = 0

        // Highlight the active tab, or first tab if no active tab
        if let activeIndex = filteredTabs.firstIndex(where: { $0.isActive }) {
            highlightedIndex = activeIndex
        } else if !filteredTabs.isEmpty {
            highlightedIndex = 0
        }

        isLoading = false
    }

    /// Load browser data from mock data store
    private func loadFromMockData() {
        let mockSources = MockDataStore.mockSources()
        if mockSources.isEmpty {
            errorMessage = "No browsers in mock data"
            isLoading = false
            return
        }

        var browserDataList: [BrowserData] = []

        for source in mockSources {
            do {
                let windows = try source.windowsSync()
                if !windows.isEmpty {
                    browserDataList.append(BrowserData(
                        name: source.name,
                        icon: source.icon,
                        windows: windows
                    ))
                }
            } catch {
                // Mock sources shouldn't fail, but handle gracefully
            }
        }

        if browserDataList.isEmpty {
            errorMessage = "No tabs found in mock data"
            isLoading = false
            return
        }

        browsers = browserDataList
        selectedBrowserIndex = 0

        // Highlight the active tab, or first tab if no active tab
        if let activeIndex = filteredTabs.firstIndex(where: { $0.isActive }) {
            highlightedIndex = activeIndex
        } else if !filteredTabs.isEmpty {
            highlightedIndex = 0
        }

        isLoading = false
    }

    func loadBrowsers() async {
        isLoading = true
        errorMessage = nil
        permissionDenied = false
        defer { isLoading = false }

        // Use mock data if loaded
        if MockDataStore.isActive {
            loadFromMockData()
            return
        }

        // Check for Accessibility permission
        if !PermissionChecker.hasAccessibilityPermission {
            PermissionChecker.promptForAccessibilityIfNeeded()
            // Give a moment for permission to be granted
            try? await Task.sleep(for: .milliseconds(500))

            if !PermissionChecker.hasAccessibilityPermission {
                permissionDenied = true
                errorMessage = "Accessibility permission required"
                return
            }
        }

        let runningBrowsers = BrowserDetector.runningBrowsers()
        if runningBrowsers.isEmpty {
            errorMessage = "No browsers running"
            return
        }

        var browserDataList: [BrowserData] = []
        var lastError: Error?

        for browser in runningBrowsers {
            let source = BrowserRegistry.source(for: browser)
            do {
                let windows = try await source.windows()
                if !windows.isEmpty {
                    browserDataList.append(BrowserData(
                        name: source.name,
                        icon: source.icon,
                        windows: windows
                    ))
                }
            } catch let error as LinkSourceError {
                if case .permissionDenied = error {
                    permissionDenied = true
                    errorMessage = "Accessibility permission required"
                    return
                }
                lastError = error
            } catch {
                lastError = error
            }
        }

        if browserDataList.isEmpty {
            if let error = lastError {
                errorMessage = "Failed to read tabs: \(error.localizedDescription)"
            } else {
                errorMessage = "No tabs found"
            }
            return
        }

        browsers = browserDataList

        // Select the first browser (frontmost)
        selectedBrowserIndex = 0

        // Highlight the active tab, or first tab if no active tab
        if let activeIndex = filteredTabs.firstIndex(where: { $0.isActive }) {
            highlightedIndex = activeIndex
        } else if !filteredTabs.isEmpty {
            highlightedIndex = 0
        }
    }

    func moveHighlight(by delta: Int) {
        let count = filteredTabs.count
        guard count > 0 else { return }

        let current = highlightedIndex ?? -1
        var newIndex = current + delta

        if newIndex < 0 {
            newIndex = count - 1
        } else if newIndex >= count {
            newIndex = 0
        }

        highlightedIndex = newIndex
    }

    func switchBrowser(by delta: Int) {
        guard browsers.count > 1 else { return }

        var newIndex = selectedBrowserIndex + delta
        if newIndex < 0 {
            newIndex = browsers.count - 1
        } else if newIndex >= browsers.count {
            newIndex = 0
        }

        selectedBrowserIndex = newIndex
        // Note: selectedTabs cleared and highlightActiveTab called via onChange in PickerView
    }

    func highlightActiveTab() {
        if let activeIndex = filteredTabs.firstIndex(where: { $0.isActive }) {
            highlightedIndex = activeIndex
        } else if !filteredTabs.isEmpty {
            highlightedIndex = 0
        } else {
            highlightedIndex = nil
        }
    }

    func toggleSelection(at index: Int) {
        guard index < filteredTabs.count else { return }
        let tab = filteredTabs[index]
        let identifier = tabIdentifier(for: tab)

        if selectedTabs.contains(identifier) {
            selectedTabs.remove(identifier)
        } else {
            selectedTabs.insert(identifier)
        }
    }

    /// Returns the number of currently visible tabs that are selected
    var selectedFilteredTabsCount: Int {
        filteredTabs.filter { tab in
            selectedTabs.contains(tabIdentifier(for: tab))
        }.count
    }

    /// Returns true if all visible tabs are selected
    var allFilteredTabsSelected: Bool {
        guard !filteredTabs.isEmpty else { return false }
        return selectedFilteredTabsCount == filteredTabs.count
    }

    /// Returns true if some (but not all) visible tabs are selected
    var someFilteredTabsSelected: Bool {
        let count = selectedFilteredTabsCount
        return count > 0 && count < filteredTabs.count
    }

    /// Select all currently visible (filtered) tabs
    func selectAllFilteredTabs() {
        for tab in filteredTabs {
            let identifier = tabIdentifier(for: tab)
            selectedTabs.insert(identifier)
        }
    }

    /// Deselect all currently visible (filtered) tabs
    func deselectAllFilteredTabs() {
        for tab in filteredTabs {
            let identifier = tabIdentifier(for: tab)
            selectedTabs.remove(identifier)
        }
    }

    /// Toggle select all / deselect all
    func toggleSelectAll() {
        if allFilteredTabsSelected {
            deselectAllFilteredTabs()
        } else {
            selectAllFilteredTabs()
        }
    }

    func copyAndDismiss(tab: TabInfo) {
        let engine = TransformEngine(
            settings: preferences.transformSettings,
            targetBundleID: targetAppBundleID
        )
        let result = engine.apply(title: tab.title, url: tab.url)
        ClipboardWriter.write(title: result.title, url: tab.url, transformedURL: result.url)
    }

    func copySelected() {
        let tabs = filteredTabs.enumerated().compactMap { index, tab -> TabInfo? in
            let identifier = tabIdentifier(for: tab)
            return selectedTabs.contains(identifier) ? tab : nil
        }

        guard !tabs.isEmpty else { return }

        let engine = TransformEngine(
            settings: preferences.transformSettings,
            targetBundleID: targetAppBundleID
        )
        let format = preferences.multiSelectionFormat
        ClipboardWriter.write(tabs, format: format, engine: engine)
    }

    private func tabIdentifier(for tab: TabInfo) -> TabIdentifier {
        // Find which window this tab belongs to
        for (windowIndex, window) in currentWindows.enumerated() {
            if let tabIndex = window.tabs.firstIndex(where: { $0.index == tab.index && $0.url == tab.url }) {
                return TabIdentifier(
                    browserIndex: selectedBrowserIndex,
                    windowIndex: windowIndex,
                    tabIndex: tabIndex
                )
            }
        }
        // Fallback
        return TabIdentifier(browserIndex: selectedBrowserIndex, windowIndex: 0, tabIndex: tab.index)
    }
}

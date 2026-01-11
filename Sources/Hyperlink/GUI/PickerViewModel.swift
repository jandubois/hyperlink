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

    /// Whether a sub-overlay (like app picker popover) is shown inside the main overlay
    @Published var isShowingSubOverlay: Bool = false

    /// Whether the search field has focus (vs the tab list)
    @Published var searchFieldHasFocus: Bool = false

    /// Whether hover previews are enabled (disabled during keyboard navigation)
    @Published var hoverPreviewsEnabled: Bool = true

    /// Sort order per browser/source (keyed by index in allBrowserData)
    @Published var sortOrders: [Int: SortOrder] = [:]

    /// Sort direction per browser/source (keyed by index in allBrowserData)
    @Published var sortAscendings: [Int: Bool] = [:]

    /// Current sort order for the selected browser
    var sortOrder: SortOrder {
        get { sortOrders[selectedBrowserIndex] ?? .original }
        set { sortOrders[selectedBrowserIndex] = newValue }
    }

    /// Current sort direction for the selected browser
    var sortAscending: Bool {
        get { sortAscendings[selectedBrowserIndex] ?? true }
        set { sortAscendings[selectedBrowserIndex] = newValue }
    }

    /// Toast message to display (auto-dismisses)
    @Published var toastMessage: String? = nil

    /// Extracted link sources (pseudo-browsers)
    @Published var extractedSources: [ExtractedLinksSource] = [] {
        didSet {
            // Subscribe to changes in nested ObservableObjects so favicon updates propagate
            setupExtractedSourcesObservation()
        }
    }

    /// Subscriptions for nested ObservableObject changes
    private var extractedSourceCancellables: [AnyCancellable] = []

    /// Whether link extraction is in progress
    @Published var isExtracting: Bool = false

    /// Status message shown during extraction
    @Published var extractionStatus: String = "Extracting links..."

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

    enum SortOrder: String, CaseIterable {
        case original = "Original"
        case byURL = "By URL"
        case byTitle = "By Title"
    }

    var currentWindows: [WindowInfo] {
        let allData = allBrowserData
        guard selectedBrowserIndex < allData.count else { return [] }
        return allData[selectedBrowserIndex].windows
    }

    var allCurrentTabs: [TabInfo] {
        currentWindows.flatMap { $0.tabs }
    }

    var filteredTabs: [TabInfo] {
        var tabs = allCurrentTabs
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            tabs = tabs.filter { tab in
                tab.title.lowercased().contains(query) ||
                tab.url.absoluteString.lowercased().contains(query)
            }
        }
        return sortTabs(tabs)
    }

    private func sortTabs(_ tabs: [TabInfo]) -> [TabInfo] {
        guard sortOrder != .original else { return tabs }

        let sorted = tabs.sorted { a, b in
            let comparison: ComparisonResult
            switch sortOrder {
            case .original:
                return false // Won't reach here due to guard
            case .byURL:
                // Compare URLs ignoring protocol
                let urlA = a.url.absoluteString.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                let urlB = b.url.absoluteString.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression)
                comparison = urlA.localizedCaseInsensitiveCompare(urlB)
            case .byTitle:
                comparison = a.title.localizedCaseInsensitiveCompare(b.title)
            }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        return sorted
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

        hoverPreviewsEnabled = false
        highlightedIndex = newIndex
    }

    func moveHighlightToStart() {
        guard !filteredTabs.isEmpty else { return }
        hoverPreviewsEnabled = false
        highlightedIndex = 0
    }

    func moveHighlightToEnd() {
        guard !filteredTabs.isEmpty else { return }
        hoverPreviewsEnabled = false
        highlightedIndex = filteredTabs.count - 1
    }

    func moveHighlightByPage(_ direction: Int) {
        let pageSize = 10
        let count = filteredTabs.count
        guard count > 0 else { return }

        let current = highlightedIndex ?? 0
        var newIndex = current + (direction * pageSize)
        newIndex = max(0, min(count - 1, newIndex))

        hoverPreviewsEnabled = false
        highlightedIndex = newIndex
    }

    func switchBrowser(by delta: Int) {
        let count = allBrowserData.count
        guard count > 1 else { return }

        var newIndex = selectedBrowserIndex + delta
        if newIndex < 0 {
            newIndex = count - 1
        } else if newIndex >= count {
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

    // MARK: - Link Extraction

    /// Number of extracted sources (pseudo-browsers at the start of the browser list)
    var extractedSourceCount: Int {
        extractedSources.count
    }

    /// Whether the currently selected browser is an extracted source
    var isViewingExtractedSource: Bool {
        selectedBrowserIndex < extractedSourceCount
    }

    /// The currently selected extracted source, if any
    var currentExtractedSource: ExtractedLinksSource? {
        guard isViewingExtractedSource else { return nil }
        return extractedSources[selectedBrowserIndex]
    }

    /// Close an extracted source at the given index
    func closeExtractedSource(at index: Int) {
        guard index < extractedSources.count else { return }

        extractedSources.remove(at: index)

        // Adjust selected index if needed
        if selectedBrowserIndex >= extractedSources.count + browsers.count {
            selectedBrowserIndex = max(0, extractedSources.count + browsers.count - 1)
        } else if selectedBrowserIndex > index {
            selectedBrowserIndex -= 1
        } else if selectedBrowserIndex == index && !extractedSources.isEmpty {
            // Stay at same index (now pointing to next item)
        } else if selectedBrowserIndex == index && extractedSources.isEmpty {
            // Switch to first browser
            selectedBrowserIndex = 0
        }

        selectedTabs.removeAll()
        highlightActiveTab()
    }

    /// Close the currently selected extracted source (if viewing one)
    func closeCurrentExtractedSource() {
        guard isViewingExtractedSource else { return }
        closeExtractedSource(at: selectedBrowserIndex)
    }

    /// All browser data including extracted sources
    var allBrowserData: [BrowserData] {
        let extractedBrowsers = extractedSources.map { source in
            BrowserData(
                name: source.displayName,
                icon: source.favicon ?? NSImage(systemSymbolName: "link", accessibilityDescription: "Extracted links") ?? NSImage(),
                windows: [source.asWindowInfo()]
            )
        }
        return extractedBrowsers + browsers
    }

    /// Extract links from the highlighted tab
    func extractLinksFromHighlightedTab() {
        guard let index = highlightedIndex,
              index < filteredTabs.count else {
            return
        }
        extractLinksFromTab(filteredTabs[index])
    }

    /// Extract links from a specific tab in the current browser
    func extractLinksFromTab(_ tab: TabInfo) {
        // Check if viewing an extracted source (use HTTP-only fetch)
        if selectedBrowserIndex < extractedSourceCount {
            extractLinksViaHTTP(from: tab)
            return
        }

        // Browser tab - find window and tab indices
        guard let browserData = browsers[safe: selectedBrowserIndex - extractedSourceCount] else {
            return
        }

        // Find window and tab indices using the actual indices from the browser
        var windowIndex = 1
        var tabIndex = 1
        for window in browserData.windows {
            if let foundTab = window.tabs.first(where: { $0.url == tab.url && $0.title == tab.title }) {
                windowIndex = window.index  // Use actual window index from browser
                tabIndex = foundTab.index   // Use actual tab index from browser
                break
            }
        }

        // Get bundle identifier for the browser
        let browserBundleID = bundleIdentifier(for: browserData.name)

        extractLinks(
            from: tab,
            browserName: browserData.name,
            bundleIdentifier: browserBundleID,
            windowIndex: windowIndex,
            tabIndex: tabIndex
        )
    }

    /// Extract links from a specific tab
    func extractLinks(
        from tab: TabInfo,
        browserName: String,
        bundleIdentifier: String,
        windowIndex: Int,
        tabIndex: Int
    ) {
        // Check if we already have an extracted source for this URL
        if let existingIndex = extractedSources.firstIndex(where: { $0.sourceURL == tab.url }) {
            selectedBrowserIndex = existingIndex
            selectedTabs.removeAll()
            highlightedIndex = 0
            return
        }

        guard !isExtracting else { return }
        isExtracting = true
        extractionStatus = "Getting page from \(browserName)..."

        Task {
            defer { isExtracting = false }

            do {
                // Fetch page source
                let result = try await PageSourceFetcher.fetchSource(
                    browserName: browserName,
                    bundleIdentifier: bundleIdentifier,
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    tabURL: tab.url,
                    onFallback: { [weak self] in
                        Task { @MainActor in
                            self?.extractionStatus = "Fetching URL directly..."
                        }
                    }
                )

                extractionStatus = "Parsing links..."

                if result.usedHTTPFallback {
                    showToast("Used direct fetch (no auth)")
                }

                // Parse links from HTML
                let parsedLinks = HTMLLinkParser.extractLinks(from: result.html, baseURL: tab.url)

                if parsedLinks.isEmpty {
                    showToast("No links found on page")
                    return
                }

                // Create extracted source
                let source = ExtractedLinksSource.create(
                    from: parsedLinks,
                    sourceURL: tab.url,
                    sourceTitle: tab.title
                )

                // Add to list and select it
                extractedSources.insert(source, at: 0)
                selectedBrowserIndex = 0
                selectedTabs.removeAll()
                highlightedIndex = 0

                // Start fetching titles and favicon
                source.startTitleFetching()
                source.fetchFavicon()

            } catch {
                showToast("Failed: \(error.localizedDescription)")
            }
        }
    }

    /// Extract links from a URL using HTTP fetch only (for extracted sources)
    private func extractLinksViaHTTP(from tab: TabInfo) {
        // Check if we already have an extracted source for this URL
        if let existingIndex = extractedSources.firstIndex(where: { $0.sourceURL == tab.url }) {
            selectedBrowserIndex = existingIndex
            selectedTabs.removeAll()
            highlightedIndex = 0
            return
        }

        guard !isExtracting else { return }
        isExtracting = true
        extractionStatus = "Fetching page..."

        Task {
            defer { isExtracting = false }

            do {
                let result = try await PageSourceFetcher.fetchSource(from: tab.url)

                extractionStatus = "Parsing links..."

                // Parse links from HTML
                let parsedLinks = HTMLLinkParser.extractLinks(from: result.html, baseURL: tab.url)

                if parsedLinks.isEmpty {
                    showToast("No links found on page")
                    return
                }

                // Create extracted source
                let source = ExtractedLinksSource.create(
                    from: parsedLinks,
                    sourceURL: tab.url,
                    sourceTitle: tab.title
                )

                // Add to list and select it
                extractedSources.insert(source, at: 0)
                selectedBrowserIndex = 0
                selectedTabs.removeAll()
                highlightedIndex = 0

                // Start fetching titles and favicon
                source.startTitleFetching()
                source.fetchFavicon()

            } catch {
                showToast("Failed: \(error.localizedDescription)")
            }
        }
    }

    /// Open a tab's URL in the default browser
    func openInBrowser(tab: TabInfo) {
        NSWorkspace.shared.open(tab.url)
    }

    /// Show a toast message that auto-dismisses
    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    /// Get bundle identifier for a browser name
    private func bundleIdentifier(for browserName: String) -> String {
        switch browserName.lowercased() {
        case "safari": return "com.apple.Safari"
        case "google chrome", "chrome": return "com.google.Chrome"
        case "arc": return "company.thebrowser.Browser"
        case "brave", "brave browser": return "com.brave.Browser"
        case "microsoft edge", "edge": return "com.microsoft.edgemac"
        case "orion": return "com.kagi.kagimacOS"
        default: return "com.apple.Safari"
        }
    }

    /// Subscribe to objectWillChange of nested ExtractedLinksSource objects
    /// so that changes (like favicon updates) trigger UI refresh
    private func setupExtractedSourcesObservation() {
        extractedSourceCancellables.removeAll()
        for source in extractedSources {
            source.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &extractedSourceCancellables)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

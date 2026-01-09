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

    private let preferences = Preferences.shared

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

    func loadBrowsers() async {
        isLoading = true
        defer { isLoading = false }

        var browserDataList: [BrowserData] = []

        for browser in BrowserDetector.runningBrowsers() {
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
            } catch {
                // Skip browsers that fail
            }
        }

        browsers = browserDataList

        // Select the first browser (frontmost)
        selectedBrowserIndex = 0

        // Highlight first tab
        if !filteredTabs.isEmpty {
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

    func copyAndDismiss(tab: TabInfo) {
        let transform = preferences.titleTransform
        ClipboardWriter.write(tab, transform: transform)
    }

    func copySelected() {
        let tabs = filteredTabs.enumerated().compactMap { index, tab -> TabInfo? in
            let identifier = tabIdentifier(for: tab)
            return selectedTabs.contains(identifier) ? tab : nil
        }

        guard !tabs.isEmpty else { return }

        let transform = preferences.titleTransform
        let format = preferences.multiSelectionFormat
        ClipboardWriter.write(tabs, format: format, transform: transform)
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

import Testing
import AppKit
@testable import hyperlink

@Suite("PickerViewModel Tests")
struct PickerViewModelTests {

    // Helper to create test tabs
    static func makeTabs(_ titles: [String], activeIndex: Int = 0) -> [TabInfo] {
        titles.enumerated().map { index, title in
            TabInfo(
                index: index + 1,
                title: title,
                url: URL(string: "https://example.com/\(index)")!,
                isActive: index == activeIndex
            )
        }
    }

    static func makeWindow(tabs: [TabInfo], index: Int = 1) -> WindowInfo {
        WindowInfo(index: index, name: nil, tabs: tabs)
    }

    static func makeBrowserData(name: String, windows: [WindowInfo]) -> PickerViewModel.BrowserData {
        PickerViewModel.BrowserData(
            name: name,
            icon: NSImage(),
            windows: windows
        )
    }

    @Test("Grouping defaults to off regardless of tab count")
    @MainActor
    func groupingDefaultsOff() {
        let viewModel = PickerViewModel()
        // Use enough tabs that any count-based auto-grouping would trigger.
        let tabs = Self.makeTabs((1...15).map { "Tab \($0)" })
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [Self.makeWindow(tabs: tabs)])]

        #expect(viewModel.filteredTabs.count == 15)
        #expect(viewModel.isGroupingEnabled == false)
    }

    @Test("moveHighlight wraps forward")
    @MainActor
    func moveHighlightWrapsForward() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2", "Tab 3"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]
        viewModel.highlightedIndex = 2  // Last tab

        viewModel.moveHighlight(by: 1)  // Should wrap to 0

        #expect(viewModel.highlightedIndex == 0)
    }

    @Test("moveHighlight wraps backward")
    @MainActor
    func moveHighlightWrapsBackward() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2", "Tab 3"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]
        viewModel.highlightedIndex = 0  // First tab

        viewModel.moveHighlight(by: -1)  // Should wrap to 2

        #expect(viewModel.highlightedIndex == 2)
    }

    @Test("moveHighlight normal navigation")
    @MainActor
    func moveHighlightNormal() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2", "Tab 3"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]
        viewModel.highlightedIndex = 1

        viewModel.moveHighlight(by: 1)
        #expect(viewModel.highlightedIndex == 2)

        viewModel.moveHighlight(by: -1)
        #expect(viewModel.highlightedIndex == 1)
    }

    @Test("filteredTabs returns all when search empty")
    @MainActor
    func filteredTabsNoFilter() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["GitHub", "Google", "Stack Overflow"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]
        viewModel.searchText = ""

        #expect(viewModel.filteredTabs.count == 3)
    }

    @Test("filteredTabs filters by title")
    @MainActor
    func filteredTabsByTitle() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["GitHub", "Google", "Stack Overflow"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]
        viewModel.searchText = "git"

        #expect(viewModel.filteredTabs.count == 1)
        #expect(viewModel.filteredTabs.first?.title == "GitHub")
    }

    @Test("filteredTabs is case insensitive")
    @MainActor
    func filteredTabsCaseInsensitive() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["GitHub", "Google", "Stack Overflow"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]
        viewModel.searchText = "GITHUB"

        #expect(viewModel.filteredTabs.count == 1)
    }

    @Test("toggleSelection adds and removes")
    @MainActor
    func toggleSelection() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]

        #expect(viewModel.selectedTabs.isEmpty)

        viewModel.toggleSelection(at: 0)
        #expect(viewModel.selectedTabs.count == 1)

        viewModel.toggleSelection(at: 1)
        #expect(viewModel.selectedTabs.count == 2)

        viewModel.toggleSelection(at: 0)
        #expect(viewModel.selectedTabs.count == 1)
    }

    @Test("Within-group children re-sort when sortOrder changes")
    @MainActor
    func groupedSortOrderChangesChildOrder() {
        let viewModel = PickerViewModel()
        // 3 tabs on the same host form a single group. Titles and URL paths
        // run in opposite orders, so byTitle and byURL produce different orderings.
        let tabs = [
            TabInfo(index: 1, title: "Charlie", url: URL(string: "https://github.com/a")!, isActive: false),
            TabInfo(index: 2, title: "Bravo",   url: URL(string: "https://github.com/b")!, isActive: false),
            TabInfo(index: 3, title: "Alpha",   url: URL(string: "https://github.com/c")!, isActive: true)
        ]
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [Self.makeWindow(tabs: tabs)])]
        viewModel.isGroupingEnabled = true

        viewModel.sortOrder = .byURL
        let byURLTitles = viewModel.displayItems.compactMap { $0.asTab?.title }
        #expect(byURLTitles == ["Charlie", "Bravo", "Alpha"])

        viewModel.sortOrder = .byTitle
        let byTitleTitles = viewModel.displayItems.compactMap { $0.asTab?.title }
        #expect(byTitleTitles == ["Alpha", "Bravo", "Charlie"])
    }

    @Test("Within-group children preserve original order")
    @MainActor
    func groupedOriginalPreservesBrowserOrder() {
        let viewModel = PickerViewModel()
        // Titles run out of alphabetic order; .original must keep the browser's
        // index order.
        let tabs = [
            TabInfo(index: 1, title: "Charlie", url: URL(string: "https://github.com/x")!, isActive: false),
            TabInfo(index: 2, title: "Alpha",   url: URL(string: "https://github.com/y")!, isActive: false),
            TabInfo(index: 3, title: "Bravo",   url: URL(string: "https://github.com/z")!, isActive: true)
        ]
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [Self.makeWindow(tabs: tabs)])]
        viewModel.isGroupingEnabled = true
        viewModel.sortOrder = .original

        let titles = viewModel.displayItems.compactMap { $0.asTab?.title }
        #expect(titles == ["Charlie", "Alpha", "Bravo"])
    }

    @Test("currentWindows returns windows for selected browser")
    @MainActor
    func currentWindows() {
        let viewModel = PickerViewModel()
        let safariTabs = Self.makeTabs(["Safari Tab"])
        let chromeTabs = Self.makeTabs(["Chrome Tab"])
        viewModel.browsers = [
            Self.makeBrowserData(name: "Safari", windows: [Self.makeWindow(tabs: safariTabs)]),
            Self.makeBrowserData(name: "Chrome", windows: [Self.makeWindow(tabs: chromeTabs)])
        ]

        viewModel.selectedBrowserIndex = 0
        #expect(viewModel.currentWindows.first?.tabs.first?.title == "Safari Tab")

        viewModel.selectedBrowserIndex = 1
        #expect(viewModel.currentWindows.first?.tabs.first?.title == "Chrome Tab")
    }

    @Test("selectAllFilteredTabs selects all visible tabs")
    @MainActor
    func selectAllFilteredTabs() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2", "Tab 3"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]

        #expect(viewModel.selectedTabs.isEmpty)
        #expect(!viewModel.allFilteredTabsSelected)

        viewModel.selectAllFilteredTabs()

        #expect(viewModel.selectedTabs.count == 3)
        #expect(viewModel.allFilteredTabsSelected)
    }

    @Test("deselectAllFilteredTabs deselects all visible tabs")
    @MainActor
    func deselectAllFilteredTabs() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2", "Tab 3"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]

        viewModel.selectAllFilteredTabs()
        #expect(viewModel.selectedTabs.count == 3)

        viewModel.deselectAllFilteredTabs()
        #expect(viewModel.selectedTabs.isEmpty)
        #expect(!viewModel.allFilteredTabsSelected)
    }

    @Test("someFilteredTabsSelected returns true for partial selection")
    @MainActor
    func someFilteredTabsSelected() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2", "Tab 3"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]

        #expect(!viewModel.someFilteredTabsSelected)

        viewModel.toggleSelection(at: 0)
        #expect(viewModel.someFilteredTabsSelected)
        #expect(!viewModel.allFilteredTabsSelected)

        viewModel.selectAllFilteredTabs()
        #expect(!viewModel.someFilteredTabsSelected)
        #expect(viewModel.allFilteredTabsSelected)
    }

    @Test("toggleSelectAll toggles between all and none")
    @MainActor
    func toggleSelectAll() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2"])
        let window = Self.makeWindow(tabs: tabs)
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [window])]

        #expect(viewModel.selectedTabs.isEmpty)

        viewModel.toggleSelectAll()
        #expect(viewModel.allFilteredTabsSelected)

        viewModel.toggleSelectAll()
        #expect(viewModel.selectedTabs.isEmpty)
    }

    @Test("Quick-select follows display order when grouped, not browser order")
    @MainActor
    func quickSelectFollowsGroupedOrder() {
        let viewModel = PickerViewModel()
        // Browser order interleaves the three github tabs with a solo tab.
        // Grouping pulls the github tabs together, ahead of solo.com.
        let tabs = [
            TabInfo(index: 1, title: "gh1",  url: URL(string: "https://github.com/1")!, isActive: false),
            TabInfo(index: 2, title: "solo", url: URL(string: "https://solo.com/x")!, isActive: false),
            TabInfo(index: 3, title: "gh2",  url: URL(string: "https://github.com/2")!, isActive: false),
            TabInfo(index: 4, title: "gh3",  url: URL(string: "https://github.com/3")!, isActive: true)
        ]
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [Self.makeWindow(tabs: tabs)])]
        viewModel.isGroupingEnabled = true

        #expect(viewModel.displayedTabs.map { $0.title } == ["gh1", "gh2", "gh3", "solo"])
        #expect(viewModel.filteredTabs.map { $0.title } == ["gh1", "solo", "gh2", "gh3"])

        // The digit "2" sits beside gh2 on screen, so Ctrl+2 must copy gh2, not solo.
        #expect(viewModel.quickSelectTab(2)?.title == "gh2")
        #expect(viewModel.quickSelectTab(4)?.title == "solo")
        #expect(viewModel.quickSelectTab(5) == nil)
    }

    @Test("Quick-select matches browser order when ungrouped")
    @MainActor
    func quickSelectMatchesFilteredWhenUngrouped() {
        let viewModel = PickerViewModel()
        let tabs = Self.makeTabs(["Tab 1", "Tab 2", "Tab 3"])
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [Self.makeWindow(tabs: tabs)])]

        #expect(viewModel.displayedTabs == viewModel.filteredTabs)
        #expect(viewModel.quickSelectTab(1)?.title == "Tab 1")
    }

    @Test("Quick-select skips group headers")
    @MainActor
    func quickSelectSkipsGroupHeaders() {
        let viewModel = PickerViewModel()
        let tabs = [
            TabInfo(index: 1, title: "gh1", url: URL(string: "https://github.com/1")!, isActive: false),
            TabInfo(index: 2, title: "gh2", url: URL(string: "https://github.com/2")!, isActive: false),
            TabInfo(index: 3, title: "gh3", url: URL(string: "https://github.com/3")!, isActive: false)
        ]
        viewModel.browsers = [Self.makeBrowserData(name: "Safari", windows: [Self.makeWindow(tabs: tabs)])]
        viewModel.isGroupingEnabled = true

        #expect(viewModel.displayItems.contains { $0.isGroupHeader })
        #expect(viewModel.displayedTabs.count == 3)
        #expect(viewModel.quickSelectTab(1)?.title == "gh1")
    }
}

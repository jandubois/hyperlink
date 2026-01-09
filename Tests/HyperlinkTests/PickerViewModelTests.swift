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
}

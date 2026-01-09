import SwiftUI

/// Scrollable list of tabs grouped by window
struct TabListView: View {
    let browserIndex: Int  // Used to force view refresh when browser changes
    let windows: [WindowInfo]
    let filteredTabs: [TabInfo]
    @Binding var selectedTabs: Set<PickerViewModel.TabIdentifier>
    @Binding var highlightedIndex: Int?
    let onSelect: (TabInfo) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredTabs.enumerated()), id: \.offset) { index, tab in
                        TabRowView(
                            tab: tab,
                            index: index,
                            isHighlighted: highlightedIndex == index,
                            isChecked: isTabSelected(tab),
                            onToggleCheck: { toggleSelection(tab) },
                            onSelect: { onSelect(tab) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: highlightedIndex) { oldValue, newValue in
                if let index = newValue {
                    withAnimation {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        .id(browserIndex)  // Force complete refresh when browser changes
    }

    private func isTabSelected(_ tab: TabInfo) -> Bool {
        // Check if this tab is in selectedTabs
        for window in windows.enumerated() {
            if let tabIndex = window.element.tabs.firstIndex(where: { $0.index == tab.index && $0.url == tab.url }) {
                let identifier = PickerViewModel.TabIdentifier(
                    browserIndex: 0, // Will be set by view model
                    windowIndex: window.offset,
                    tabIndex: tabIndex
                )
                if selectedTabs.contains(identifier) {
                    return true
                }
            }
        }
        return false
    }

    private func toggleSelection(_ tab: TabInfo) {
        for window in windows.enumerated() {
            if let tabIndex = window.element.tabs.firstIndex(where: { $0.index == tab.index && $0.url == tab.url }) {
                let identifier = PickerViewModel.TabIdentifier(
                    browserIndex: 0,
                    windowIndex: window.offset,
                    tabIndex: tabIndex
                )
                if selectedTabs.contains(identifier) {
                    selectedTabs.remove(identifier)
                } else {
                    selectedTabs.insert(identifier)
                }
                return
            }
        }
    }
}

/// Individual tab row
struct TabRowView: View {
    let tab: TabInfo
    let index: Int
    let isHighlighted: Bool
    let isChecked: Bool
    let onToggleCheck: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: onToggleCheck) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .foregroundColor(isChecked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            // Number shortcut (1-9)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 16)
            } else {
                Spacer()
                    .frame(width: 16)
            }

            // Active indicator
            if tab.isActive {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            } else {
                Spacer()
                    .frame(width: 6)
            }

            // Favicon
            FaviconView(url: tab.url)
                .frame(width: 16, height: 16)

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(tab.url.absoluteString)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

/// Displays a favicon for a URL, loading asynchronously
struct FaviconView: View {
    let url: URL
    @StateObject private var loader = FaviconLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loader.load(url: url)
        }
    }
}

/// Observable loader for favicon images
@MainActor
class FaviconLoader: ObservableObject {
    @Published var image: NSImage?

    func load(url: URL) {
        image = FaviconCache.shared.favicon(for: url) { [weak self] loadedImage in
            self?.image = loadedImage
        }
    }
}

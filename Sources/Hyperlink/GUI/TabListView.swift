import SwiftUI

/// Scrollable list of tabs grouped by window
struct TabListView: View {
    let browserIndex: Int  // Used to force view refresh when browser changes
    let windows: [WindowInfo]
    let filteredTabs: [TabInfo]
    @Binding var selectedTabs: Set<PickerViewModel.TabIdentifier>
    @Binding var highlightedIndex: Int?
    let onSelect: (TabInfo) -> Void
    var onExtract: ((TabInfo, Int) -> Void)? = nil
    var onOpenInBrowser: ((TabInfo) -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredTabs.enumerated()), id: \.element) { index, tab in
                        TabRowView(
                            tab: tab,
                            index: index,
                            isHighlighted: highlightedIndex == index,
                            isChecked: isTabSelected(tab),
                            onToggleCheck: { toggleSelection(tab) },
                            onSelect: { onSelect(tab) },
                            onExtract: { onExtract?(tab, index) },
                            onOpenInBrowser: { onOpenInBrowser?(tab) }
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
    var onExtract: (() -> Void)? = nil
    var onOpenInBrowser: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var showPreview = false
    @State private var previewMetadata: OpenGraphMetadata?
    @State private var hoverTask: Task<Void, Never>?

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
            .popover(isPresented: $showPreview, arrowEdge: .trailing) {
                LinkPreviewView(url: tab.url, metadata: previewMetadata)
            }

            Spacer()

            // Actions menu (shown on hover)
            if isHovering {
                Menu {
                    Button(action: { onOpenInBrowser?() }) {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    Button(action: { onExtract?() }) {
                        Label("Extract Links", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Actions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                // Start preview fetch after delay
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    let metadata = await OpenGraphCache.shared.fetch(for: tab.url)
                    guard !Task.isCancelled else { return }
                    if metadata != nil {
                        previewMetadata = metadata
                        showPreview = true
                    }
                }
            } else {
                // Cancel pending fetch and hide preview
                hoverTask?.cancel()
                hoverTask = nil
                showPreview = false
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
}

/// Preview popover showing Open Graph metadata
struct LinkPreviewView: View {
    let url: URL
    let metadata: OpenGraphMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // OG Image
            if let imageURL = metadata?.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: 280, maxHeight: 150)
                            .clipped()
                    case .failure:
                        EmptyView()
                    case .empty:
                        ProgressView()
                            .frame(width: 280, height: 100)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Title
            if let title = metadata?.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(.primary)
            }

            // Description
            if let description = metadata?.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 12))
                    .lineLimit(4)
                    .foregroundColor(.secondary)
            }

            // URL
            Text(url.host ?? url.absoluteString)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(width: 300)
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
            // Callback is already on main thread via RunLoop.main.perform
            MainActor.assumeIsolated {
                self?.image = loadedImage
            }
        }
    }
}

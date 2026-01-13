import SwiftUI
import AppKit

/// Preference key to collect row bounds
struct RowBoundsPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [TabInfo: CGRect] = [:]
    static func reduce(value: inout [TabInfo: CGRect], nextValue: () -> [TabInfo: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Manages a floating preview panel that appears to the left of the main window.
///
/// Uses NSPanel to display content outside the main window bounds. Key design decisions:
///
/// - Fresh hosting view each time: We create a new NSHostingView for each show() call.
///   Reusing the hosting view caused stale content to flash briefly when switching rows,
///   because SwiftUI doesn't update synchronously when setting rootView.
///
/// - GeometryReader for size changes: Content size can change after initial display
///   (e.g., when AsyncImage loads). We use onChange(of: geo.size) to reposition the
///   panel whenever the content size changes, keeping it centered on the row.
///
/// - Deferred orderFront: We show the panel in an async block after setting content,
///   giving SwiftUI time to lay out before the panel becomes visible.
///
/// - Screen coordinate conversion: The screenY parameter is in macOS screen coordinates
///   (Y=0 at bottom). We center the panel vertically on this position.
@MainActor
class PreviewPanelController: ObservableObject {
    static let shared = PreviewPanelController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var screenY: CGFloat = 0
    private var windowFrame: NSRect = .zero

    @Published var isVisible = false

    private init() {}

    func show(content: some View, atY screenY: CGFloat) {
        let previewWidth: CGFloat = 300

        guard let mainWindow = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        self.windowFrame = mainWindow.frame
        self.screenY = screenY

        let wrappedContent = AnyView(
            content
                .frame(width: previewWidth)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
                )
                .padding(16)
                .background(
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.size) { _, newSize in
                            PreviewPanelController.shared.reposition(forSize: newSize)
                        }
                    }
                )
        )

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: previewWidth + 32, height: 200),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = false
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false

            self.panel = panel
        }

        // Create fresh hosting view to avoid stale content flashing when switching rows
        let hosting = NSHostingView(rootView: wrappedContent)
        panel?.contentView = hosting
        self.hostingView = hosting

        // Position and show after SwiftUI has laid out content
        DispatchQueue.main.async { [self] in
            reposition(forSize: hosting.fittingSize)

            if !isVisible {
                panel?.orderFront(nil)
                isVisible = true
            }
        }
    }

    func reposition(forSize size: CGSize) {
        guard let panel = panel, size.width > 0, size.height > 0 else { return }

        let x = windowFrame.minX - size.width - 12
        let y = screenY - size.height / 2  // Center vertically on the row

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }
}

/// Scrollable list of tabs grouped by window
struct TabListView: View {
    let browserIndex: Int  // Used to force view refresh when browser changes
    let windows: [WindowInfo]
    let filteredTabs: [TabInfo]
    @Binding var selectedTabs: Set<PickerViewModel.TabIdentifier>
    @Binding var highlightedIndex: Int?
    @Binding var hoverPreviewsEnabled: Bool
    let onSelect: (TabInfo) -> Void
    var onExtract: ((TabInfo, Int) -> Void)? = nil
    var onOpenInBrowser: ((TabInfo) -> Void)? = nil

    // Grouping support
    @ObservedObject var viewModel: PickerViewModel

    // Preview state (lifted up from individual rows)
    @State private var hoveredTab: TabInfo?
    @State private var previewMetadata: OpenGraphMetadata?
    @State private var isLoadingPreview = false
    @State private var previewLoadFailed = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var rowBounds: [TabInfo: CGRect] = [:]

    private let previewNamespace = "tabListPreview"

    /// Cached display items to avoid rebuilding on every render
    @State private var cachedDisplayItems: [PickerViewModel.DisplayItem] = []

    var body: some View {
        let items = viewModel.displayItems

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        displayItemView(item: item, index: index)
                            .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onPreferenceChange(RowBoundsPreferenceKey.self) { bounds in
                rowBounds = bounds
            }
            .onChange(of: highlightedIndex) { oldValue, newValue in
                if let index = newValue, index < items.count {
                    // Use nil anchor to scroll minimally (only if item is off-screen)
                    proxy.scrollTo(items[index].id, anchor: nil)
                }
            }
        }
        .id(browserIndex)  // Force complete refresh when browser changes
        .onChange(of: browserIndex) { _, _ in
            clearPreviewState()
        }
        .onChange(of: hoverPreviewsEnabled) { _, enabled in
            if !enabled {
                PreviewPanelController.shared.hide()
            }
        }
        .onDisappear {
            PreviewPanelController.shared.hide()
        }
    }

    /// Renders a single display item (either group header or tab row)
    @ViewBuilder
    private func displayItemView(item: PickerViewModel.DisplayItem, index: Int) -> some View {
        switch item {
        case .groupHeader(let group, let indentLevel):
            GroupHeaderView(
                group: group,
                isCollapsed: viewModel.isGroupCollapsed(group.id),
                isFullySelected: viewModel.isGroupFullySelected(group),
                isPartiallySelected: viewModel.isGroupPartiallySelected(group),
                indentLevel: indentLevel,
                isHighlighted: highlightedIndex == index,
                onToggleCollapsed: { viewModel.toggleGroupCollapsed(group.id) },
                onToggleSelection: { viewModel.toggleGroupSelection(group) }
            )
        case .tab(let tab, let indentLevel):
            tabRowView(tab: tab, index: index, indentLevel: indentLevel)
        }
    }

    /// Single tab row with indentation
    @ViewBuilder
    private func tabRowView(tab: TabInfo, index: Int, indentLevel: Int) -> some View {
        TabRowView(
            tab: tab,
            index: index,
            isHighlighted: highlightedIndex == index,
            isChecked: isTabSelected(tab),
            isPinned: isTabPinned(tab),
            onToggleCheck: { toggleSelection(tab) },
            onSelect: { onSelect(tab) },
            onExtract: { onExtract?(tab, index) },
            onOpenInBrowser: { onOpenInBrowser?(tab) },
            onHover: { hovering in handleRowHover(tab: tab, hovering: hovering) }
        )
        .padding(.leading, CGFloat(indentLevel) * 16)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: RowBoundsPreferenceKey.self,
                    value: [tab: geo.frame(in: .global)]
                )
            }
        )
        .id(tab)
    }

    private func handleRowHover(tab: TabInfo, hovering: Bool) {
        if hovering {
            // Ignore hover events when previews are disabled (keyboard navigation)
            guard hoverPreviewsEnabled else { return }

            // Cancel any pending task
            hoverTask?.cancel()

            // If same tab and already have data, just update panel position
            if tab == hoveredTab && (previewMetadata != nil || isLoadingPreview) {
                updatePreviewPanel(for: tab)
                return
            }

            hoveredTab = tab

            hoverTask = Task {
                // Check cache first - show immediately with no delay
                if let cached = await OpenGraphCache.shared.getCached(for: tab.url) {
                    previewMetadata = cached.isEmpty ? nil : cached
                    previewLoadFailed = cached.isEmpty
                    isLoadingPreview = false
                    updatePreviewPanel(for: tab)
                    return
                }

                // Delay before network fetch to avoid spam when scanning through list
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }

                isLoadingPreview = true
                previewLoadFailed = false
                previewMetadata = nil

                let metadata = await OpenGraphCache.shared.fetch(for: tab.url)
                guard !Task.isCancelled else { return }

                isLoadingPreview = false
                previewMetadata = metadata
                previewLoadFailed = (metadata == nil)
                updatePreviewPanel(for: tab)
            }
        } else {
            // Only clear if leaving the currently hovered row
            if hoveredTab == tab {
                hoverTask?.cancel()
                hoverTask = nil
                clearPreviewState()
            }
        }
    }

    private func updatePreviewPanel(for tab: TabInfo) {
        guard let rowRect = rowBounds[tab],
              let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let contentView = window.contentView else { return }

        // Convert from SwiftUI coordinates to screen coordinates
        let contentHeight = contentView.frame.height
        let appKitY = contentHeight - rowRect.midY
        let screenPoint = window.convertPoint(toScreen: NSPoint(x: 0, y: appKitY))

        let content = LinkPreviewView(
            url: tab.url,
            metadata: previewMetadata,
            isLoading: isLoadingPreview,
            loadFailed: previewLoadFailed
        )

        PreviewPanelController.shared.show(content: content, atY: screenPoint.y)
    }

    private func clearPreviewState() {
        hoveredTab = nil
        previewMetadata = nil
        isLoadingPreview = false
        previewLoadFailed = false
        PreviewPanelController.shared.hide()
    }

    private func isTabSelected(_ tab: TabInfo) -> Bool {
        for window in windows.enumerated() {
            if let tabIndex = window.element.tabs.firstIndex(where: { $0.index == tab.index && $0.url == tab.url }) {
                let identifier = PickerViewModel.TabIdentifier(
                    browserIndex: browserIndex,
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
                    browserIndex: browserIndex,
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

    /// Check if a tab is pinned (first N tabs in its window where N = pinnedTabCount)
    private func isTabPinned(_ tab: TabInfo) -> Bool {
        for window in windows {
            if let tabPosition = window.tabs.firstIndex(where: { $0.index == tab.index && $0.url == tab.url }) {
                return tabPosition < window.pinnedTabCount
            }
        }
        return false
    }
}

/// Group header row with disclosure triangle and selection checkbox
struct GroupHeaderView: View {
    let group: PickerViewModel.LinkGroup
    let isCollapsed: Bool
    let isFullySelected: Bool
    let isPartiallySelected: Bool
    let indentLevel: Int
    var isHighlighted: Bool = false
    let onToggleCollapsed: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: onToggleSelection) {
                Image(systemName: checkboxIcon)
                    .foregroundColor(isFullySelected || isPartiallySelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

            // Disclosure triangle
            Button(action: onToggleCollapsed) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            // Group name
            Text(group.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            // Count badge
            Text("\(group.totalCount)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.leading, CGFloat(indentLevel) * 16)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.05))
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleCollapsed()
        }
    }

    private var checkboxIcon: String {
        if isFullySelected {
            return "checkmark.square.fill"
        } else if isPartiallySelected {
            return "minus.square.fill"
        } else {
            return "square"
        }
    }
}

/// Individual tab row
struct TabRowView: View {
    let tab: TabInfo
    let index: Int
    let isHighlighted: Bool
    let isChecked: Bool
    var isPinned: Bool = false
    let onToggleCheck: () -> Void
    let onSelect: () -> Void
    var onExtract: (() -> Void)? = nil
    var onOpenInBrowser: (() -> Void)? = nil
    var onHover: ((Bool) -> Void)? = nil

    @State private var isHovering = false

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

            // Pinned indicator
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(tab.isActive ? .accentColor : .secondary)
                    .rotationEffect(.degrees(45))
                    .frame(width: 10)
            } else if tab.isActive {
                // Active indicator (only shown for non-pinned tabs)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .padding(.horizontal, 2)
            } else {
                Spacer()
                    .frame(width: 10)
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
            onHover?(hovering)
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
    var isLoading: Bool = false
    var loadFailed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading preview...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if let metadata = metadata {
                // OG Image
                if let imageURL = metadata.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: 280, maxHeight: 150)
                                .clipped()
                        case .failure, .empty:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                // Title
                if let title = metadata.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                }

                // Description
                if let description = metadata.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .lineLimit(4)
                        .foregroundColor(.secondary)
                }
            } else if loadFailed {
                // No metadata available (only show after load completed)
                Text("No preview available")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            // URL (always shown)
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

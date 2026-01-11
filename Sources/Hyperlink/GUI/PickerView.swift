import SwiftUI

/// Main picker view containing browser tabs and tab list
struct PickerView: View {
    @ObservedObject var viewModel: PickerViewModel
    let onDismiss: () -> Void
    @State private var showHelp = false
    @State private var showSettings = false

    /// Icon for the master checkbox based on selection state
    private var masterCheckboxIcon: String {
        if viewModel.allFilteredTabsSelected {
            return "checkmark.square.fill"
        } else if viewModel.someFilteredTabsSelected {
            return "minus.square.fill"
        } else {
            return "square"
        }
    }

    /// Label for the copy button based on selection state
    private var copyButtonLabel: String {
        if viewModel.allFilteredTabsSelected {
            return "Copy All"
        } else {
            return "Copy Selected (\(viewModel.selectedFilteredTabsCount)/\(viewModel.filteredTabs.count))"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row: browser tabs (if multiple) + settings/help icons
            HStack(spacing: 8) {
                if viewModel.allBrowserData.count > 1 {
                    BrowserTabBar(
                        browsers: viewModel.allBrowserData,
                        selectedIndex: $viewModel.selectedBrowserIndex,
                        extractedSourceCount: viewModel.extractedSourceCount,
                        onClose: { index in
                            viewModel.closeExtractedSource(at: index)
                        }
                    )
                }

                Spacer()

                // Settings button
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings (Cmd+,)")

                // Help button
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Keyboard shortcuts (?)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search field + Select All on same row
            HStack(spacing: 8) {
                // Master checkbox
                Button(action: { viewModel.toggleSelectAll() }) {
                    Image(systemName: masterCheckboxIcon)
                        .foregroundColor(viewModel.selectedFilteredTabsCount > 0 ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                // Search field
                SearchField(
                    text: $viewModel.searchText,
                    isFocused: $viewModel.searchFieldHasFocus,
                    matchCount: viewModel.filteredTabs.count,
                    totalCount: viewModel.allCurrentTabs.count
                )

                // Copy button (when tabs are selected)
                if viewModel.selectedFilteredTabsCount > 0 {
                    Button(action: {
                        viewModel.copySelected()
                        onDismiss()
                    }) {
                        Text(copyButtonLabel)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Tab list
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.permissionDenied {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Accessibility Permission Required")
                        .font(.headline)
                    Text("Hyperlink needs permission to read browser tabs.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open System Settings") {
                        PermissionChecker.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredTabs.isEmpty {
                Text(viewModel.searchText.isEmpty ? "No tabs found" : "No matching tabs")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabListView(
                    browserIndex: viewModel.selectedBrowserIndex,
                    windows: viewModel.currentWindows,
                    filteredTabs: viewModel.filteredTabs,
                    selectedTabs: $viewModel.selectedTabs,
                    highlightedIndex: $viewModel.highlightedIndex,
                    hoverPreviewsEnabled: $viewModel.hoverPreviewsEnabled,
                    onSelect: { tab in
                        viewModel.copyAndDismiss(tab: tab)
                        onDismiss()
                    },
                    onExtract: { tab, _ in
                        viewModel.extractLinksFromTab(tab)
                    },
                    onOpenInBrowser: { tab in
                        viewModel.openInBrowser(tab: tab)
                    }
                )
            }
        }
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .overlay {
            if showHelp {
                Color.black.opacity(0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { showHelp = false }

                HelpOverlay(onDismiss: { showHelp = false })
            }
        }
        .overlay {
            if showSettings {
                Color.black.opacity(0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { showSettings = false }

                SettingsView(
                    preferences: viewModel.preferences,
                    currentTab: viewModel.highlightedIndex.flatMap { index in
                        index < viewModel.filteredTabs.count ? viewModel.filteredTabs[index] : nil
                    },
                    isShowingSubOverlay: $viewModel.isShowingSubOverlay,
                    onDismiss: { showSettings = false }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toastMessage {
                ToastView(message: toast)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage)
            }
        }
        .overlay {
            if viewModel.isExtracting {
                Color.black.opacity(0.2)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                ProgressView(viewModel.extractionStatus)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
            }
        }
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: showSettings) { _, newValue in
            viewModel.isShowingOverlay = newValue || showHelp
        }
        .onChange(of: showHelp) { _, newValue in
            viewModel.isShowingOverlay = newValue || showSettings
        }
        .onChange(of: viewModel.selectedBrowserIndex) { _, _ in
            viewModel.highlightActiveTab()
        }
        .onChange(of: viewModel.searchFieldHasFocus) { _, newValue in
            TestLogger.logState("viewModel.searchFieldHasFocus", value: newValue)
        }
    }

    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyEvent(event) {
                return nil
            }
            return event
        }

        // Re-enable hover previews when mouse moves (disabled during keyboard navigation)
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            viewModel.hoverPreviewsEnabled = true
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Don't process most keys while an overlay (settings/help) is shown
        if viewModel.isShowingOverlay {
            if event.keyCode == 53 { // Escape closes overlays
                if viewModel.isShowingSubOverlay {
                    // Close sub-overlay (e.g., app picker popover) first
                    viewModel.isShowingSubOverlay = false
                } else {
                    showSettings = false
                    showHelp = false
                }
                return true
            }
            return false
        }

        let hasCmd = event.modifierFlags.contains(.command)
        let hasCtrl = event.modifierFlags.contains(.control)
        let hasModifier = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        let char = event.charactersIgnoringModifiers ?? ""
        let characters = event.characters ?? ""

        // === Always-handled keys (regardless of focus) ===

        // Cmd+, opens settings
        if hasCmd && char == "," {
            showSettings = true
            return true
        }

        // Navigation: up/down always work, left/right depend on focus and modifiers
        switch event.keyCode {
        case 125: // Down arrow
            viewModel.moveHighlight(by: 1)
            return true
        case 126: // Up arrow
            viewModel.moveHighlight(by: -1)
            return true
        case 115: // Home
            viewModel.moveHighlightToStart()
            return true
        case 119: // End
            viewModel.moveHighlightToEnd()
            return true
        case 116: // Page Up
            viewModel.moveHighlightByPage(-1)
            return true
        case 121: // Page Down
            viewModel.moveHighlightByPage(1)
            return true
        case 123: // Left arrow
            // Cmd+Left always switches browser; plain Left only when list has focus
            if hasCmd {
                viewModel.switchBrowser(by: -1)
                return true
            } else if !viewModel.searchFieldHasFocus {
                viewModel.switchBrowser(by: -1)
                return true
            }
            return false // Let text field handle cursor movement
        case 124: // Right arrow
            // Cmd+Right always switches browser; plain Right only when list has focus
            if hasCmd {
                viewModel.switchBrowser(by: 1)
                return true
            } else if !viewModel.searchFieldHasFocus {
                viewModel.switchBrowser(by: 1)
                return true
            }
            return false // Let text field handle cursor movement
        case 48: // Tab - toggle focus between list and search
            viewModel.searchFieldHasFocus.toggle()
            return true
        case 53: // Escape
            if !viewModel.searchText.isEmpty {
                viewModel.searchText = ""
                viewModel.searchFieldHasFocus = false
                return true
            }
            return false // Let escape propagate to close window
        case 36: // Return
            if hasCmd {
                // Cmd+Enter for link extraction
                viewModel.extractLinksFromHighlightedTab()
            } else if !viewModel.selectedTabs.isEmpty {
                // Copy checkbox-selected tabs
                viewModel.copySelected()
                onDismiss()
            } else if let index = viewModel.highlightedIndex,
               index < viewModel.filteredTabs.count {
                // Copy highlighted tab
                let tab = viewModel.filteredTabs[index]
                viewModel.copyAndDismiss(tab: tab)
                onDismiss()
            }
            return true
        default:
            break
        }

        // Cmd+Backspace to close extracted source tab
        if hasCmd && event.keyCode == 51 {
            if viewModel.isViewingExtractedSource {
                viewModel.closeCurrentExtractedSource()
            } else {
                viewModel.showToast("Only extracted tabs can be closed")
            }
            return true
        }

        // Cmd+1-9 for browser switching (always works)
        if hasCmd,
           let number = Int(char),
           number >= 1 && number <= 9 {
            let index = number - 1
            if index < viewModel.allBrowserData.count {
                viewModel.selectedBrowserIndex = index
            }
            return true
        }

        // Ctrl+1-9 for quick tab selection (always works)
        if hasCtrl,
           let number = Int(char),
           number >= 1 && number <= 9 {
            let index = number - 1
            if index < viewModel.filteredTabs.count {
                let tab = viewModel.filteredTabs[index]
                viewModel.copyAndDismiss(tab: tab)
                onDismiss()
            }
            return true
        }

        // === Focus-dependent keys ===

        if viewModel.searchFieldHasFocus {
            // Search field has focus - let most keys pass through to the text field
            // But handle backspace when search is empty to switch focus back
            if event.keyCode == 51 && viewModel.searchText.isEmpty { // Backspace
                viewModel.searchFieldHasFocus = false
                return true
            }
            return false // Let the text field handle it
        }

        // List has focus - handle shortcuts and auto-switch to search for typing

        // `?` shows help
        if characters == "?" && !hasModifier {
            showHelp = true
            return true
        }

        // 1-9 for quick tab selection
        if let number = Int(char), number >= 1 && number <= 9, !hasModifier {
            let index = number - 1
            if index < viewModel.filteredTabs.count {
                let tab = viewModel.filteredTabs[index]
                viewModel.copyAndDismiss(tab: tab)
                onDismiss()
            }
            return true
        }

        // Space toggles checkbox
        if event.keyCode == 49 { // Space
            if let index = viewModel.highlightedIndex {
                viewModel.toggleSelection(at: index)
            }
            return true
        }

        // Backspace - delete from search if there's text
        if event.keyCode == 51 { // Backspace
            if !viewModel.searchText.isEmpty {
                viewModel.searchText.removeLast()
            }
            return true
        }

        // Printable characters: auto-switch to search and type
        if !hasModifier && !characters.isEmpty && !characters.contains(where: \.isNewline) {
            viewModel.searchFieldHasFocus = true
            viewModel.searchText.append(characters)
            return true
        }

        return false
    }
}

/// Visual effect view for the window background
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

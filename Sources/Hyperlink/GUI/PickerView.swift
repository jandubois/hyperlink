import SwiftUI

/// Main picker view containing browser tabs and tab list
struct PickerView: View {
    @ObservedObject var viewModel: PickerViewModel
    let onDismiss: () -> Void
    @State private var showHelp = false

    /// Search field is active when it has text or user activated it with / or click
    private var searchFieldIsActive: Binding<Bool> {
        Binding(
            get: { !viewModel.searchText.isEmpty || viewModel.searchFocusRequested },
            set: { newValue in
                if newValue {
                    viewModel.searchFocusRequested = true
                }
            }
        )
    }

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

    var body: some View {
        VStack(spacing: 0) {
            // Browser tab bar at top
            if viewModel.browsers.count > 1 {
                BrowserTabBar(
                    browsers: viewModel.browsers,
                    selectedIndex: $viewModel.selectedBrowserIndex
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

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
                    isActive: searchFieldIsActive,
                    onActivate: { viewModel.searchFocusRequested = true }
                )

                // Selection count
                if viewModel.selectedFilteredTabsCount > 0 {
                    Text("\(viewModel.selectedFilteredTabsCount)/\(viewModel.filteredTabs.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Help button
                Button(action: { showHelp = true }) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Keyboard shortcuts (?)")
            }
            .padding(.horizontal, 12)
            .padding(.top, viewModel.browsers.count > 1 ? 0 : 12)
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
                    onSelect: { tab in
                        viewModel.copyAndDismiss(tab: tab)
                        onDismiss()
                    }
                )
            }

            // Footer with copy button for multi-select
            if !viewModel.selectedTabs.isEmpty {
                Divider()
                HStack {
                    Spacer()
                    Button("Copy Selected (\(viewModel.selectedTabs.count))") {
                        viewModel.copySelected()
                        onDismiss()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(12)
            }
        }
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
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
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: viewModel.selectedBrowserIndex) { _, _ in
            viewModel.selectedTabs.removeAll()
            viewModel.highlightActiveTab()
        }
    }

    private func setupKeyboardHandling() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Dismiss help on any key
        if showHelp {
            showHelp = false
            return true
        }

        let hasModifier = !event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        let hasCmd = event.modifierFlags.contains(.command)
        let hasCtrl = event.modifierFlags.contains(.control)
        let char = event.charactersIgnoringModifiers ?? ""
        let characters = event.characters ?? ""

        // `?` shows help when search is not active
        if characters == "?" && !hasModifier {
            let searchIsActive = viewModel.searchFocusRequested || !viewModel.searchText.isEmpty
            if !searchIsActive {
                showHelp = true
                return true
            }
            // Search is active, add `?` to search text
            viewModel.searchText.append("?")
            return true
        }

        // Cmd+1-9 for browser switching
        if hasCmd,
           let number = Int(char),
           number >= 1 && number <= 9 {
            let index = number - 1
            if index < viewModel.browsers.count {
                viewModel.selectedBrowserIndex = index
                // Note: selectedTabs cleared and highlightActiveTab called via onChange
            }
            return true
        }

        // Ctrl+1-9 OR plain 1-9 (when search is empty and no / pressed) for tab selection
        if let number = Int(char), number >= 1 && number <= 9 {
            // Ctrl+1-9 always selects tabs
            // Plain 1-9 only selects tabs when search is empty and / wasn't pressed
            let shouldPassToSearch = viewModel.searchFocusRequested || !viewModel.searchText.isEmpty
            if hasCtrl || (!hasModifier && !shouldPassToSearch) {
                let index = number - 1
                if index < viewModel.filteredTabs.count {
                    let tab = viewModel.filteredTabs[index]
                    viewModel.copyAndDismiss(tab: tab)
                    onDismiss()
                }
                return true
            }
            // Append to search field, reset the focus flag
            viewModel.searchFocusRequested = false
            viewModel.searchText.append(characters)
            return true
        }

        // `/` activates search mode when search is not active, otherwise types into search
        if char == "/" && !hasModifier {
            if viewModel.searchText.isEmpty && !viewModel.searchFocusRequested {
                viewModel.searchFocusRequested = true
                return true
            }
            // Search is already active, add `/` to search text
            viewModel.searchText.append("/")
            return true
        }

        // Arrow keys for navigation
        switch event.keyCode {
        case 125: // Down arrow
            viewModel.moveHighlight(by: 1)
            return true
        case 126: // Up arrow
            viewModel.moveHighlight(by: -1)
            return true
        case 123: // Left arrow
            viewModel.switchBrowser(by: -1)
            return true
        case 124: // Right arrow
            viewModel.switchBrowser(by: 1)
            return true
        case 36: // Return
            if let index = viewModel.highlightedIndex,
               index < viewModel.filteredTabs.count {
                let tab = viewModel.filteredTabs[index]
                viewModel.copyAndDismiss(tab: tab)
                onDismiss()
            }
            return true
        case 51: // Delete/Backspace
            if !viewModel.searchText.isEmpty {
                viewModel.searchText.removeLast()
            }
            return true
        case 49: // Space - toggle selection if search is empty, otherwise add to search
            if viewModel.searchText.isEmpty && !viewModel.searchFocusRequested {
                if let index = viewModel.highlightedIndex {
                    viewModel.toggleSelection(at: index)
                }
                return true
            }
            viewModel.searchText.append(" ")
            viewModel.searchFocusRequested = false
            return true
        case 53: // Escape
            if !viewModel.searchText.isEmpty {
                viewModel.searchText = ""
                return true
            }
            return false // Let escape propagate to close window
        default:
            // Printable characters go to search (without modifiers)
            if !hasModifier && !characters.isEmpty {
                viewModel.searchText.append(characters)
                return true
            }
            return false
        }
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

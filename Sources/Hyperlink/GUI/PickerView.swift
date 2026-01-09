import SwiftUI

/// Main picker view containing browser tabs and tab list
struct PickerView: View {
    @ObservedObject var viewModel: PickerViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            SearchField(text: $viewModel.searchText)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Browser tab bar
            if viewModel.browsers.count > 1 {
                BrowserTabBar(
                    browsers: viewModel.browsers,
                    selectedIndex: $viewModel.selectedBrowserIndex
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

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
        .onAppear {
            setupKeyboardHandling()
        }
        .onChange(of: viewModel.selectedBrowserIndex) { _, _ in
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
        // Cmd+1-9 for browser switching
        if event.modifierFlags.contains(.command),
           let number = Int(event.charactersIgnoringModifiers ?? ""),
           number >= 1 && number <= 9 {
            let index = number - 1
            if index < viewModel.browsers.count {
                viewModel.selectedBrowserIndex = index
            }
            return true
        }

        // 1-9 for tab selection
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           let number = Int(event.charactersIgnoringModifiers ?? ""),
           number >= 1 && number <= 9 {
            let index = number - 1
            if index < viewModel.filteredTabs.count {
                let tab = viewModel.filteredTabs[index]
                viewModel.copyAndDismiss(tab: tab)
                onDismiss()
            }
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
        case 49: // Space
            if let index = viewModel.highlightedIndex {
                viewModel.toggleSelection(at: index)
            }
            return true
        default:
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

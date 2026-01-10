import SwiftUI
import AppKit

/// Main SwiftUI application for the GUI picker
struct HyperlinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// App delegate to handle the floating panel
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    var testMode: Bool = false
    private var testCommandReader: TestCommandReader?
    private var previousAppBundleID: String?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // We're on the main thread, so we can use assumeIsolated
        MainActor.assumeIsolated {
            self.setupUI()
        }
    }

    private func setupUI() {
        // Capture the frontmost app BEFORE we activate ourselves
        previousAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Hide the default window
        NSApp.windows.forEach { $0.close() }

        // Create and show the floating panel
        panel = FloatingPanel(targetAppBundleID: previousAppBundleID)
        panel?.show()

        // Load browsers synchronously
        panel?.viewModel.loadBrowsersSync()

        // Log browser data in test mode
        if testMode {
            logBrowserData()
            setupTestCommandReader()
            TestLogger.logReady()
        }
    }

    private func logBrowserData() {
        guard let viewModel = panel?.viewModel else { return }

        for browser in viewModel.browsers {
            let totalTabs = browser.windows.flatMap { $0.tabs }.count
            TestLogger.logBrowserData(
                browser: browser.name,
                windows: browser.windows.count,
                tabs: totalTabs
            )

            for window in browser.windows {
                for tab in window.tabs {
                    TestLogger.logTab(
                        browser: browser.name,
                        windowIndex: window.index,
                        tabIndex: tab.index,
                        title: tab.title,
                        url: tab.url.absoluteString,
                        active: tab.isActive
                    )
                }
            }
        }

        TestLogger.logState("highlightedIndex", value: viewModel.highlightedIndex ?? -1)
    }

    private func setupTestCommandReader() {
        testCommandReader = TestCommandReader()
        testCommandReader?.viewModel = panel?.viewModel
        testCommandReader?.onDismiss = { [weak self] in
            self?.panel?.dismiss()
        }
        testCommandReader?.start()
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false - we handle termination ourselves via dismiss()
        // This prevents AppKit from terminating when popup menus close
        false
    }
}

/// Custom hosting view that doesn't reset cursor on SwiftUI updates
class StableCursorHostingView<Content: View>: NSHostingView<Content> {
    override func cursorUpdate(with event: NSEvent) {
        // Don't call super - this prevents the system from resetting the cursor
        // when SwiftUI views update (e.g., TextField cursor blinking)
    }
}

/// Floating window that stays above other windows
class FloatingPanel: NSWindow {
    private var hostingView: StableCursorHostingView<PickerView>?
    var viewModel: PickerViewModel

    init(targetAppBundleID: String? = nil) {
        self.viewModel = PickerViewModel(targetAppBundleID: targetAppBundleID)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure window appearance
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        // Disable cursor rects to prevent SwiftUI from resetting cursors
        // Text fields will manage their own cursors via tracking areas
        self.acceptsMouseMovedEvents = true
        self.disableCursorRects()

        // Set up content view
        let pickerView = PickerView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.dismiss()
        })
        hostingView = StableCursorHostingView(rootView: pickerView)
        hostingView?.frame = contentView?.bounds ?? .zero
        hostingView?.autoresizingMask = [.width, .height]
        contentView?.addSubview(hostingView!)

        // Handle click outside to dismiss (when app loses active status)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func show() {
        // Center on screen
        center()

        // Show and make key
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        close()
        NSApp.terminate(nil)
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        // Dismiss when user clicks outside the app
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        // Escape key pressed
        dismiss()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

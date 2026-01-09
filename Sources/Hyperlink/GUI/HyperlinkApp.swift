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
class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the default window
        NSApp.windows.forEach { $0.close() }

        // Create and show the floating panel
        panel = FloatingPanel()
        panel?.show()

        // Load browsers synchronously
        panel?.viewModel.loadBrowsersSync()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Floating panel that stays above other windows
class FloatingPanel: NSPanel {
    private var hostingView: NSHostingView<PickerView>?
    var viewModel: PickerViewModel

    init() {
        self.viewModel = PickerViewModel()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure panel appearance
        self.title = "Hyperlink"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true

        // Allow panel to become key for keyboard input
        self.becomesKeyOnlyIfNeeded = false

        // Set up content view
        let pickerView = PickerView(viewModel: viewModel, onDismiss: { [weak self] in
            self?.dismiss()
        })
        hostingView = NSHostingView(rootView: pickerView)
        hostingView?.frame = contentView?.bounds ?? .zero
        hostingView?.autoresizingMask = [.width, .height]
        contentView?.addSubview(hostingView!)

        // Handle click outside to dismiss
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
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

    @objc private func windowDidResignKey(_ notification: Notification) {
        // Dismiss when clicking outside
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        // Escape key pressed
        dismiss()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

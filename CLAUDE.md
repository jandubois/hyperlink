# Hyperlink - Claude Instructions

## Project Overview

Hyperlink is a macOS utility for extracting hyperlinks from browser tabs. It has two modes:
- **CLI mode**: Command-line interface with flags for browser/tab selection
- **GUI mode**: Floating picker panel (launches when run without arguments)

## Build & Test Commands

```bash
# Build
swift build

# Run unit tests (21 tests)
swift test

# Run all tests (unit + integration)
./scripts/integration-test.sh

# Run specific integration test
./scripts/integration-test.sh startup
./scripts/integration-test.sh navigation
```

## Project Structure

```
Sources/Hyperlink/
├── Hyperlink.swift          # Entry point, CLI argument parsing
├── Core/
│   ├── LinkSource.swift     # Protocol + WindowInfo/TabInfo types
│   ├── ClipboardWriter.swift # Markdown + RTF clipboard output
│   ├── TitleTransform.swift  # Title cleanup (backticks, GitHub suffixes)
│   ├── Preferences.swift     # UserDefaults wrapper
│   ├── BrowserDetector.swift # Running browser detection
│   ├── PermissionChecker.swift # Accessibility permission handling
│   ├── TestLogger.swift      # Structured test output
│   └── TestCommandReader.swift # Stdin command reader for tests
├── Browsers/
│   ├── BrowserRegistry.swift # Available browser sources
│   ├── SafariSource.swift    # Safari AppleScript implementation
│   ├── ChromiumSource.swift  # Chrome/Arc/Brave/Edge implementation
│   └── OrionSource.swift     # Orion browser implementation
└── GUI/
    ├── HyperlinkApp.swift    # SwiftUI app + FloatingPanel
    ├── PickerView.swift      # Main picker UI
    ├── PickerViewModel.swift # UI state and logic
    ├── BrowserTabBar.swift   # Browser selection tabs
    ├── TabListView.swift     # Scrollable tab list
    └── SearchField.swift     # Filter input
```

## Key Patterns

### AppleScript Execution
Browser tab data is fetched via AppleScript using `osascript` subprocess (not NSAppleScript, which deadlocks with NSApplication.run()). See `AppleScriptRunner` in SafariSource.swift.

### Swift 6 Concurrency
- Main UI code is `@MainActor` isolated
- `TestLogger.isEnabled` uses `nonisolated(unsafe)` for cross-actor access
- `TestCommandReader` uses `NSObject.perform(_:with:afterDelay:)` for run loop integration (DispatchQueue.main doesn't work with NSApplication.run())

### Test Mode
The `--test` flag enables:
- Structured logging to stderr (`[BROWSER_DATA]`, `[TAB]`, `[READY]`, etc.)
- Stdin command processing (`wait:100`, `key:down`, `quit`, etc.)

## Testing

### Unit Tests
Located in `Tests/HyperlinkTests/`. Use Swift Testing framework (`@Test`, `#expect`).

ClipboardWriterTests uses `.serialized` trait because tests share the system clipboard.

### Integration Tests
The `scripts/integration-test.sh` script tests GUI mode by:
1. Launching with `--test` flag
2. Sending commands via stdin
3. Checking stderr output for expected patterns

Requires at least one browser running with tabs.

## Exit Codes

- 0: Success
- 1: General error (no tabs, script failure)
- 2: Invalid arguments
- 3: Permission denied
- 4: Browser not found/not running

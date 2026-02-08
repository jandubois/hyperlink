# Hyperlink - Claude Instructions

## Project Overview

Hyperlink is a macOS utility for extracting hyperlinks from browser tabs. It has two modes:
- **CLI mode**: Command-line interface with flags for browser/tab selection
- **GUI mode**: Floating picker panel (launches when run without arguments)

## Build & Test Commands

```bash
# Build
make build

# Run unit tests
make test

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
│   ├── MockDataStore.swift  # Mock data save/load for testing
│   ├── TestLogger.swift      # Structured test output
│   └── TestCommandReader.swift # Stdin command reader for tests
├── Browsers/
│   ├── BrowserRegistry.swift # Available browser sources
│   ├── SafariSource.swift    # Safari AppleScript implementation
│   ├── ChromiumSource.swift  # Chrome/Arc/Brave/Edge implementation
│   └── OrionSource.swift     # Orion browser implementation
├── LinkExtractor/
│   ├── PageSourceFetcher.swift    # Fetch HTML source from browser tabs
│   ├── HTMLLinkParser.swift       # Extract links from HTML
│   ├── TitleFetcher.swift         # Fetch <title> from URLs
│   ├── ExtractedLinksSource.swift # Pseudo-browser for extracted links
│   └── DomainFormatter.swift      # Apex domain name formatting
└── GUI/
    ├── HyperlinkApp.swift    # SwiftUI app + FloatingPanel
    ├── PickerView.swift      # Main picker UI
    ├── PickerViewModel.swift # UI state and logic
    ├── BrowserTabBar.swift   # Browser selection tabs
    ├── TabListView.swift     # Scrollable tab list
    ├── SearchField.swift     # Filter input
    └── ToastView.swift       # Toast notifications for errors
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

### Mock Data
For testing and debugging, browser data can be saved and replayed:

```bash
# Save current browser state to JSON
hyperlink --save-data ~/snapshot.json

# Load mock data instead of querying real browsers (CLI)
hyperlink --mock-data ~/snapshot.json --browser safari --stdout

# Load mock data in GUI mode
hyperlink --mock-data ~/snapshot.json
```

When `--mock-data` is active:
- No accessibility permissions required
- No real browsers need to be running
- Data comes from the JSON snapshot

## Testing

### Unit Tests
Located in `Tests/HyperlinkTests/`. Use Swift Testing framework (`@Test`, `#expect`).

ClipboardWriterTests uses `.serialized` trait because tests share the system clipboard.

### Integration Tests
The `scripts/integration-test.sh` script tests GUI mode by:
1. Launching with `--test` flag
2. Sending commands via stdin
3. Checking stderr output for expected patterns

Uses mock data for reproducible tests (no browser required).

## Exit Codes

- 0: Success
- 1: General error (no tabs, script failure)
- 2: Invalid arguments
- 3: Permission denied
- 4: Browser not found/not running

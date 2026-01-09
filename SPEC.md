# Hyperlink - macOS Browser Tab Link Utility

A native macOS utility for extracting hyperlinks from browser tabs, available as both a CLI tool and a GUI picker.

## Overview

`hyperlink` fetches the title and URL from browser tabs and copies them to the clipboard as both markdown (for plain text paste) and RTF (for rich text paste). It supports all major browsers and provides both command-line and graphical interfaces.

## Technology

- **Language**: Swift
- **UI Framework**: SwiftUI
- **Target**: macOS (native, single binary)
- **Configuration**: UserDefaults (`~/Library/Preferences/hyperlink.plist`)

## Supported Browsers

**Confirmed** (AppleScript support verified):
- Safari
- Google Chrome
- Arc
- Brave
- Microsoft Edge
- Orion

**Uncertain** (AppleScript support unverified):
- Firefox - May not be possible; Firefox does not appear to have AppleScript support for tab access. Investigate alternatives (native messaging, accessibility APIs) but do not block initial release on this.

Browser communication uses AppleScript/JavaScript for Automation (JXA) via NSAppleScript or OSAKit.

## CLI Mode

Invoked when any command-line flags are provided.

### Usage

```
hyperlink [OPTIONS]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--browser <name>` | Browser to query: `safari`, `chrome`, `arc`, `brave`, `edge`, `orion` | Frontmost browser |
| `--tab <spec>` | Tab specifier: 1-based index, `active`, or `all` | `active` |
| `--stdout` | Output to stdout instead of clipboard | Off (clipboard) |
| `--format <fmt>` | Output format: `markdown`, `json` (for `--stdout`) | `markdown` |
| `--save-data <path>` | Save all browser data to JSON file and exit | |
| `--mock-data <path>` | Load mock data from JSON instead of querying browsers | |
| `--help` | Show help message | |
| `--version` | Show version | |

### Examples

```bash
# Copy active tab of frontmost browser to clipboard
hyperlink --tab active

# Copy third tab of Safari to clipboard
hyperlink --browser safari --tab 3

# Output all Chrome tabs as JSON to stdout
hyperlink --browser chrome --tab all --stdout --format json

# Copy active tab of Arc to clipboard
hyperlink --browser arc
```

### Output Formats

**Markdown** (default):
```
[Page Title](https://example.com/page)
```

**JSON** (with `--format json`):
```json
{
  "browser": "safari",
  "window": 1,
  "tab": 3,
  "title": "Page Title",
  "url": "https://example.com/page"
}
```

**JSON for `--tab all`**:
```json
{
  "browser": "safari",
  "windows": [
    {
      "index": 1,
      "tabs": [
        {"index": 1, "title": "Page Title", "url": "https://example.com", "active": true},
        {"index": 2, "title": "Other Page", "url": "https://other.com", "active": false}
      ]
    }
  ]
}
```

### Mock Data Format

The `--save-data` flag exports all browser data to JSON:

```json
{
  "browsers": [
    {
      "name": "Safari",
      "windows": [
        {
          "index": 1,
          "name": null,
          "tabs": [
            {"index": 1, "title": "Page Title", "url": "https://example.com", "isActive": true}
          ]
        }
      ]
    }
  ]
}
```

When `--mock-data` is specified, the app loads this JSON instead of querying real browsers. This enables:
- Reproducible integration tests
- Debugging with consistent browser state
- Running without accessibility permissions

### Clipboard Format

When copying to clipboard (default behavior), the tool sets both:
- **Plain text**: Markdown format `[Title](URL)`
- **RTF**: Clickable hyperlink for rich text paste

## GUI Mode

Invoked when no command-line flags are provided (just `hyperlink`).

### Window Behavior

- **Type**: Floating panel (NSPanel with `.floating` level)
- **Behavior**: Stays above other windows, auto-dismisses on selection
- **Dismiss**: Escape key or clicking outside the panel

### Layout

```
┌─────────────────────────────────────────────────────┐
│ [🔍 Filter tabs...]                                 │
├─────────────────────────────────────────────────────┤
│ [Safari] [Chrome] [Arc]                             │  ← Browser tabs (Cmd+1, Cmd+2, etc.)
├─────────────────────────────────────────────────────┤
│ Window 1                                            │
│ ☐ 1. ● Active Tab Title                        ★   │  ← ★ = active, ● = favicon
│ ☐ 2. ● Another Tab Title                           │
│ ☐ 3. ● Third Tab Title                             │
├─────────────────────────────────────────────────────┤
│ Window 2                                            │
│ ☐ 4. ● Some Other Tab                              │
│ ☐ 5. ● Yet Another Tab                             │
├─────────────────────────────────────────────────────┤
│                              [Copy Selected]        │
└─────────────────────────────────────────────────────┘
```

### Browser Tabs

- One tab per running browser instance
- For browsers with multiple windows or profiles (e.g., Chrome profiles, Arc spaces), each distinct instance appears as a separate tab in the picker
- Displays browser icon and name (with profile/space name suffix if applicable)
- Ordered by window z-order (frontmost browser's tab is selected by default)
- Switch with mouse click or Cmd+1 through Cmd+9

### Tab List

- Shows all tabs from all windows of the selected browser
- Grouped by window with visual separators
- Active tab is visually highlighted (bold, accent color, or indicator)
- Each row shows: checkbox, number (1-9 for shortcuts), favicon (if cached), title
- Rows are truncated with ellipsis if title is too long; full title shown on hover

### Favicons

- Display favicon if already cached
- Do not block UI waiting for favicon fetch
- Show generic globe/page icon as placeholder

### Search/Filter

- Text field at top of panel
- Filters tabs by title or URL as user types
- Case-insensitive substring match
- Filter applies across all windows

### Selection

**Single selection**:
- Click a row (not checkbox) to copy and close
- Press number key 1-9 to select corresponding visible tab
- Press Enter to copy currently highlighted row

**Multi-selection**:
- Click checkboxes to select multiple tabs
- Click "Copy Selected" button (or press Cmd+Enter) to copy all and close

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `1-9` | Select and copy nth visible tab |
| `Cmd+1-9` | Switch to nth browser tab |
| `↑/↓` | Navigate tab list |
| `Enter` | Copy highlighted tab and close |
| `Space` | Toggle checkbox on highlighted row |
| `Cmd+Enter` | Copy all checked tabs and close |
| `Cmd+A` | Select all visible tabs |
| `Cmd+F` | Focus search field |
| `Escape` | Close without copying |

## Configuration

Stored in `~/Library/Preferences/hyperlink.plist` via UserDefaults.

### Transform Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `removeBackticks` | Bool | `true` | Remove backticks from titles |
| `trimGitHubSuffix` | Bool | `true` | Remove " · owner/repo" from GitHub page titles |

### Multi-Selection Format

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `multiSelectionFormat` | String | `list` | Format for multiple tabs: `list`, `plain`, `html` |

**Formats**:
- `list`: Markdown bullet list
  ```
  - [Title 1](url1)
  - [Title 2](url2)
  ```
- `plain`: Plain lines (no bullets)
  ```
  [Title 1](url1)
  [Title 2](url2)
  ```
- `html`: HTML unordered list (for RTF, markdown for plain text)

## Permissions

The app requires Accessibility permissions to communicate with browsers via AppleScript.

### First Launch

1. Detect if permissions are missing
2. Show explanatory dialog: "Hyperlink needs Accessibility access to read browser tabs"
3. Provide button to open System Preferences > Privacy & Security > Accessibility

### Permission Denied

If the user denies or revokes permission:
- CLI: Print error to stderr with instructions
- GUI: Show alert with instructions and button to open System Preferences

## Architecture

### Extensibility

The browser interface is designed as a protocol to allow future app support:

```swift
protocol LinkSource {
    var name: String { get }
    var icon: NSImage { get }
    var isRunning: Bool { get }

    func windows() async throws -> [WindowInfo]
}

struct WindowInfo {
    let index: Int
    let tabs: [TabInfo]
}

struct TabInfo {
    let index: Int
    let title: String
    let url: URL
    let isActive: Bool
    let favicon: NSImage?
}
```

Future sources (not in initial release):
- DEVONthink (document links)
- Mail (message:// links)
- Finder (file:// links)
- Notes

### Module Structure

```
Sources/
  Hyperlink/
    main.swift              # Entry point, CLI parsing
    CLI/
      CLICommand.swift      # Argument parsing and CLI logic
      ClipboardWriter.swift # Clipboard formatting
    GUI/
      HyperlinkApp.swift    # SwiftUI App
      PickerPanel.swift     # Floating panel window
      BrowserTabView.swift  # Browser switcher tabs
      TabListView.swift     # Tab list with checkboxes
      SearchField.swift     # Filter field
    Sources/
      LinkSource.swift      # Protocol
      Safari.swift
      Chrome.swift          # Also covers Arc, Brave, Edge (Chromium-based)
      Orion.swift
      Firefox.swift         # Experimental, may not be feasible
    Transforms/
      TitleTransform.swift  # Backtick removal, GitHub suffix, etc.
    Config/
      Preferences.swift     # UserDefaults wrapper
```

## Error Handling

| Condition | CLI Behavior | GUI Behavior |
|-----------|--------------|--------------|
| No browsers running | Exit 1, print error | Show "No browsers running" message |
| Browser not found | Exit 1, print error | N/A (only shows running browsers) |
| Permission denied | Exit 1, print instructions | Show alert with Settings button |
| Invalid tab index | Exit 1, print error | N/A |
| AppleScript error | Exit 1, print error | Show alert |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Permission denied |
| 4 | Browser not running |

## Future Considerations

- Menu bar mode (live in menu bar, dropdown shows tabs)
- Global hotkey to invoke GUI
- Browser extensions for richer metadata
- Sync preferences via iCloud
- URL shortening integration
- Custom transform rules (regex-based)

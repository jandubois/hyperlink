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

See [Transformation Rules](#transformation-rules) for the full transform system.

Legacy keys (migrated automatically on first launch):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `removeBackticks` | Bool | `true` | *(Deprecated)* Migrated to global rule |
| `trimGitHubSuffix` | Bool | `true` | *(Deprecated)* Migrated to global rule |

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

## Transformation Rules

Transformation rules allow customizing the title and URL before copying to clipboard. Rules are organized into groups and applied based on URL matching and target application context.

### Concepts

**Groups**: Collections of rules. There are two types:
- **Global group**: Always exists, cannot be deleted. Rules apply regardless of target application.
- **App-specific groups**: Apply only when pasting into a specific application (identified by bundle ID).

**Rules**: Each rule has:
- A URL match pattern (prefix match, empty = match all URLs)
- An enabled/disabled toggle
- One or more transforms

**Transforms**: Each transform has:
- A target field (Title or URL)
- A regex pattern to find
- A replacement string (supports capture groups: `$1`, `$2`, etc.)
- An enabled/disabled toggle

### Execution Order

1. Global rules execute first, in top-to-bottom order
2. App-specific rules execute second (if a group exists for the target app), in top-to-bottom order
3. Within each rule, transforms execute in top-to-bottom order
4. All matching rules apply (rules are composable, not exclusive)
5. If no rules match a URL, title and URL pass through unchanged

### URL Matching

- Patterns use prefix matching
- No trailing wildcard required: `https://github.com` matches `https://github.com/user/repo`
- Empty pattern matches all URLs
- Matching is case-sensitive

### Regex Transforms

- Uses Swift's `NSRegularExpression` (ICU regex syntax)
- Replacement strings support capture groups: `$0` (full match), `$1`, `$2`, etc.
- Invalid regex syntax shows inline error; transform is skipped at runtime
- Transforms can delete text by using empty replacement string

### Target Application Detection

- The target app is the application that was frontmost before Hyperlink opened
- Captured at launch time
- App-specific groups are identified by bundle ID (e.g., `com.apple.Agenda`)
- UI shows app icon and display name for user-friendliness

### Default Rules

On first launch, the global group is populated with default rules migrated from the legacy `TitleTransform` system:

| Rule Name | URL Match | Transform |
|-----------|-----------|-----------|
| Strip backticks | *(empty - all URLs)* | Title: `` ` `` → *(empty)* |
| GitHub suffix | `https://github.com` | Title: ` · [^·]+$` → *(empty)* |

Users can modify or delete these default rules.

### Settings UI

Accessed via:
- Gear icon (⚙) in the picker window
- Keyboard shortcut Cmd+,
- GUI mode only (not available from CLI)

#### Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│ ⚙ Settings                                                     [×] │
├─────────────────────────────────────────────────────────────────────┤
│ Preview                                                             │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │ Title: Example Page Title · user/repo                          │ │
│ │ URL:   https://github.com/user/repo                            │ │
│ │                                                                 │ │
│ │ Result: Example Page Title                                     │ │
│ │         https://github.com/user/repo                           │ │
│ └─────────────────────────────────────────────────────────────────┘ │
├───────────────────────┬─────────────────────────────────────────────┤
│ Groups                │ Rules for "Global"                          │
│                       │                                             │
│ ▸ Global          [+] │ ☑ Strip backticks                      [−] │
│   Safari              │   URL match: (all URLs)                     │
│   Agenda              │   ┌───────────────────────────────────────┐ │
│                       │   │ [Title ▾] Find: `                     │ │
│                       │   │           Replace:                    │ │
│                       │   └───────────────────────────────────────┘ │
│                       │                                             │
│                       │ ☑ GitHub suffix                        [−] │
│                       │   URL match: https://github.com             │
│                       │   ┌───────────────────────────────────────┐ │
│                       │   │ [Title ▾] Find:  · [^·]+$             │ │
│                       │   │           Replace:                    │ │
│                       │   └───────────────────────────────────────┘ │
│                       │                                             │
│                       │ [+ Add Rule]                                │
├───────────────────────┴─────────────────────────────────────────────┤
│                                                    [Done]           │
└─────────────────────────────────────────────────────────────────────┘
```

#### Interactions

**Preview section**:
- Shows example title and URL (initialized from currently selected tab)
- Updates live with debounce as rules are edited
- Shows transformed result below the inputs

**Groups sidebar**:
- Lists all groups (Global always first)
- Click to select and show rules in detail pane
- [+] button shows dropdown of running applications to add new app group
- Drag to reorder app-specific groups (Global stays first)
- Swipe or right-click to delete app groups (Global cannot be deleted)
- Groups show app icon and display name

**Rules detail pane**:
- Shows rules for selected group
- Checkbox to enable/disable each rule
- [−] button to delete rule
- Drag to reorder rules within the group
- Each rule shows URL match field and its transforms
- [+ Add Rule] button at bottom

**Transforms within rules**:
- Dropdown to select target (Title or URL)
- Find field (regex pattern)
- Replace field (replacement string with capture group support)
- Invalid regex shows red border and error tooltip
- [+ Add Transform] to add more transforms to a rule
- Drag to reorder transforms within a rule

**Drag-and-drop feedback**:
- Dragged item becomes semi-transparent
- Drop indicator shows insertion point

### Data Model

```swift
struct TransformSettings: Codable {
    var globalGroup: RuleGroup
    var appGroups: [AppRuleGroup]
}

struct RuleGroup: Codable {
    var rules: [TransformRule]
}

struct AppRuleGroup: Codable {
    var bundleID: String
    var displayName: String
    var rules: [TransformRule]
    var isEnabled: Bool
}

struct TransformRule: Codable, Identifiable {
    var id: UUID
    var name: String
    var urlMatch: String  // empty = match all
    var transforms: [Transform]
    var isEnabled: Bool
}

struct Transform: Codable, Identifiable {
    var id: UUID
    var target: TransformTarget  // .title or .url
    var pattern: String          // regex
    var replacement: String
    var isEnabled: Bool
}

enum TransformTarget: String, Codable {
    case title
    case url
}
```

### Persistence

- Stored in UserDefaults as JSON-encoded `TransformSettings`
- Key: `transformRules`
- Legacy `removeBackticks` and `trimGitHubSuffix` keys are migrated on first launch, then removed

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
- Import/export transformation rules

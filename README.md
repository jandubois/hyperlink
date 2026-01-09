# Hyperlink

A native macOS utility for extracting hyperlinks from browser tabs. Copy any browser tab as a markdown link with a single keystroke.

## Features

- **Dual mode**: CLI for automation, GUI picker for interactive use
- **Smart clipboard**: Copies as both markdown (plain text) and RTF (rich text)
- **Multi-browser support**: Safari, Chrome, Arc, Brave, Edge, Orion
- **Title transforms**: Automatic cleanup of backticks and GitHub suffixes
- **Multi-select**: Copy multiple tabs at once
- **Keyboard-driven**: Full keyboard navigation and shortcuts

## Installation

### From Source

Requires Swift 5.9+ and macOS 14+.

```bash
git clone https://github.com/yourusername/hyperlink.git
cd hyperlink
swift build -c release
cp .build/release/Hyperlink /usr/local/bin/hyperlink
```

### Permissions

Hyperlink requires Accessibility permissions to read browser tabs via AppleScript. On first launch, you'll be prompted to grant access in System Settings > Privacy & Security > Accessibility.

## Usage

### GUI Mode

Run without arguments to open the floating picker:

```bash
hyperlink
```

The picker shows all tabs from running browsers. Click a tab or press 1-9 to copy it as a markdown link.

### CLI Mode

```bash
# Copy active tab of frontmost browser
hyperlink --browser safari

# Copy specific tab by index
hyperlink --browser chrome --tab 3

# Copy all tabs as JSON to stdout
hyperlink --browser arc --tab all --stdout --format json

# Output to stdout instead of clipboard
hyperlink --browser safari --stdout
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--browser <name>` | Browser: `safari`, `chrome`, `arc`, `brave`, `edge`, `orion` | Frontmost |
| `--tab <spec>` | Tab: 1-based index, `active`, or `all` | `active` |
| `--stdout` | Output to stdout instead of clipboard | Off |
| `--format <fmt>` | Format: `markdown`, `json` | `markdown` |

## Keyboard Shortcuts (GUI)

| Key | Action |
|-----|--------|
| `1-9` | Copy nth visible tab |
| `Cmd+1-9` | Switch browser |
| `Arrow Up/Down` | Navigate list |
| `Enter` | Copy highlighted tab |
| `Space` | Toggle checkbox |
| `Cmd+Enter` | Copy all selected |
| `Escape` | Close |

## Configuration

Preferences are stored in `~/Library/Preferences/hyperlink.plist`:

| Setting | Default | Description |
|---------|---------|-------------|
| `removeBackticks` | `true` | Remove backticks from titles |
| `trimGitHubSuffix` | `true` | Remove " - owner/repo" from GitHub titles |
| `multiSelectionFormat` | `list` | Multi-tab format: `list`, `plain` |

## Output Formats

**Clipboard** (default): Sets both plain text (markdown) and RTF (clickable link).

```
[Page Title](https://example.com)
```

**JSON** (with `--format json --stdout`):

```json
{
  "browser": "safari",
  "window": 1,
  "tab": 1,
  "title": "Page Title",
  "url": "https://example.com"
}
```

## Development

### Building

```bash
swift build
```

### Testing

```bash
# Unit tests
swift test

# Integration tests (uses mock data, no browser required)
./scripts/integration-test.sh
```

### Project Structure

```
Sources/Hyperlink/
├── Hyperlink.swift       # Entry point
├── Core/                 # Shared utilities
├── Browsers/             # Browser implementations
└── GUI/                  # SwiftUI interface
```

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

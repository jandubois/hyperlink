# Hyperlink

A native macOS utility for extracting hyperlinks from browser tabs. Copy any browser tab as a markdown link with a single keystroke.

## Features

- **Dual mode**: CLI for automation, GUI picker for interactive use
- **Smart clipboard**: Copies as both markdown (plain text) and RTF (rich text)
- **Multi-browser support**: Safari, Chrome, Arc, Brave, Edge, Orion
- **Chrome profiles**: Separate tabs per profile, with profile name in the browser tab bar
- **Multi-select**: Copy multiple tabs at once as a list
- **Link extraction**: Extract all links from a page, then browse and copy them
- **Link preview**: Hover over any tab to see Open Graph metadata (title, description, image)
- **Grouping and sorting**: Group tabs by domain, sort by URL or title
- **Title transforms**: Regex-based rules to clean up titles (per-app or global)
- **Pinned tab awareness**: Select All cycles through unpinned, then all
- **Keyboard-driven**: Full keyboard navigation and shortcuts
- **Paste mode**: Paste directly into any app instead of copying to clipboard

## Installation

Requires Swift 5.9+ and macOS 14+.

```bash
git clone https://github.com/jkrauss/hyperlink.git
cd hyperlink
make release
cp .build/release/hyperlink /usr/local/bin/hyperlink
```

### Permissions

Hyperlink requires Accessibility permissions to read browser tabs via AppleScript. On first launch, you'll be prompted to grant access in System Settings > Privacy & Security > Accessibility.

## Usage

### GUI Mode

Run without arguments to open the floating picker:

```bash
hyperlink
```

The picker shows all tabs from running browsers. Click a tab or press 1–9 to copy it as a markdown link. Select multiple tabs with checkboxes and press Enter to copy them all.

By default, the GUI writes to stdout. Use `--copy` for clipboard output or `--paste` to paste directly into the frontmost app.

### CLI Mode

The CLI writes to stdout by default. Use `--copy` for clipboard output or `--paste` to paste directly.

```bash
# Active tab of frontmost browser (stdout)
hyperlink --browser safari

# Copy to clipboard instead
hyperlink --browser safari --copy

# Paste directly into the frontmost app
hyperlink --browser chrome --paste

# Paste into a specific app
hyperlink --browser safari --paste-app Slack

# Specific tab by index
hyperlink --browser chrome --tab 3

# All tabs as JSON
hyperlink --browser arc --tab all --format json

# All tabs as markdown, copied to clipboard
hyperlink --browser safari --tab all --copy
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--browser <name>` | Browser: `safari`, `chrome`, `arc`, `brave`, `edge`, `orion`, `frontmost` | `frontmost` |
| `--tab <spec>` | Tab: 1-based index, `active`, or `all` | `active` |
| `--copy` | Copy to clipboard instead of stdout | Off |
| `--paste` | Paste into frontmost app | Off |
| `--paste-app <name>` | Paste into a specific app (implies `--paste`) | — |
| `--format <fmt>` | Output format: `markdown`, `json` | `markdown` |
| `--save-data <path>` | Save all browser data to a JSON snapshot | — |
| `--mock-data <path>` | Load mock data instead of querying browsers | — |

`--copy` and `--paste` are mutually exclusive. `--paste-app` implies `--paste`.

## GUI Features

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `1-9` | Copy nth visible tab |
| `Ctrl+1-9` | Copy nth tab (works even when search field has focus) |
| `Up/Down` | Navigate list |
| `Enter` | Copy highlighted tab (or selected tabs if any are checked) |
| `Space` | Toggle checkbox |
| `Cmd+Enter` | Extract links from highlighted page |
| `Cmd+1-9` | Switch browser |
| `Cmd+Left/Right` | Switch browser |
| `Left/Right` | Collapse/expand group (when list has focus) |
| `Cmd+Up/Down` | Jump to previous/next group header |
| `Home/End` | Jump to first/last item |
| `Page Up/Down` | Scroll by 10 items |
| `Tab` | Toggle focus between search field and list |
| `Escape` | Clear search, or close picker |
| `Cmd+Delete` | Close extracted link tab |
| `Cmd+,` | Open settings |
| `?` | Show keyboard shortcut help |

Typing any character while the list has focus automatically switches to the search field.

### Link Extraction

Press `Cmd+Enter` on any tab to extract all links from that page. Hyperlink fetches the page source from the browser (falling back to a direct HTTP request if needed), parses the HTML for links, and presents them as a new tab source in the browser bar.

Extracted sources appear to the left of browser tabs with the page's favicon. Close them with `Cmd+Delete`. You can extract links from extracted sources too — each opens as a new tab.

### Link Preview

Hover over any tab to see an Open Graph preview panel beside the picker. The preview shows the page's title, description, and image when available. Previews are cached and load on demand.

### Grouping and Sorting

Tabs are automatically grouped by domain when a browser has more than 12 visible tabs. Toggle grouping manually from the sort menu. Groups with many tabs subdivide by URL path.

The sort menu (icon in the toolbar) offers three orders — Original, By URL, and By Title — each with an ascending/descending toggle. Sort settings are per-browser.

### Select All

The master checkbox cycles through three states: None, Unpinned Only, and All. When a browser reports pinned tabs (Safari and Chrome), the first press selects only unpinned tabs; a second press adds pinned tabs.

### Title Transforms

Open settings with `Cmd+,` to manage title transform rules. Rules match tabs by URL prefix and apply regex find-and-replace to the title or URL before copying.

Two global rules are enabled by default:

- **Strip backticks** — removes `` ` `` characters from titles
- **GitHub suffix** — removes ` · owner/repo` from GitHub page titles

You can add app-specific rules that apply only when pasting into a particular app (via `--paste-app` or paste mode).

## Output Formats

**Single tab** — copies as both markdown and RTF:

```
[Page Title](https://example.com)
```

**Multiple tabs** — format set in preferences (`list`, `plain`, or `html`):

| Format | Markdown output |
|--------|----------------|
| `list` | `- [Title](url)` per line |
| `plain` | `[Title](url)` per line (no bullets) |
| `html` | Same as `list` in markdown; `<ul><li>` in RTF |

**JSON** (CLI only, with `--format json`):

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

```bash
# Build
make build

# Unit tests
make test

# Integration tests (uses mock data, no browser required)
./scripts/integration-test.sh

# Run specific integration test
./scripts/integration-test.sh startup
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (no tabs, script failure) |
| 2 | Invalid arguments |
| 3 | Permission denied |
| 4 | Browser not found or not running |

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

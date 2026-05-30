#!/bin/bash
#
# Integration tests for Hyperlink
#
# Usage: ./scripts/integration-test.sh [test-name]
#
# Runs GUI integration tests (via --test mode) and CLI stdout tests, both
# against mock data. Uses test-data.json for reproducible browser/tab state.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$PROJECT_DIR/.build/debug/hyperlink"
MOCK_DATA="$SCRIPT_DIR/test-data.json"
TIMEOUT_SEC=5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

passed=0
failed=0

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    passed=$((passed + 1))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    failed=$((failed + 1))
}

log_info() {
    echo -e "${YELLOW}→${NC} $1"
}

# Build the project
build() {
    log_info "Building project..."
    (cd "$PROJECT_DIR" && swift build 2>&1) || {
        log_fail "Build failed"
        exit 1
    }
    log_pass "Build succeeded"
}

# Run unit tests
unit_tests() {
    log_info "Running unit tests..."
    (cd "$PROJECT_DIR" && swift test 2>&1) || {
        log_fail "Unit tests failed"
        return 1
    }
    log_pass "Unit tests passed"
}

# Run the GUI in test mode with commands piped to stdin
# Args: test_name, commands (one per line), expected_patterns (one per line)
run_gui_test() {
    local test_name="$1"
    local commands="$2"
    local expected_patterns="$3"

    local output
    local exit_code=0

    # Run with timeout and capture stderr (where test logs go)
    output=$(echo "$commands" | timeout "$TIMEOUT_SEC" "$BINARY" --test --mock-data "$MOCK_DATA" 2>&1) || exit_code=$?

    # Timeout exit code is 124
    if [ $exit_code -eq 124 ]; then
        log_fail "$test_name: timed out after ${TIMEOUT_SEC}s"
        echo "Output: $output"
        return 1
    fi

    # Check for expected patterns (using fixed string matching)
    local all_found=true
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if ! echo "$output" | grep -qF "$pattern"; then
            log_fail "$test_name: missing expected pattern '$pattern'"
            all_found=false
        fi
    done <<< "$expected_patterns"

    if $all_found; then
        log_pass "$test_name"
    else
        echo "Full output:"
        echo "$output" | head -50
        return 1
    fi
}

# Run the CLI in stdout mode and compare its output byte-for-byte.
# Args: test_name, expected_stdout, cli_flags...
# The 'x' sentinel survives command substitution (which strips trailing
# newlines), so an exact match can assert that title/url emit none. Use
# $'...' in expected_stdout to embed newlines.
run_cli_test() {
    local test_name="$1"
    local expected="$2"
    shift 2

    local output
    output=$(timeout "$TIMEOUT_SEC" "$BINARY" --mock-data "$MOCK_DATA" "$@" 2>/dev/null || true; printf 'x')
    output="${output%x}"

    if [ "$output" = "$expected" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name"
        echo "  expected: $(printf '%s' "$expected" | od -c)"
        echo "  actual:   $(printf '%s' "$output" | od -c)"
    fi
}

# Run the CLI and assert stdout contains every fixed substring.
# Args: test_name, substrings (one per line), cli_flags...
# JSON key order varies between runs, so match key/value pairs rather than
# the whole document.
run_cli_contains() {
    local test_name="$1"
    local patterns="$2"
    shift 2

    local output
    output=$(timeout "$TIMEOUT_SEC" "$BINARY" --mock-data "$MOCK_DATA" "$@" 2>/dev/null || true)

    local all_found=true
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        if ! printf '%s' "$output" | grep -qF "$pattern"; then
            log_fail "$test_name: missing '$pattern'"
            all_found=false
        fi
    done <<< "$patterns"

    if $all_found; then
        log_pass "$test_name"
    fi
}

# Test: Basic startup and ready signal
test_startup() {
    run_gui_test "GUI starts and signals ready" \
        "wait:100
quit" \
        "[READY]
[RESULT] type=\"quit\""
}

# Test: Browser data is logged
test_browser_data() {
    run_gui_test "Browser data is logged" \
        "wait:100
quit" \
        "[BROWSER_DATA]
[TAB]"
}

# Test: Arrow key navigation
test_navigation() {
    run_gui_test "Arrow key navigation" \
        "wait:100
key:down
key:up
quit" \
        "key=\"down\"
key=\"up\"
name=\"highlightedIndex\""
}

# Test: Browser switching with left/right arrows
test_browser_switch() {
    # Note: This test requires at least 2 browsers running
    run_gui_test "Browser switching" \
        "wait:100
key:right
key:left
quit" \
        "key=\"right\"
key=\"left\"
name=\"selectedBrowserIndex\""
}

# Test: Search filtering
test_search() {
    run_gui_test "Search filtering" \
        "wait:100
search:test
wait:50
quit" \
        "name=\"searchText\"
value=\"test\""
}

# Test: Number key selection copies and exits
test_number_selection() {
    # Note: This test will only pass if there's at least one tab
    run_gui_test "Number key selection" \
        "wait:100
key:1" \
        "key=\"1\"
type=\"copy\""
}

# Test: Ctrl+number selection works even with search text
test_ctrl_number_selection() {
    # Search for "go" which should match most browser tabs (Google, etc.)
    run_gui_test "Ctrl+number selection with search" \
        "wait:100
search:go
wait:50
key:ctrl+1" \
        "name=\"searchText\"
key=\"ctrl+1\"
type=\"copy\""
}

# Test: Slash key adds to search text (no special behavior)
test_slash_search() {
    # Pressing / now just adds to search text
    run_gui_test "Slash adds to search" \
        "wait:100
key:/
quit" \
        "key=\"/\"
name=\"searchText\"
value=\"/\""
}

# Test: TAB toggles focus between list and search field
test_tab_focus() {
    run_gui_test "TAB toggles focus" \
        "wait:100
key:tab
wait:50
key:tab
quit" \
        "name=\"searchFieldHasFocus\"
value=true
value=false"
}

# Test: Select all tabs
test_select_all() {
    run_gui_test "Select all tabs" \
        "wait:100
select_all
quit" \
        "name=\"selectedCount\""
}

# Test: Toggle select all selects then deselects
test_toggle_select_all() {
    run_gui_test "Toggle select all" \
        "wait:100
toggle_select_all
toggle_select_all
quit" \
        "name=\"allSelected\"
value=true
value=false"
}

# Test: Escape dismisses
test_escape() {
    run_gui_test "Escape dismisses" \
        "wait:100
key:escape" \
        "key=\"escape\"
type=\"dismiss\"
reason=\"escape\""
}

# CLI stdout tests. Expected titles and URLs assume the default global
# transform rules, which leave this test data unchanged; JSON output ignores
# transforms.

# Test: Single-tab output for each format
test_cli_single() {
    run_cli_test "CLI markdown (single tab, no trailing newline)" \
        '[Apple](https://www.apple.com/)' \
        --browser safari --tab active --format markdown
    run_cli_test "CLI title (single tab, no trailing newline)" \
        'Apple' \
        --browser safari --tab active --format title
    run_cli_test "CLI url (single tab, no trailing newline)" \
        'https://www.apple.com/' \
        --browser safari --tab active --format url
}

# Test: All-tabs output for each format
test_cli_all() {
    run_cli_test "CLI markdown (all tabs, newline-separated, no trailing newline)" \
        $'[Apple](https://www.apple.com/)\n[Google Search](https://www.google.com/)\n[GitHub - Code hosting](https://github.com/)\n[Stack Overflow - Developer community](https://stackoverflow.com/)\n[Hacker News](https://news.ycombinator.com/)' \
        --browser safari --tab all --format markdown
    run_cli_test "CLI title (all tabs, newline-separated, no trailing newline)" \
        $'Apple\nGoogle Search\nGitHub - Code hosting\nStack Overflow - Developer community\nHacker News' \
        --browser safari --tab all --format title
    run_cli_test "CLI url (all tabs, newline-separated, no trailing newline)" \
        $'https://www.apple.com/\nhttps://www.google.com/\nhttps://github.com/\nhttps://stackoverflow.com/\nhttps://news.ycombinator.com/' \
        --browser safari --tab all --format url
}

# Test: JSON output carries the expected key/value pairs
test_cli_json() {
    run_cli_contains "CLI json (single tab)" \
        '"browser":"safari"
"window":1
"tab":1
"title":"Apple"
"url":"https:\/\/www.apple.com\/"' \
        --browser safari --tab active --format json
}

# Run all tests or specific test
run_tests() {
    local specific_test="$1"

    if [ -n "$specific_test" ]; then
        # Run specific test
        case "$specific_test" in
            startup) test_startup ;;
            browser_data) test_browser_data ;;
            navigation) test_navigation ;;
            browser_switch) test_browser_switch ;;
            search) test_search ;;
            number) test_number_selection ;;
            ctrl_number) test_ctrl_number_selection ;;
            slash) test_slash_search ;;
            tab_focus) test_tab_focus ;;
            select_all) test_select_all ;;
            toggle_select_all) test_toggle_select_all ;;
            escape) test_escape ;;
            cli_single) test_cli_single ;;
            cli_all) test_cli_all ;;
            cli_json) test_cli_json ;;
            unit) unit_tests ;;
            build) build ;;
            *)
                echo "Unknown test: $specific_test"
                echo "Available: startup, browser_data, navigation, browser_switch, search, number, ctrl_number, slash, tab_focus, select_all, toggle_select_all, escape, cli_single, cli_all, cli_json, unit, build"
                exit 1
                ;;
        esac
    else
        # Run all tests
        build
        unit_tests
        echo ""
        log_info "Running GUI integration tests..."
        log_info "(Using mock data from test-data.json)"
        echo ""

        test_startup
        test_browser_data
        test_navigation
        test_browser_switch
        test_search
        test_number_selection
        test_ctrl_number_selection
        test_slash_search
        test_tab_focus
        test_select_all
        test_toggle_select_all
        test_escape

        echo ""
        log_info "Running CLI stdout tests..."
        echo ""

        test_cli_single
        test_cli_all
        test_cli_json
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "─────────────────────────────────────"
    echo -e "Passed: ${GREEN}$passed${NC}  Failed: ${RED}$failed${NC}"
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed${NC}"
        exit 1
    fi
}

# Main
run_tests "$1"
print_summary

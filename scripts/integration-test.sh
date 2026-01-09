#!/bin/bash
#
# Integration tests for Hyperlink
#
# Usage: ./scripts/integration-test.sh [test-name]
#
# Runs GUI integration tests using the --test mode.
# Requires at least one browser to be running with some tabs open.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BINARY="$PROJECT_DIR/.build/debug/hyperlink"
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
    output=$(echo "$commands" | timeout "$TIMEOUT_SEC" "$BINARY" --test 2>&1) || exit_code=$?

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

# Test: Search filtering
test_search() {
    run_gui_test "Search filtering" \
        "wait:100
search:test
wait:50
quit" \
        "[STATE] value=\"test\" name=\"searchText\""
}

# Test: Number key selection copies and exits
test_number_selection() {
    # Note: This test will only pass if there's at least one tab
    run_gui_test "Number key selection" \
        "wait:100
key:1" \
        "[KEY] key=\"1\"
[RESULT] type=\"copy\""
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

# Run all tests or specific test
run_tests() {
    local specific_test="$1"

    if [ -n "$specific_test" ]; then
        # Run specific test
        case "$specific_test" in
            startup) test_startup ;;
            browser_data) test_browser_data ;;
            navigation) test_navigation ;;
            search) test_search ;;
            number) test_number_selection ;;
            escape) test_escape ;;
            unit) unit_tests ;;
            build) build ;;
            *)
                echo "Unknown test: $specific_test"
                echo "Available: startup, browser_data, navigation, search, number, escape, unit, build"
                exit 1
                ;;
        esac
    else
        # Run all tests
        build
        unit_tests
        echo ""
        log_info "Running GUI integration tests..."
        log_info "(Requires at least one browser to be running with tabs)"
        echo ""

        test_startup
        test_browser_data
        test_navigation
        test_search
        test_escape
        # test_number_selection  # Skipped by default as it copies to clipboard
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

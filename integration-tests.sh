#!/usr/bin/env bash
# integration-tests.sh - Integration tests for ralph loop
#
# These tests run actual agent iterations and verify core workflows.
# Requires opencode/claudecode installation and valid API credentials.
#
# Usage:
#   ./integration-tests.sh                    # Run all tests
#   SKIP_INTEGRATION_TESTS=1 ./tests.sh       # Skip in CI
#   TEST_AGENT=claudecode ./integration-tests.sh  # Test specific agent

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR=$(mktemp -d)
PASSED=0
FAILED=0
TOTAL=0

# Respect NO_COLOR standard and non-terminal output
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
	RED=""
	GREEN=""
	YELLOW=""
	NC=""
else
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[0;33m'
	NC='\033[0m'
fi

cleanup() {
	rm -rf "$TEST_DIR"
}
trap cleanup EXIT

log_test() {
	TOTAL=$((TOTAL + 1))
	echo -e "${YELLOW}INTEGRATION TEST:${NC} $1"
}

pass() {
	PASSED=$((PASSED + 1))
	echo -e "  ${GREEN}✓ PASSED${NC}"
}

fail() {
	FAILED=$((FAILED + 1))
	echo -e "  ${RED}✗ FAILED: $1${NC}"
}

assert_file_exists() {
	if [[ -f "$1" ]]; then
		pass
	else
		fail "File not found: $1"
	fi
}

assert_file_contains() {
	if grep -qF "$2" "$1" 2>/dev/null; then
		pass
	else
		fail "File $1 does not contain '$2'"
	fi
}

assert_not_empty() {
	if [[ -s "$1" ]]; then
		pass
	else
		fail "File is empty: $1"
	fi
}

# Determine which agent to test (default: opencode if available, else claudecode)
TEST_AGENT="${TEST_AGENT:-opencode}"
if ! command -v opencode >/dev/null 2>&1 && [[ "$TEST_AGENT" == "opencode" ]]; then
	echo "Warning: opencode not found, testing with claudecode instead"
	TEST_AGENT="claudecode"
fi

if ! command -v "$TEST_AGENT" >/dev/null 2>&1; then
	echo "Error: Neither opencode nor claudecode found. Cannot run integration tests." >&2
	exit 1
fi

echo "============================================="
echo "Agent Orchestrator Integration Tests"
echo "============================================="
echo "Agent: $TEST_AGENT"
echo "Test directory: $TEST_DIR"
echo ""

# =============================================
# Basic agent execution
# =============================================
echo "--- Basic agent execution ---"

log_test "ralph loop produces output for simple prompt"
WORK_DIR="$TEST_DIR/test-simple"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
"$SCRIPT_DIR/ralph" loop "Just say hi" --max 1 --sandbox none --agent "$TEST_AGENT" > output.log 2>&1 &
RALPH_PID=$!
# Wait up to 60s for completion
for i in {1..60}; do
	if ! kill -0 $RALPH_PID 2>/dev/null; then
		break
	fi
	sleep 1
done
# Kill if still running
if kill -0 $RALPH_PID 2>/dev/null; then
	kill $RALPH_PID 2>/dev/null || true
	wait $RALPH_PID 2>/dev/null || true
fi
# Check what actually exists
echo "  DEBUG: Checking for logs..." >&2
ls -la .ralph/ 2>&1 | head -5 >&2 || echo "  .ralph doesn't exist" >&2
find .ralph -name "*.log" 2>&1 | head -5 >&2 || echo "  No logs found" >&2
if [[ -d .ralph ]] && [[ -n "$(find .ralph -name 'iteration-1.log' 2>/dev/null)" ]]; then
	LOG_FILE=$(find .ralph -name 'iteration-1.log' | head -1)
	assert_not_empty "$LOG_FILE"
else
	echo "  Ralph output:"
	cat output.log | head -30
	fail "No iteration log found"
fi

log_test "ralph loop creates session directory structure"
SESSION_DIR=$(find "$WORK_DIR/.ralph" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -d "$SESSION_DIR" ]]; then
	pass
else
	fail "Session directory not created"
fi

log_test "iteration log contains agent output"
if [[ -n "${LOG_FILE:-}" ]]; then
	# Should contain some text output from the agent
	if [[ $(wc -c < "$LOG_FILE") -gt 50 ]]; then
		pass
	else
		fail "Log file too small ($(wc -c < "$LOG_FILE") bytes)"
	fi
else
	fail "LOG_FILE not set"
fi

# =============================================
# File operations
# =============================================
echo ""
echo "--- File operations ---"

log_test "agent can read files"
WORK_DIR="$TEST_DIR/test-read"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
echo "test content 12345" > test-file.txt
timeout 120 "$SCRIPT_DIR/ralph" loop "Read test-file.txt and tell me what it contains" --max 1 --sandbox none --agent "$TEST_AGENT" > output.log 2>&1 || true
LOG_FILE=$(find .ralph/*/logs/iteration-1.log 2>/dev/null | head -1)
if [[ -f "$LOG_FILE" ]]; then
	# Log should contain evidence of reading the file (the Read tool or file content)
	if grep -qE "(Read|test-file\.txt|test content|12345)" "$LOG_FILE"; then
		pass
	else
		fail "No evidence of file read in log"
	fi
else
	fail "No iteration log found"
fi

log_test "agent can write files"
WORK_DIR="$TEST_DIR/test-write"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
timeout 120 "$SCRIPT_DIR/ralph" loop "Create a file named hello.txt with content 'Hello World'" --max 2 --sandbox none --agent "$TEST_AGENT" > output.log 2>&1 || true
if [[ -f hello.txt ]]; then
	if grep -qF "Hello World" hello.txt; then
		pass
	else
		fail "File created but doesn't contain expected content"
	fi
else
	fail "File not created"
fi

# =============================================
# Multi-iteration behavior
# =============================================
echo ""
echo "--- Multi-iteration behavior ---"

log_test "multiple iterations create separate logs"
WORK_DIR="$TEST_DIR/test-multi"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
timeout 180 "$SCRIPT_DIR/ralph" loop "Count to 3, one number per iteration. Output <promise>COMPLETE</promise> after 3" --min 3 --max 5 --sandbox none --agent "$TEST_AGENT" > output.log 2>&1 || true
SESSION_DIR=$(find .ralph -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
if [[ -d "$SESSION_DIR/logs" ]]; then
	LOG_COUNT=$(find "$SESSION_DIR/logs" -name "iteration-*.log" 2>/dev/null | wc -l)
	LOG_COUNT="${LOG_COUNT// /}"
	if [[ $LOG_COUNT -ge 3 ]]; then
		pass
	else
		fail "Expected at least 3 iteration logs, found $LOG_COUNT"
	fi
else
	fail "Logs directory not found"
fi

log_test "history.json tracks iterations"
if [[ -f "$SESSION_DIR/history.json" ]]; then
	# Should have at least 3 entries
	ENTRY_COUNT=$(jq 'length' "$SESSION_DIR/history.json" 2>/dev/null || echo 0)
	if [[ $ENTRY_COUNT -ge 3 ]]; then
		pass
	else
		fail "Expected at least 3 history entries, found $ENTRY_COUNT"
	fi
else
	fail "history.json not found"
fi

# =============================================
# Completion detection
# =============================================
echo ""
echo "--- Completion detection ---"

log_test "completion marker stops the loop"
WORK_DIR="$TEST_DIR/test-completion"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
timeout 120 "$SCRIPT_DIR/ralph" loop "Output <promise>COMPLETE</promise> immediately" --max 5 --sandbox none --agent "$TEST_AGENT" > output.log 2>&1 || true
SESSION_DIR=$(find .ralph -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
if [[ -d "$SESSION_DIR/logs" ]]; then
	LOG_COUNT=$(find "$SESSION_DIR/logs" -name "iteration-*.log" 2>/dev/null | wc -l)
	LOG_COUNT="${LOG_COUNT// /}"
	# Should stop after 1-2 iterations (sometimes takes 2 if agent doesn't comply immediately)
	if [[ $LOG_COUNT -le 3 ]]; then
		pass
	else
		fail "Loop didn't stop on completion (ran $LOG_COUNT iterations)"
	fi
else
	fail "Logs directory not found"
fi

# =============================================
# Error handling
# =============================================
echo ""
echo "--- Error handling ---"

log_test "invalid model triggers fallback or clear error"
WORK_DIR="$TEST_DIR/test-invalid-model"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
set +e
timeout 60 "$SCRIPT_DIR/ralph" loop "test" --model "invalid/nonexistent-model-xyz" --max 1 --sandbox none --agent "$TEST_AGENT" > output.log 2>&1
EXIT_CODE=$?
set -e
# Either fails gracefully (exit 1) or falls back to another model
if [[ $EXIT_CODE -ne 0 ]] || grep -qE "(fallback|Error|rate limit)" output.log; then
	pass
else
	fail "No error handling for invalid model"
fi

# =============================================
# Summary
# =============================================
echo ""
echo "============================================="
echo "Integration Test Results"
echo "============================================="
echo "Total:   $TOTAL"
echo "Passed:  $PASSED"
echo "Failed:  $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
	echo -e "${GREEN}All integration tests passed!${NC}"
	exit 0
else
	echo -e "${RED}Some integration tests failed.${NC}"
	exit 1
fi

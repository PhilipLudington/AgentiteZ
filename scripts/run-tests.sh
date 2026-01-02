#!/bin/bash
# Run Zig tests and output results in GitStat JSON format

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_FILE="$PROJECT_ROOT/.test-results.json"

cd "$PROJECT_ROOT"

# Run tests and capture output
OUTPUT=$(zig build test --summary all 2>&1) || true

# Parse the output to extract test counts
# Expected format: "run test 27 passed 2ms" or "run test 25 passed 2 failed"
if echo "$OUTPUT" | grep -q "passed"; then
    # Extract passed count
    PASSED=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+')

    # Extract failed count (0 if not present)
    if echo "$OUTPUT" | grep -q "failed"; then
        FAILED=$(echo "$OUTPUT" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '[0-9]+')
    else
        FAILED=0
    fi

    # Calculate total
    TOTAL=$((PASSED + FAILED))

    # Extract failure names if any
    FAILURES="[]"
    if [ "$FAILED" -gt 0 ]; then
        # Try to extract failed test names from output
        FAILURE_NAMES=$(echo "$OUTPUT" | grep -E "^test\." | grep -v "OK" | sed 's/^test\.//' | sed 's/ .*//' | head -20)
        if [ -n "$FAILURE_NAMES" ]; then
            FAILURES=$(echo "$FAILURE_NAMES" | jq -R . | jq -s .)
        fi
    fi
else
    # No test output - likely a build error
    PASSED=0
    FAILED=1
    TOTAL=1
    FAILURES='["Build failed"]'
fi

# Write results JSON
cat > "$RESULTS_FILE" << EOF
{
  "passed": $PASSED,
  "failed": $FAILED,
  "total": $TOTAL,
  "failures": $FAILURES
}
EOF

# Print summary
echo "Tests: $PASSED/$TOTAL passed"
if [ "$FAILED" -gt 0 ]; then
    echo "Failed: $FAILED"
    exit 1
fi

#!/bin/bash
# Build Zig project and output results in GitStat JSON format

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_FILE="$PROJECT_ROOT/.build-results.json"

cd "$PROJECT_ROOT"

# Run build and capture output
OUTPUT=$(zig build 2>&1) || BUILD_FAILED=1

# Count warnings and errors from output
WARNINGS=$(echo "$OUTPUT" | grep -c "warning:" || true)
ERRORS=$(echo "$OUTPUT" | grep -c "error:" || true)

# Extract messages (first 10 warnings/errors)
MESSAGES="[]"
if [ -n "$OUTPUT" ]; then
    MSG_LINES=$(echo "$OUTPUT" | grep -E "(warning:|error:)" | head -10)
    if [ -n "$MSG_LINES" ]; then
        MESSAGES=$(echo "$MSG_LINES" | jq -R . | jq -s .)
    fi
fi

# Determine success
if [ -z "$BUILD_FAILED" ] && [ "$ERRORS" -eq 0 ]; then
    SUCCESS=true
else
    SUCCESS=false
fi

# Write results JSON
cat > "$RESULTS_FILE" << EOF
{
  "success": $SUCCESS,
  "errors": $ERRORS,
  "warnings": $WARNINGS,
  "messages": $MESSAGES
}
EOF

# Print summary
if [ "$SUCCESS" = true ]; then
    if [ "$WARNINGS" -gt 0 ]; then
        echo "Build succeeded with $WARNINGS warning(s)"
    else
        echo "Build succeeded"
    fi
else
    echo "Build failed with $ERRORS error(s)"
    exit 1
fi

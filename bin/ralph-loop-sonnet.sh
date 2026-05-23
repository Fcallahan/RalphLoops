#!/usr/bin/env bash
# ralph-loop-sonnet — run the Claude Ralph loop with Sonnet defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RALPH_CLAUDE_MODEL="${RALPH_CLAUDE_MODEL:-sonnet}"
export RALPH_CLAUDE_EFFORT="${RALPH_CLAUDE_EFFORT:-high}"
exec "$SCRIPT_DIR/ralph-loop-claude.sh" "$@"

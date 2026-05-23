#!/usr/bin/env bash
# ralph-loop-opus — run the Claude Ralph loop with Opus defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RALPH_CLAUDE_MODEL="${RALPH_CLAUDE_MODEL:-opus}"
export RALPH_CLAUDE_EFFORT="${RALPH_CLAUDE_EFFORT:-medium}"
exec "$SCRIPT_DIR/ralph-loop-claude.sh" "$@"

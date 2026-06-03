#!/usr/bin/env bash
# ralph-loop-pi-deepseek — wrap `pi` in a Ralph loop using DeepSeek.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RALPH_LOOP_PI_COMMAND_NAME="ralph-loop-pi-deepseek"
export RALPH_LOOP_PI_MODEL="openrouter/deepseek/deepseek-v4-flash"
export RALPH_LOOP_PI_DEFAULT_THINKING="high"
exec "$SCRIPT_DIR/ralph-loop-pi.sh" "$@"

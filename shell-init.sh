#!/usr/bin/env bash
# Sourced from ~/.zshrc by install.sh. Defines ralph-loop-* shell functions.

export RALPH_LOOPS_DIR="${RALPH_LOOPS_DIR:-$HOME/code/Work/Ralphloops}"

ralph-loop-claude() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-claude.sh" "$@"
}

ralph-loop-codex() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-codex.sh" "$@"
}

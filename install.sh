#!/usr/bin/env bash
# Idempotently wires Ralphloops into ~/.zshrc and makes scripts executable.
set -euo pipefail

RALPH_LOOPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="$HOME/.zshrc"
SOURCE_LINE="source \"$RALPH_LOOPS_DIR/shell-init.sh\""
MARKER="# >>> ralphloops >>>"
END_MARKER="# <<< ralphloops <<<"

chmod +x \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-claude.sh" \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-sonnet.sh" \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-opus.sh" \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-codex.sh" \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-pi.sh" \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-pi-deepseek.sh" \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-auto.sh" \
  "$RALPH_LOOPS_DIR/bin/ralph-loop-smart.sh" \
  "$RALPH_LOOPS_DIR/bin/shims/git" \
  "$RALPH_LOOPS_DIR/bin/shims/rm" \
  "$RALPH_LOOPS_DIR/bin/shims/sudo" \
  "$RALPH_LOOPS_DIR/shell-init.sh"

if [[ ! -f "$ZSHRC" ]]; then
  touch "$ZSHRC"
fi

if grep -Fq "$MARKER" "$ZSHRC"; then
  echo "install.sh: ralphloops block already present in $ZSHRC — skipping"
else
  {
    echo ""
    echo "$MARKER"
    echo "$SOURCE_LINE"
    echo "$END_MARKER"
  } >> "$ZSHRC"
  echo "install.sh: appended ralphloops block to $ZSHRC"
fi

echo
echo "Done. Open a new shell (or run: source $RALPH_LOOPS_DIR/shell-init.sh) to use:"
echo "  ralph-loop-claude <pre-prompt> <iterations> \"<request>\""
echo "  ralph-loop-sonnet <pre-prompt> <iterations> \"<request>\""
echo "  ralph-loop-opus   <pre-prompt> <iterations> \"<request>\""
echo "  ralph-loop-codex  <pre-prompt> <iterations> \"<request>\""
echo "  ralph-loop-pi          [--thinking medium] <pre-prompt> <iterations> \"<request>\""
echo "  ralph-loop-pi-deepseek [--thinking high]   <pre-prompt> <iterations> \"<request>\""
echo "  ralph-loop-auto        [--thinking medium] <pre-prompt> <iterations> \"<request>\""
echo "  ralph-loop-smart       <pre-prompt> <iterations> \"<request>\""

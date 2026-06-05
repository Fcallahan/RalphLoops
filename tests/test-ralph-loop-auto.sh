#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/pi" <<'FAKE_PI'
#!/usr/bin/env bash
calls=0
if [[ -f "$PI_CALLS" ]]; then
  calls="$(cat "$PI_CALLS")"
fi
calls=$((calls + 1))
printf '%s' "$calls" > "$PI_CALLS"
{
  printf '%s\n' "--- pi invocation $calls ---"
  printf '%s\n' "$@"
} >> "$PI_CAPTURE"
printf '%s\n' "You've exceeded your 5 hour limit"
exit 1
FAKE_PI
chmod +x "$FAKE_BIN/pi"

cat > "$FAKE_BIN/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
calls=0
if [[ -f "$CLAUDE_CALLS" ]]; then
  calls="$(cat "$CLAUDE_CALLS")"
fi
calls=$((calls + 1))
printf '%s' "$calls" > "$CLAUDE_CALLS"
{
  printf '%s\n' "--- claude invocation $calls ---"
  printf '%s\n' "$@"
} >> "$CLAUDE_CAPTURE"
printf '%s\n' 'claude ok'
FAKE_CLAUDE
chmod +x "$FAKE_BIN/claude"

export PI_CAPTURE="$TMP_DIR/pi-args.log"
export PI_CALLS="$TMP_DIR/pi-calls.txt"
export CLAUDE_CAPTURE="$TMP_DIR/claude-args.log"
export CLAUDE_CALLS="$TMP_DIR/claude-calls.txt"
export PATH="$FAKE_BIN:$PATH"

WORKTREE="$TMP_DIR/worktree"
mkdir -p "$WORKTREE"
cd "$WORKTREE"

"$REPO_ROOT/bin/ralph-loop-auto.sh" plan-implement 2 "Inline prompt body" >/tmp/ralph-loop-auto-test-output.log

[[ "$(cat "$PI_CALLS")" == "1" ]]
[[ "$(cat "$CLAUDE_CALLS")" == "2" ]]

grep -q -- '--model' "$PI_CAPTURE"
grep -q -- 'openai-codex/gpt-5.5' "$PI_CAPTURE"
grep -q -- '--thinking' "$PI_CAPTURE"
grep -q -- 'medium' "$PI_CAPTURE"
grep -q -- 'Inline prompt body' "$PI_CAPTURE"

grep -q -- '--model' "$CLAUDE_CAPTURE"
grep -q -- 'opus' "$CLAUDE_CAPTURE"
grep -q -- '--effort' "$CLAUDE_CAPTURE"
grep -q -- 'medium' "$CLAUDE_CAPTURE"
grep -q -- '--system-prompt-file' "$CLAUDE_CAPTURE"
grep -q -- 'Inline prompt body' "$CLAUDE_CAPTURE"
grep -q -- 'iteration 1 of 2' "$CLAUDE_CAPTURE"
grep -q -- 'iteration 2 of 2' "$CLAUDE_CAPTURE"

find .ralph-loop -name '*-iter-1.log' | grep -q .
find .ralph-loop -name '*-iter-1-claude-fallback.log' | grep -q .
find .ralph-loop -name '*-iter-2-claude.log' | grep -q .

#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/pi" <<'FAKE_PI'
#!/usr/bin/env bash
{
  printf '%s\n' '--- pi invocation ---'
  printf '%s\n' "$@"
} >> "$PI_CAPTURE"
printf '%s\n' 'OK'
FAKE_PI
chmod +x "$FAKE_BIN/pi"

cat > "$FAKE_BIN/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
{
  printf '%s\n' '--- claude invocation ---'
  printf '%s\n' "$@"
} >> "$CLAUDE_CAPTURE"
printf '%s\n' 'claude output with shell-looking text:'
printf '%s\n' '$(t'
printf '%s\n' 'Review:'
printf '%s\n' '</role>'
printf '%s\n' '`uname`'
FAKE_CLAUDE
chmod +x "$FAKE_BIN/claude"

export PI_CAPTURE="$TMP_DIR/pi-args.log"
export CLAUDE_CAPTURE="$TMP_DIR/claude-args.log"
export PATH="$FAKE_BIN:$PATH"

WORKTREE="$TMP_DIR/worktree"
mkdir -p "$WORKTREE"
cd "$WORKTREE"
git init -q

RALPH_SMART_SKIP_REVIEW=1 RALPH_SMART_SKIP_FIX=1 \
  "$REPO_ROOT/bin/ralph-loop-smart.sh" plan-implement 1 "Inline prompt body" >/tmp/ralph-loop-smart-test-default.log

grep -q -- '--model' "$PI_CAPTURE"
grep -q -- 'openai-codex/gpt-5.3-codex-spark' "$PI_CAPTURE"
grep -q -- '--thinking' "$PI_CAPTURE"
grep -q -- 'off' "$PI_CAPTURE"
grep -q -- 'scouts:     pi openai-codex/gpt-5.3-codex-spark / off x2' /tmp/ralph-loop-smart-test-default.log
grep -q -- 'Scout focus: file map and implementation surface.' "$PI_CAPTURE"
grep -q -- 'Scout focus: validation, risk, and edge cases.' "$PI_CAPTURE"

: > "$PI_CAPTURE"
RALPH_SMART_SKIP_REVIEW=1 RALPH_SMART_SKIP_FIX=1 \
  "$REPO_ROOT/bin/ralph-loop-smart.sh" --scout-model test/provider --scout-thinking "no thinking" \
  plan-implement 1 "Inline prompt body" >/tmp/ralph-loop-smart-test-override.log

grep -q -- 'test/provider' "$PI_CAPTURE"
grep -q -- '--thinking' "$PI_CAPTURE"
grep -q -- 'off' "$PI_CAPTURE"
grep -q -- 'scouts:     pi test/provider / off x2' /tmp/ralph-loop-smart-test-override.log

: > "$PI_CAPTURE"
"$REPO_ROOT/bin/ralph-loop-smart.sh" plan-implement 1 "Review and fix prompt body" >/tmp/ralph-loop-smart-test-review-fix.log

LATEST_ITER="$(find .ralph-loop -path '*/iter-1' -type d -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)"
grep -q -- '--- reviewer (read-only) ---' /tmp/ralph-loop-smart-test-review-fix.log
grep -q -- '--- pi fix worker (sole writer) ---' /tmp/ralph-loop-smart-test-review-fix.log
grep -q -- '$(t' "$LATEST_ITER/fix-prompt.md"
grep -q -- '</role>' "$LATEST_ITER/fix-prompt.md"

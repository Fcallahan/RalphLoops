#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/pi" <<'FAKE_PI'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$PI_CAPTURE"
printf '%s\n' 'pi ok'
FAKE_PI
chmod +x "$FAKE_BIN/pi"

export PI_CAPTURE="$TMP_DIR/pi-args.log"
export PATH="$FAKE_BIN:$PATH"

WORKTREE="$TMP_DIR/worktree"
mkdir -p "$WORKTREE"
cd "$WORKTREE"

"$REPO_ROOT/bin/ralph-loop-pi-deepseek.sh" plan-implement 1 "Inline prompt body" >/tmp/ralph-loop-pi-deepseek-test-output.log

grep -q -- '--model' "$PI_CAPTURE"
grep -q -- 'openrouter/deepseek/deepseek-v4-flash' "$PI_CAPTURE"
grep -q -- '--thinking' "$PI_CAPTURE"
grep -q -- 'high' "$PI_CAPTURE"
grep -q -- 'Inline prompt body' "$PI_CAPTURE"

: > "$PI_CAPTURE"
"$REPO_ROOT/bin/ralph-loop-pi-deepseek.sh" --thinking medium plan-implement 1 "Override thinking" >/tmp/ralph-loop-pi-deepseek-test-output-override.log

grep -q -- 'openrouter/deepseek/deepseek-v4-flash' "$PI_CAPTURE"
grep -q -- 'medium' "$PI_CAPTURE"

: > "$PI_CAPTURE"
"$REPO_ROOT/bin/ralph-loop-pi-deepseek.sh" --thinking "no thinking" plan-implement 1 "Disable thinking" >/tmp/ralph-loop-pi-deepseek-test-output-no-thinking.log

grep -q -- 'openrouter/deepseek/deepseek-v4-flash' "$PI_CAPTURE"
grep -q -- 'off' "$PI_CAPTURE"

: > "$PI_CAPTURE"
"$REPO_ROOT/bin/ralph-loop-pi-deepseek.sh" --thinking none plan-implement 1 "Disable thinking alias" >/tmp/ralph-loop-pi-deepseek-test-output-none.log

grep -q -- 'off' "$PI_CAPTURE"

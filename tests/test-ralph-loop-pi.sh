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
printf '%s\n' 'pi ok'
FAKE_PI
chmod +x "$FAKE_BIN/pi"

export PI_CAPTURE="$TMP_DIR/pi-args.log"
export PATH="$FAKE_BIN:$PATH"

WORKTREE="$TMP_DIR/worktree"
mkdir -p "$WORKTREE"
REQUEST_FILE="$TMP_DIR/request.md"
printf '%s\n' 'Large prompt body from file' > "$REQUEST_FILE"

cd "$WORKTREE"
"$REPO_ROOT/bin/ralph-loop-pi.sh" --thinking high plan-implement 1 --file "$REQUEST_FILE" >/tmp/ralph-loop-pi-test-output.log

grep -q -- 'pi ok' .ralph-loop/*-iter-1.log
grep -q -- '--model' "$PI_CAPTURE"
grep -q -- 'openai-codex/gpt-5.5' "$PI_CAPTURE"
grep -q -- '--thinking' "$PI_CAPTURE"
grep -q -- 'high' "$PI_CAPTURE"
grep -q -- '-p' "$PI_CAPTURE"
grep -q -- "@$REQUEST_FILE" "$PI_CAPTURE"

: > "$PI_CAPTURE"
"$REPO_ROOT/bin/ralph-loop-pi.sh" plan-implement 1 "Inline prompt body" >/tmp/ralph-loop-pi-test-output-default.log

grep -q -- '--thinking' "$PI_CAPTURE"
grep -q -- 'medium' "$PI_CAPTURE"
grep -q -- 'Inline prompt body' "$PI_CAPTURE"

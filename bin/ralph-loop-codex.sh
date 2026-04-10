#!/usr/bin/env bash
# ralph-loop-codex — wrap `codex exec` in a Ralph loop.
# Usage: ralph-loop-codex <pre-prompt> <iterations> <request...>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_LOOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF >&2
Usage: ralph-loop-codex <pre-prompt> <iterations> <request...>

  <pre-prompt>   Path to a markdown file, OR the bare name of a prompt
                 in $RALPH_LOOPS_DIR/prompts/ (without .md).
  <iterations>   Positive integer — how many Ralph loop iterations to run.
  <request...>   The task description (everything after iterations is joined).

Example:
  ralph-loop-codex plan-implement 3 "build me a feature that does X"
EOF
  exit 2
}

[[ $# -ge 3 ]] || usage

PROMPT_ARG="$1"; shift
ITERATIONS="$1"; shift
USER_REQUEST="$*"

if [[ -f "$PROMPT_ARG" ]]; then
  PROMPT_FILE="$PROMPT_ARG"
elif [[ -f "$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" ]]; then
  PROMPT_FILE="$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md"
else
  echo "ralph-loop-codex: pre-prompt not found: $PROMPT_ARG" >&2
  echo "  tried: $PROMPT_ARG" >&2
  echo "  tried: $RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" >&2
  exit 2
fi

if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ralph-loop-codex: iterations must be a positive integer, got: $ITERATIONS" >&2
  exit 2
fi

[[ -n "$USER_REQUEST" ]] || { echo "ralph-loop-codex: empty request" >&2; exit 2; }

# Codex doesn't have a per-tool deny list, and `codex exec` runs hands-off
# so destructive commands the model decides to run inside the workspace
# would not be intercepted. We prepend a tiny PATH shim that rejects
# destructive `git` verbs and `rm`/`sudo`, then exec the real binary for
# everything else.
SHIM_DIR="$SCRIPT_DIR/shims"
if [[ ! -x "$SHIM_DIR/git" || ! -x "$SHIM_DIR/rm" || ! -x "$SHIM_DIR/sudo" ]]; then
  echo "ralph-loop-codex: missing shims in $SHIM_DIR" >&2
  exit 1
fi
export PATH="$SHIM_DIR:$PATH"

LOG_DIR="./.ralph-loop"
mkdir -p "$LOG_DIR"
RUN_TS="$(date +%Y%m%d-%H%M%S)"

trap 'echo; echo "ralph-loop-codex: interrupted"; exit 130' INT

PRE_PROMPT_BODY="$(cat "$PROMPT_FILE")"

for i in $(seq 1 "$ITERATIONS"); do
  echo
  echo "=== Ralph loop iteration $i / $ITERATIONS (codex) ==="
  echo "    pre-prompt: $PROMPT_FILE"
  echo "    cwd:        $PWD"
  echo "    log:        $LOG_DIR/${RUN_TS}-iter-${i}.log"
  echo

  # Codex exec has no system-prompt flag, so we inline the pre-prompt as a
  # <system> block at the top of the user prompt.
  COMPOSED_PROMPT=$(cat <<EOF
<system>
$PRE_PROMPT_BODY
</system>

<task>
$USER_REQUEST
</task>

<iteration>
You are iteration $i of $ITERATIONS in a Ralph loop. Follow the system block's continuity contract: audit the worktree's current state first, then close the single highest-value gap. End with the Iteration summary block.
</iteration>
EOF
)

  codex exec \
    --sandbox workspace-write \
    --skip-git-repo-check \
    -c 'approval_policy="never"' \
    "$COMPOSED_PROMPT" 2>&1 | tee "$LOG_DIR/${RUN_TS}-iter-${i}.log"

  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    echo "ralph-loop-codex: iteration $i exited with code $rc — continuing to next iteration" >&2
  fi
done

echo
echo "=== Ralph loop complete: $ITERATIONS iteration(s) ==="
echo "Logs: $LOG_DIR/${RUN_TS}-iter-*.log"

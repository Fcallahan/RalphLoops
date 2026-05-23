#!/usr/bin/env bash
# ralph-loop-pi — wrap `pi -p` in a Ralph loop.
# Usage: ralph-loop-pi <pre-prompt> <iterations> <request...>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_LOOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF >&2
Usage: ralph-loop-pi <pre-prompt> <iterations> <request...>

  <pre-prompt>   Path to a markdown file, OR the bare name of a prompt
                 in $RALPH_LOOPS_DIR/prompts/ (without .md).
  <iterations>   Positive integer — how many Ralph loop iterations to run.
  <request...>   The task description (everything after iterations is joined).

Example:
  ralph-loop-pi plan-implement 3 "build me a feature that does X"
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
  echo "ralph-loop-pi: pre-prompt not found: $PROMPT_ARG" >&2
  echo "  tried: $PROMPT_ARG" >&2
  echo "  tried: $RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" >&2
  exit 2
fi

if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ralph-loop-pi: iterations must be a positive integer, got: $ITERATIONS" >&2
  exit 2
fi

[[ -n "$USER_REQUEST" ]] || { echo "ralph-loop-pi: empty request" >&2; exit 2; }

# By default, use the user's configured Pi defaults (for example, from
# ~/.pi/agent/settings.json). Users can override these without editing the
# script. Example: RALPH_PI_MODEL=gpt-5.5 RALPH_PI_THINKING=medium
PI_MODEL="${RALPH_PI_MODEL:-}"
PI_THINKING="${RALPH_PI_THINKING:-}"

# Pi does not have a per-command deny list for shell tools. We prepend a tiny
# PATH shim that rejects destructive `git` verbs and `rm`/`sudo`, then execs the
# real binary for everything else.
SHIM_DIR="$SCRIPT_DIR/shims"
if [[ ! -x "$SHIM_DIR/git" || ! -x "$SHIM_DIR/rm" || ! -x "$SHIM_DIR/sudo" ]]; then
  echo "ralph-loop-pi: missing shims in $SHIM_DIR" >&2
  exit 1
fi
export PATH="$SHIM_DIR:$PATH"

LOG_DIR="./.ralph-loop"
mkdir -p "$LOG_DIR"
RUN_TS="$(date +%Y%m%d-%H%M%S)"

trap 'echo; echo "ralph-loop-pi: interrupted"; exit 130' INT

PRE_PROMPT_BODY="$(cat "$PROMPT_FILE")"

for i in $(seq 1 "$ITERATIONS"); do
  echo
  echo "=== Ralph loop iteration $i / $ITERATIONS (pi) ==="
  echo "    pre-prompt: $PROMPT_FILE"
  echo "    cwd:        $PWD"
  echo "    model:      ${PI_MODEL:-pi default}"
  echo "    thinking:   ${PI_THINKING:-pi default}"
  echo "    log:        $LOG_DIR/${RUN_TS}-iter-${i}.log"
  echo

  COMPOSED_PROMPT=$(cat <<EOF
<task>
$USER_REQUEST
</task>

<iteration>
You are iteration $i of $ITERATIONS in a Ralph loop. Follow the appended system prompt's continuity contract: audit the worktree's current state first, then close the single highest-value gap. End with the Iteration summary block.
</iteration>
EOF
)

  PI_ARGS=(-p)
  [[ -n "$PI_MODEL" ]] && PI_ARGS+=(--model "$PI_MODEL")
  [[ -n "$PI_THINKING" ]] && PI_ARGS+=(--thinking "$PI_THINKING")
  PI_ARGS+=(--append-system-prompt "$PRE_PROMPT_BODY")

  pi "${PI_ARGS[@]}" "$COMPOSED_PROMPT" 2>&1 | tee "$LOG_DIR/${RUN_TS}-iter-${i}.log"

  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    echo "ralph-loop-pi: iteration $i exited with code $rc — continuing to next iteration" >&2
  fi
done

echo
echo "=== Ralph loop complete: $ITERATIONS iteration(s) ==="
echo "Logs: $LOG_DIR/${RUN_TS}-iter-*.log"

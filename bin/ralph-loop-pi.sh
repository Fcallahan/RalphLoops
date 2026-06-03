#!/usr/bin/env bash
# ralph-loop-pi — wrap `pi` in a Ralph loop.
# Usage: ralph-loop-pi [--thinking <level>] <pre-prompt> <iterations> (<request...>|--file <path>)
set -uo pipefail

COMMAND_NAME="${RALPH_LOOP_PI_COMMAND_NAME:-$(basename "$0" .sh)}"
PI_MODEL="${RALPH_LOOP_PI_MODEL:-${RALPH_PI_MODEL:-openai-codex/gpt-5.5}}"
DEFAULT_THINKING="${RALPH_LOOP_PI_DEFAULT_THINKING:-${RALPH_PI_THINKING:-medium}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_LOOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF >&2
Usage: $COMMAND_NAME [--thinking <level>] <pre-prompt> <iterations> (<request...>|--file <path>)

  --thinking    pi thinking level: "no thinking", off, minimal, low,
                medium, high, xhigh. Defaults to $DEFAULT_THINKING.
  <pre-prompt>  Path to a markdown file, OR the bare name of a prompt
                in $RALPH_LOOPS_DIR/prompts/ (without .md).
  <iterations>  Positive integer — how many Ralph loop iterations to run.
  <request...>  The task description (everything after iterations is joined).
  --file        Read the task description from a file. Useful for large prompts.

Examples:
  $COMMAND_NAME plan-implement 3 "build me a feature that does X"
  $COMMAND_NAME --thinking high plan-implement 3 --file ./large-task.md
EOF
  exit 2
}

THINKING="$DEFAULT_THINKING"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --thinking)
      [[ $# -ge 2 ]] || { echo "$COMMAND_NAME: --thinking requires a value" >&2; exit 2; }
      THINKING="$2"
      shift 2
      ;;
    --thinking=*)
      THINKING="${1#--thinking=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

case "${THINKING,,}" in
  "no thinking"|no-thinking|none|no|off)
    THINKING="off"
    ;;
  minimal|min)
    THINKING="minimal"
    ;;
  low|medium|high|xhigh)
    THINKING="${THINKING,,}"
    ;;
  *) echo "$COMMAND_NAME: invalid --thinking value: $THINKING" >&2; exit 2 ;;
esac

[[ $# -ge 3 ]] || usage

PROMPT_ARG="$1"; shift
ITERATIONS="$1"; shift

REQUEST_FILE=""
if [[ "${1:-}" == "--file" || "${1:-}" == "--request-file" || "${1:-}" == "-f" ]]; then
  [[ $# -eq 2 ]] || { echo "$COMMAND_NAME: file request usage is: --file <path>" >&2; exit 2; }
  REQUEST_FILE="$2"
  [[ -f "$REQUEST_FILE" ]] || { echo "$COMMAND_NAME: request file not found: $REQUEST_FILE" >&2; exit 2; }
  USER_REQUEST=""
else
  USER_REQUEST="$*"
  [[ -n "$USER_REQUEST" ]] || { echo "$COMMAND_NAME: empty request" >&2; exit 2; }
fi

if [[ -f "$PROMPT_ARG" ]]; then
  PROMPT_FILE="$PROMPT_ARG"
elif [[ -f "$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" ]]; then
  PROMPT_FILE="$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md"
else
  echo "$COMMAND_NAME: pre-prompt not found: $PROMPT_ARG" >&2
  echo "  tried: $PROMPT_ARG" >&2
  echo "  tried: $RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" >&2
  exit 2
fi

if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "$COMMAND_NAME: iterations must be a positive integer, got: $ITERATIONS" >&2
  exit 2
fi

SHIM_DIR="$SCRIPT_DIR/shims"
if [[ ! -x "$SHIM_DIR/git" || ! -x "$SHIM_DIR/rm" || ! -x "$SHIM_DIR/sudo" ]]; then
  echo "$COMMAND_NAME: missing shims in $SHIM_DIR" >&2
  exit 1
fi
export PATH="$SHIM_DIR:$PATH"

LOG_DIR="./.ralph-loop"
mkdir -p "$LOG_DIR"
RUN_TS="$(date +%Y%m%d-%H%M%S)"

trap 'echo; echo "$COMMAND_NAME: interrupted"; exit 130' INT

for i in $(seq 1 "$ITERATIONS"); do
  echo
  echo "=== Ralph loop iteration $i / $ITERATIONS ($COMMAND_NAME) ==="
  echo "    pre-prompt: $PROMPT_FILE"
  echo "    model:      $PI_MODEL"
  echo "    thinking:   $THINKING"
  echo "    cwd:        $PWD"
  echo "    log:        $LOG_DIR/${RUN_TS}-iter-${i}.log"
  echo

  ITERATION_PROMPT=$(cat <<EOF
<iteration>
You are iteration $i of $ITERATIONS in a Ralph loop. Follow the system prompt's continuity contract: audit the worktree's current state first, then close the single highest-value gap. End with the Iteration summary block.
</iteration>
EOF
)

  if [[ -n "$REQUEST_FILE" ]]; then
    pi -p \
      --model "$PI_MODEL" \
      --thinking "$THINKING" \
      --append-system-prompt "$PROMPT_FILE" \
      --no-session \
      "<task>Use the attached file as the task description.</task>" \
      "@$REQUEST_FILE" \
      "$ITERATION_PROMPT" 2>&1 | tee "$LOG_DIR/${RUN_TS}-iter-${i}.log"
  else
    COMPOSED_PROMPT=$(cat <<EOF
<task>
$USER_REQUEST
</task>

$ITERATION_PROMPT
EOF
)

    pi -p \
      --model "$PI_MODEL" \
      --thinking "$THINKING" \
      --append-system-prompt "$PROMPT_FILE" \
      --no-session \
      "$COMPOSED_PROMPT" 2>&1 | tee "$LOG_DIR/${RUN_TS}-iter-${i}.log"
  fi

  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    echo "$COMMAND_NAME: iteration $i exited with code $rc — continuing to next iteration" >&2
  fi
done

echo
echo "=== Ralph loop complete: $ITERATIONS iteration(s) ==="
echo "Logs: $LOG_DIR/${RUN_TS}-iter-*.log"

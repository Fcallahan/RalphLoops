#!/usr/bin/env bash
# ralph-loop-auto — wrap `pi` in a Ralph loop with direct Claude CLI fallback.
# Usage: ralph-loop-auto [--thinking <level>] <pre-prompt> <iterations> (<request...>|--file <path>)
set -uo pipefail

COMMAND_NAME="ralph-loop-auto"
PI_MODEL="${RALPH_AUTO_PI_MODEL:-${RALPH_LOOP_PI_MODEL:-${RALPH_PI_MODEL:-openai-codex/gpt-5.5}}}"
DEFAULT_THINKING="${RALPH_AUTO_PI_THINKING:-${RALPH_LOOP_PI_DEFAULT_THINKING:-${RALPH_PI_THINKING:-medium}}}"
CLAUDE_MODEL="${RALPH_AUTO_CLAUDE_MODEL:-opus}"
CLAUDE_EFFORT="${RALPH_AUTO_CLAUDE_EFFORT:-medium}"
CLAUDE_PERMISSION_MODE="${RALPH_AUTO_CLAUDE_PERMISSION_MODE:-bypassPermissions}"
CODEX_LIMIT_REGEX="${RALPH_AUTO_CODEX_LIMIT_REGEX:-exceed(ed|s)?.*(5[ -]?hour|five[ -]?hour).*limit|(5[ -]?hour|five[ -]?hour).*limit.*exceed(ed|s)?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_LOOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF >&2
Usage: $COMMAND_NAME [--thinking <level>] <pre-prompt> <iterations> (<request...>|--file <path>)

  Runs Pi/GPT by default. If a Codex 5-hour-limit message is detected in an
  iteration log, reruns that same iteration directly with Claude CLI and uses
  Claude for the remaining iterations in this run.

  --thinking    pi thinking level: "no thinking", off, minimal, low,
                medium, high, xhigh. Defaults to $DEFAULT_THINKING.
  <pre-prompt>  Path to a markdown file, OR the bare name of a prompt
                in $RALPH_LOOPS_DIR/prompts/ (without .md).
  <iterations>  Positive integer — how many Ralph loop iterations to run.
  <request...>  The task description (everything after iterations is joined).
  --file        Read the task description from a file. Useful for large prompts.

Env overrides:
  RALPH_AUTO_PI_MODEL=$PI_MODEL
  RALPH_AUTO_PI_THINKING=$DEFAULT_THINKING
  RALPH_AUTO_CLAUDE_MODEL=$CLAUDE_MODEL
  RALPH_AUTO_CLAUDE_EFFORT=$CLAUDE_EFFORT
  RALPH_AUTO_CODEX_LIMIT_REGEX=<extended grep regex>

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

# Tools to deny — destructive verbs only. Reads, edits, builds, tests stay open.
DENY_TOOLS='Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git rebase:*),Bash(git checkout:*),Bash(git branch:*),Bash(git clean:*),Bash(git tag:*),Bash(rm:*),Bash(sudo:*)'

LOG_DIR="./.ralph-loop"
mkdir -p "$LOG_DIR"
RUN_TS="$(date +%Y%m%d-%H%M%S)"
ACTIVE_PROVIDER="pi"

trap 'echo; echo "$COMMAND_NAME: interrupted"; exit 130' INT

codex_limit_detected() {
  local log="$1"
  [[ -f "$log" ]] && grep -Eiq "$CODEX_LIMIT_REGEX" "$log"
}

build_iteration_prompt() {
  local i="$1"
  cat <<EOF
<iteration>
You are iteration $i of $ITERATIONS in a Ralph loop. Follow the system prompt's continuity contract: audit the worktree's current state first, then close the single highest-value gap. End with the Iteration summary block.
Prior logs for this run are available under $LOG_DIR/${RUN_TS}-iter-*.log. Inspect them if helpful, but trust the current worktree state first.
</iteration>
EOF
}

build_claude_prompt() {
  local iteration_prompt="$1"
  if [[ -n "$REQUEST_FILE" ]]; then
    cat <<EOF
<task>
$(cat "$REQUEST_FILE")
</task>

$iteration_prompt
EOF
  else
    cat <<EOF
<task>
$USER_REQUEST
</task>

$iteration_prompt
EOF
  fi
}

run_pi_iteration() {
  local i="$1" iteration_prompt="$2" log="$3"

  if [[ -n "$REQUEST_FILE" ]]; then
    pi -p \
      --model "$PI_MODEL" \
      --thinking "$THINKING" \
      --append-system-prompt "$PROMPT_FILE" \
      --no-session \
      "<task>Use the attached file as the task description.</task>" \
      "@$REQUEST_FILE" \
      "$iteration_prompt" 2>&1 | tee "$log"
  else
    local composed_prompt
    composed_prompt=$(cat <<EOF
<task>
$USER_REQUEST
</task>

$iteration_prompt
EOF
)

    pi -p \
      --model "$PI_MODEL" \
      --thinking "$THINKING" \
      --append-system-prompt "$PROMPT_FILE" \
      --no-session \
      "$composed_prompt" 2>&1 | tee "$log"
  fi

  return "${PIPESTATUS[0]}"
}

run_claude_iteration() {
  local prompt="$1" log="$2"

  claude -p \
    --model "$CLAUDE_MODEL" \
    --effort "$CLAUDE_EFFORT" \
    --permission-mode "$CLAUDE_PERMISSION_MODE" \
    --system-prompt-file "$PROMPT_FILE" \
    --disallowedTools "$DENY_TOOLS" \
    -- "$prompt" 2>&1 | tee "$log"

  return "${PIPESTATUS[0]}"
}

for i in $(seq 1 "$ITERATIONS"); do
  ITERATION_PROMPT="$(build_iteration_prompt "$i")"
  CLAUDE_PROMPT="$(build_claude_prompt "$ITERATION_PROMPT")"

  echo
  echo "=== Ralph loop iteration $i / $ITERATIONS ($COMMAND_NAME) ==="
  echo "    pre-prompt: $PROMPT_FILE"
  echo "    active:     $ACTIVE_PROVIDER"
  echo "    pi model:   $PI_MODEL"
  echo "    thinking:   $THINKING"
  echo "    fallback:   claude $CLAUDE_MODEL / $CLAUDE_EFFORT"
  echo "    cwd:        $PWD"

  if [[ "$ACTIVE_PROVIDER" == "pi" ]]; then
    PI_LOG="$LOG_DIR/${RUN_TS}-iter-${i}.log"
    echo "    log:        $PI_LOG"
    echo

    run_pi_iteration "$i" "$ITERATION_PROMPT" "$PI_LOG"
    rc=$?

    if codex_limit_detected "$PI_LOG"; then
      ACTIVE_PROVIDER="claude"
      CLAUDE_LOG="$LOG_DIR/${RUN_TS}-iter-${i}-claude-fallback.log"
      echo
      echo "$COMMAND_NAME: Codex 5-hour limit detected in $PI_LOG"
      echo "$COMMAND_NAME: rerunning iteration $i directly with Claude CLI"
      echo "    log:        $CLAUDE_LOG"
      echo

      run_claude_iteration "$CLAUDE_PROMPT" "$CLAUDE_LOG"
      claude_rc=$?
      if [[ $claude_rc -ne 0 ]]; then
        echo "$COMMAND_NAME: Claude fallback for iteration $i exited with code $claude_rc — continuing to next iteration" >&2
      fi
    elif [[ $rc -ne 0 ]]; then
      echo "$COMMAND_NAME: Pi iteration $i exited with code $rc — continuing to next iteration" >&2
    fi
  else
    CLAUDE_LOG="$LOG_DIR/${RUN_TS}-iter-${i}-claude.log"
    echo "    log:        $CLAUDE_LOG"
    echo

    run_claude_iteration "$CLAUDE_PROMPT" "$CLAUDE_LOG"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "$COMMAND_NAME: Claude iteration $i exited with code $rc — continuing to next iteration" >&2
    fi
  fi
done

echo
echo "=== Ralph loop complete: $ITERATIONS iteration(s) ==="
echo "Logs: $LOG_DIR/${RUN_TS}-iter-*.log"

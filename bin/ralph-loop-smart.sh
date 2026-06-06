#!/usr/bin/env bash
# ralph-loop-smart — multi-model Ralph loop:
# Opus plans, Pi/GPT-5.3-Codex-Spark no-thinking scouts, Pi/GPT-5.5 medium writes/reviews.
# Usage: ralph-loop-smart [--scout-model <model>] [--scout-thinking <level>] <pre-prompt> <iterations> <request...>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_LOOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF >&2
Usage: ralph-loop-smart [options] <pre-prompt> <iterations> <request...>

Options:
  --scout-model <model>       Pi model for read-only scouts.
  --scout-thinking <level>    Pi thinking level for scouts: "no thinking", off,
                              minimal, low, medium, high, xhigh.

  <pre-prompt>   Path to a markdown file, OR the bare name of a prompt
                 in $RALPH_LOOPS_DIR/prompts/ (without .md).
  <iterations>   Positive integer — how many Smart Ralph loop iterations to run.
  <request...>   The task description (everything after iterations is joined).

Env overrides:
  RALPH_SMART_PLAN_MODEL=opus
  RALPH_SMART_PLAN_EFFORT=high
  RALPH_SMART_SCOUT_MODEL=openai-codex/gpt-5.3-codex-spark
  RALPH_SMART_SCOUT_THINKING=off
  RALPH_SMART_SCOUT_COUNT=2
  RALPH_SMART_WORKER_MODEL=openai-codex/gpt-5.5
  RALPH_SMART_WORKER_THINKING=medium
  RALPH_SMART_REVIEW_MODEL=openai-codex/gpt-5.5
  RALPH_SMART_REVIEW_THINKING=medium
  RALPH_SMART_SKIP_REVIEW=0|1
  RALPH_SMART_SKIP_FIX=0|1

Example:
  ralph-loop-smart --scout-thinking off plan-implement 2 "build me a feature that does X"
EOF
  exit 2
}

SCOUT_MODEL="${RALPH_SMART_SCOUT_MODEL:-openai-codex/gpt-5.3-codex-spark}"
SCOUT_THINKING="${RALPH_SMART_SCOUT_THINKING:-off}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scout-model)
      [[ $# -ge 2 ]] || { echo "ralph-loop-smart: --scout-model requires a value" >&2; exit 2; }
      SCOUT_MODEL="$2"
      shift 2
      ;;
    --scout-model=*)
      SCOUT_MODEL="${1#--scout-model=}"
      shift
      ;;
    --scout-thinking)
      [[ $# -ge 2 ]] || { echo "ralph-loop-smart: --scout-thinking requires a value" >&2; exit 2; }
      SCOUT_THINKING="$2"
      shift 2
      ;;
    --scout-thinking=*)
      SCOUT_THINKING="${1#--scout-thinking=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    --)
      shift
      break
      ;;
    --*)
      echo "ralph-loop-smart: unknown option: $1" >&2
      usage
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 3 ]] || usage

PROMPT_ARG="$1"; shift
ITERATIONS="$1"; shift
USER_REQUEST="$*"

if [[ -f "$PROMPT_ARG" ]]; then
  PROMPT_FILE="$PROMPT_ARG"
elif [[ -f "$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" ]]; then
  PROMPT_FILE="$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md"
else
  echo "ralph-loop-smart: pre-prompt not found: $PROMPT_ARG" >&2
  echo "  tried: $PROMPT_ARG" >&2
  echo "  tried: $RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" >&2
  exit 2
fi

if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ralph-loop-smart: iterations must be a positive integer, got: $ITERATIONS" >&2
  exit 2
fi

[[ -n "$USER_REQUEST" ]] || { echo "ralph-loop-smart: empty request" >&2; exit 2; }

PLAN_MODEL="${RALPH_SMART_PLAN_MODEL:-opus}"
PLAN_EFFORT="${RALPH_SMART_PLAN_EFFORT:-high}"
SCOUT_COUNT="${RALPH_SMART_SCOUT_COUNT:-2}"
WORKER_MODEL="${RALPH_SMART_WORKER_MODEL:-openai-codex/gpt-5.5}"
WORKER_THINKING="${RALPH_SMART_WORKER_THINKING:-medium}"
REVIEW_MODEL="${RALPH_SMART_REVIEW_MODEL:-openai-codex/gpt-5.5}"
REVIEW_THINKING="${RALPH_SMART_REVIEW_THINKING:-medium}"
SKIP_REVIEW="${RALPH_SMART_SKIP_REVIEW:-0}"
SKIP_FIX="${RALPH_SMART_SKIP_FIX:-0}"

case "${SCOUT_THINKING,,}" in
  "no thinking"|no-thinking|none|no|off)
    SCOUT_THINKING="off"
    ;;
  minimal|min)
    SCOUT_THINKING="minimal"
    ;;
  low|medium|high|xhigh)
    SCOUT_THINKING="${SCOUT_THINKING,,}"
    ;;
  *) echo "ralph-loop-smart: invalid scout thinking value: $SCOUT_THINKING" >&2; exit 2 ;;
esac

if ! [[ "$SCOUT_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ralph-loop-smart: RALPH_SMART_SCOUT_COUNT must be a positive integer, got: $SCOUT_COUNT" >&2
  exit 2
fi

SHIM_DIR="$SCRIPT_DIR/shims"
if [[ ! -x "$SHIM_DIR/git" || ! -x "$SHIM_DIR/rm" || ! -x "$SHIM_DIR/sudo" ]]; then
  echo "ralph-loop-smart: missing shims in $SHIM_DIR" >&2
  exit 1
fi
export PATH="$SHIM_DIR:$PATH"

LOG_DIR="./.ralph-loop"
RUN_TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$LOG_DIR/smart-$RUN_TS"
mkdir -p "$RUN_DIR"

trap 'echo; echo "ralph-loop-smart: interrupted"; exit 130' INT

PRE_PROMPT_BODY="$(cat "$PROMPT_FILE")"

worktree_fingerprint() {
  # Ignore Ralph's own run artifacts and submodule working-tree dirtiness.
  # Read-only phases write plan/scout/review logs under .ralph-loop, and
  # read/build commands can leave a submodule marked "-dirty" without changing
  # the parent repo's tracked content. Still detect real tracked/index changes,
  # including submodule commit pointer changes.
  {
    git diff --binary --ignore-submodules=dirty -- . ':(exclude).ralph-loop/**' 2>/dev/null || true
    git diff --cached --binary --ignore-submodules=dirty -- . ':(exclude).ralph-loop/**' 2>/dev/null || true
  } | sha256sum | awk '{print $1}'
}

run_readonly_claude() {
  local model="$1" effort="$2" prompt="$3" output="$4" log="$5"
  local before after rc
  before="$(worktree_fingerprint)"

  claude -p \
    --model "$model" \
    --effort "$effort" \
    --permission-mode bypassPermissions \
    --disallowedTools 'Edit,Write,MultiEdit,NotebookEdit,Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git rebase:*),Bash(git checkout:*),Bash(git branch:*),Bash(git clean:*),Bash(git tag:*),Bash(rm:*),Bash(sudo:*)' \
    -- "$prompt" 2>&1 | tee "$log" > "$output"
  rc=${PIPESTATUS[0]}

  after="$(worktree_fingerprint)"
  if [[ "$before" != "$after" ]]; then
    echo "ralph-loop-smart: WARNING: read-only Claude phase changed the worktree; inspect $log" >&2
  fi

  return "$rc"
}

run_readonly_pi() {
  local model="$1" thinking="$2" prompt="$3" output="$4" log="$5"
  local before after rc
  before="$(worktree_fingerprint)"

  PI_ARGS=(-p --no-session --tools read,bash,grep,find,ls --thinking "$thinking")
  [[ -n "$model" ]] && PI_ARGS+=(--model "$model")
  pi "${PI_ARGS[@]}" "$prompt" 2>&1 | tee "$log" > "$output"
  rc=${PIPESTATUS[0]}

  after="$(worktree_fingerprint)"
  if [[ "$before" != "$after" ]]; then
    echo "ralph-loop-smart: WARNING: read-only Pi phase changed the worktree; inspect $log" >&2
  fi

  return "$rc"
}

run_writer_pi() {
  local model="$1" thinking="$2" prompt="$3" output="$4" log="$5"
  PI_ARGS=(-p --no-session --thinking "$thinking")
  [[ -n "$model" ]] && PI_ARGS+=(--model "$model")
  pi "${PI_ARGS[@]}" "$prompt" 2>&1 | tee "$log" > "$output"
  return "${PIPESTATUS[0]}"
}

is_fatal_provider_error() {
  local log="$1"
  grep -Eqi '402 Insufficient credits|exceeded your current quota|No API key found|invalid_api_key|authentication|unauthorized|model.*not.*found|provider.*not.*found' "$log"
}

stop_on_fatal_provider_error() {
  local phase="$1" log="$2"
  if is_fatal_provider_error "$log"; then
    echo "ralph-loop-smart: fatal provider error during $phase; stopping loop" >&2
    echo "ralph-loop-smart: inspect $log" >&2
    exit 1
  fi
}

scout_focus() {
  local scout_i="$1"
  case "$scout_i" in
    1)
      cat <<'EOF'
Scout focus: file map and implementation surface.
- Find the most relevant files, existing patterns, and likely edit points.
- Prefer concrete paths and short reasons over broad commentary.
- Do not spend time on test strategy unless it identifies a missing edit surface.
EOF
      ;;
    2)
      cat <<'EOF'
Scout focus: validation, risk, and edge cases.
- Find relevant tests, commands, user flows, migrations/data risks, and likely regressions.
- Prefer concrete validation gates and failure modes over implementation advice.
- Do not duplicate the file-map scout unless a path is important to validation.
EOF
      ;;
    *)
      cat <<'EOF'
Scout focus: independent gap check.
- Look for anything important the planner or earlier scouts may have missed.
- Prefer contradictions, missing files, hidden coupling, and validation holes.
- Avoid repeating already-obvious findings.
EOF
      ;;
  esac
}

echo "ralph-loop-smart: Pi preflight: $WORKER_MODEL / $WORKER_THINKING"
PREFLIGHT_LOG="$RUN_DIR/pi-preflight.log"
if ! pi -p --no-session --no-tools --model "$WORKER_MODEL" --thinking "$WORKER_THINKING" 'Reply with exactly OK' >"$PREFLIGHT_LOG" 2>&1; then
  echo "ralph-loop-smart: Pi preflight failed; inspect $PREFLIGHT_LOG" >&2
  cat "$PREFLIGHT_LOG" >&2
  exit 1
fi
if ! grep -q 'OK' "$PREFLIGHT_LOG"; then
  echo "ralph-loop-smart: Pi preflight returned unexpected output; inspect $PREFLIGHT_LOG" >&2
  cat "$PREFLIGHT_LOG" >&2
  exit 1
fi

for i in $(seq 1 "$ITERATIONS"); do
  ITER_DIR="$RUN_DIR/iter-$i"
  mkdir -p "$ITER_DIR"

  echo
  echo "=== Smart Ralph loop iteration $i / $ITERATIONS ==="
  echo "    pre-prompt: $PROMPT_FILE"
  echo "    cwd:        $PWD"
  echo "    planner:    claude $PLAN_MODEL / $PLAN_EFFORT"
  echo "    scouts:     pi $SCOUT_MODEL / $SCOUT_THINKING x$SCOUT_COUNT"
  echo "    worker:     pi $WORKER_MODEL / $WORKER_THINKING"
  echo "    reviewer:   pi $REVIEW_MODEL / $REVIEW_THINKING"
  echo "    artifacts:  $ITER_DIR"
  echo

  PLAN_PROMPT=$(cat <<EOF
<system>
$PRE_PROMPT_BODY
</system>

<role>
You are the heavy planner for a Smart Ralph loop. You are read-only. Do not edit files.
Your job is to inspect the current worktree, account for prior iterations, and produce a concise implementation plan for the single highest-value next gap.
</role>

<task>
$USER_REQUEST
</task>

<iteration>
Iteration $i of $ITERATIONS. Audit current state first. Then write $ITER_DIR/plan.md content in your final answer.
</iteration>

Output format:
# Smart Ralph plan — iteration $i
## Current state
- Already done:
- Partially done / broken:
- Not started:
## Highest-value gap
- ...
## Worker instructions
- 3-8 concrete instructions for the writer.
## Validation contract
- Commands/checks/user flows the worker should run.
## Non-goals / guardrails
- ...
EOF
)

  echo "--- planner (read-only) ---"
  run_readonly_claude "$PLAN_MODEL" "$PLAN_EFFORT" "$PLAN_PROMPT" "$ITER_DIR/plan.md" "$ITER_DIR/planner.log"
  rc=$?
  [[ $rc -ne 0 ]] && echo "ralph-loop-smart: planner exited $rc — continuing with captured output" >&2

  : > "$ITER_DIR/scout-findings.md"
  for scout_i in $(seq 1 "$SCOUT_COUNT"); do
    SCOUT_FOCUS="$(scout_focus "$scout_i")"
    SCOUT_PROMPT=$(cat <<EOF
You are Pi scout $scout_i of $SCOUT_COUNT for a Smart Ralph loop. You are read-only: inspect files, search, and review current state, but do not edit files.

$SCOUT_FOCUS

Original user task:
$USER_REQUEST

Pre-prompt / continuity contract:
$PRE_PROMPT_BODY

Planner output:
$(cat "$ITER_DIR/plan.md")

Focus on concrete file-level findings that help the final writer. Include paths, likely edits, risks, and validation ideas. Do not implement anything.
EOF
)

    echo "--- pi scout $scout_i (read-only) ---"
    run_readonly_pi "$SCOUT_MODEL" "$SCOUT_THINKING" "$SCOUT_PROMPT" "$ITER_DIR/scout-$scout_i.md" "$ITER_DIR/scout-$scout_i.log"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "ralph-loop-smart: scout $scout_i exited $rc — continuing with captured output" >&2
      stop_on_fatal_provider_error "scout $scout_i" "$ITER_DIR/scout-$scout_i.log"
    fi
    {
      echo "# Scout $scout_i"
      cat "$ITER_DIR/scout-$scout_i.md"
      echo
    } >> "$ITER_DIR/scout-findings.md"
  done

  REVIEW_FINDINGS_PROMPT=$(cat <<EOF
<role>
You are the heavy analysis reviewer. You are read-only. Review the Pi scout findings against the task and planner output, then produce a precise implementation contract for the Pi writer.
</role>

<task>
$USER_REQUEST
</task>

<plan>
$(cat "$ITER_DIR/plan.md")
</plan>

<pi-scout-findings>
$(cat "$ITER_DIR/scout-findings.md")
</pi-scout-findings>

Return only:
# Smart Ralph implementation contract — iteration $i
## Approved highest-value gap
## File-level instructions
## Risks / guardrails
## Validation contract
EOF
)

  echo "--- gpt review of pi findings (read-only) ---"
  run_readonly_pi "$REVIEW_MODEL" "$REVIEW_THINKING" "$REVIEW_FINDINGS_PROMPT" "$ITER_DIR/implementation-contract.md" "$ITER_DIR/findings-reviewer.log"
  rc=$?
  [[ $rc -ne 0 ]] && echo "ralph-loop-smart: findings reviewer exited $rc — writer will still receive captured output" >&2

  WORKER_PROMPT=$(cat <<EOF
You are the sole writer for Smart Ralph loop iteration $i.

Implement only the approved highest-value gap from the implementation contract. Audit current state before editing. Do not commit, push, reset, rebase, checkout, clean, rm -rf, or sudo. Keep scope tight. Run focused validation where practical. End with an Iteration summary block.

Original task:
$USER_REQUEST

Pre-prompt / continuity contract:
$PRE_PROMPT_BODY

Implementation contract:
$(cat "$ITER_DIR/implementation-contract.md")
EOF
)
  printf '%s\n' "$WORKER_PROMPT" > "$ITER_DIR/worker-prompt.md"

  echo "--- pi worker (sole writer) ---"
  run_writer_pi "$WORKER_MODEL" "$WORKER_THINKING" "$WORKER_PROMPT" "$ITER_DIR/worker-summary.md" "$ITER_DIR/worker.log"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "ralph-loop-smart: worker exited $rc" >&2
    stop_on_fatal_provider_error "worker" "$ITER_DIR/worker.log"
    echo "ralph-loop-smart: non-fatal worker failure — skipping review/fix for this iteration" >&2
    continue
  fi

  if [[ "$SKIP_REVIEW" == "1" ]]; then
    echo "--- review skipped (RALPH_SMART_SKIP_REVIEW=1) ---"
    continue
  fi

  REVIEW_PROMPT_FILE="$ITER_DIR/review-prompt.md"
  {
    printf '%s\n' '<role>'
    printf '%s\n' 'You are the reviewer for a Smart Ralph loop. You are read-only. Do not edit files.'
    printf '%s\n' 'Review the current git diff against the original task, planner output, and worker summary.'
    printf '%s\n' '</role>'
    printf '\n%s\n' '<task>'
    printf '%s\n' "$USER_REQUEST"
    printf '%s\n' '</task>'
    printf '\n%s\n' '<plan>'
    cat "$ITER_DIR/plan.md"
    printf '%s\n' '</plan>'
    printf '\n%s\n' '<worker-summary>'
    cat "$ITER_DIR/worker-summary.md" 2>/dev/null || true
    printf '%s\n' '</worker-summary>'
    printf '%s\n' ''
    printf '%s\n' 'Return:'
    printf '%s\n' "# Smart Ralph review — iteration $i"
    printf '%s\n' '## Blockers'
    printf '%s\n' '- ... or none'
    printf '%s\n' '## Fixes worth doing now'
    printf '%s\n' '- ... or none'
    printf '%s\n' '## Optional/deferred'
    printf '%s\n' '- ... or none'
    printf '%s\n' '## Validation notes'
    printf '%s\n' '- ...'
  } > "$REVIEW_PROMPT_FILE"
  REVIEW_PROMPT="$(< "$REVIEW_PROMPT_FILE")"

  echo "--- reviewer (read-only) ---"
  run_readonly_pi "$REVIEW_MODEL" "$REVIEW_THINKING" "$REVIEW_PROMPT" "$ITER_DIR/review.md" "$ITER_DIR/reviewer.log"
  rc=$?
  [[ $rc -ne 0 ]] && echo "ralph-loop-smart: reviewer exited $rc — continuing with captured output" >&2

  if [[ "$SKIP_FIX" == "1" ]]; then
    echo "--- fix pass skipped (RALPH_SMART_SKIP_FIX=1) ---"
    continue
  fi

  FIX_PROMPT_FILE="$ITER_DIR/fix-prompt.md"
  {
    printf '%s\n' "You are the sole fix worker for Smart Ralph loop iteration $i."
    printf '%s\n' ''
    printf '%s\n' 'Apply only blockers and fixes worth doing now from the review below. Do not expand scope. If the review says there are no blockers/fixes worth doing now, inspect briefly and make no edits.'
    printf '%s\n' ''
    printf '%s\n' 'Original task:'
    printf '%s\n' "$USER_REQUEST"
    printf '%s\n' ''
    printf '%s\n' 'Plan:'
    cat "$ITER_DIR/plan.md"
    printf '%s\n' ''
    printf '%s\n' 'Review:'
    cat "$ITER_DIR/review.md"
    printf '%s\n' ''
    printf '%s\n' 'Rules:'
    printf '%s\n' '- Do not commit, push, reset, rebase, checkout, clean, rm -rf, or sudo.'
    printf '%s\n' '- Keep edits minimal.'
    printf '%s\n' '- Run focused validation if you changed files.'
    printf '%s\n' '- End with an Iteration summary block.'
  } > "$FIX_PROMPT_FILE"
  FIX_PROMPT="$(< "$FIX_PROMPT_FILE")"

  echo "--- pi fix worker (sole writer) ---"
  run_writer_pi "$WORKER_MODEL" "$WORKER_THINKING" "$FIX_PROMPT" "$ITER_DIR/fix-summary.md" "$ITER_DIR/fix.log"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "ralph-loop-smart: fix worker exited $rc" >&2
    stop_on_fatal_provider_error "fix worker" "$ITER_DIR/fix.log"
    echo "ralph-loop-smart: non-fatal fix worker failure — continuing to next iteration" >&2
  fi
done

echo
echo "=== Smart Ralph loop complete: $ITERATIONS iteration(s) ==="
echo "Artifacts: $RUN_DIR"

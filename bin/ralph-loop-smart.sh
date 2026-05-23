#!/usr/bin/env bash
# ralph-loop-smart — multi-model Ralph loop:
# Opus plans, Pi/GPT-5.5 orchestrates, Codex/GPT-5 low writes, Opus reviews.
# Usage: ralph-loop-smart <pre-prompt> <iterations> <request...>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_LOOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF >&2
Usage: ralph-loop-smart <pre-prompt> <iterations> <request...>

  <pre-prompt>   Path to a markdown file, OR the bare name of a prompt
                 in $RALPH_LOOPS_DIR/prompts/ (without .md).
  <iterations>   Positive integer — how many Smart Ralph loop iterations to run.
  <request...>   The task description (everything after iterations is joined).

Env overrides:
  RALPH_SMART_PLAN_MODEL=opus
  RALPH_SMART_PLAN_EFFORT=high
  RALPH_SMART_ORCH_MODEL=openai/gpt-5.5
  RALPH_SMART_ORCH_THINKING=medium
  RALPH_SMART_WORKER_MODEL=gpt-5
  RALPH_SMART_WORKER_EFFORT=low
  RALPH_SMART_REVIEW_MODEL=opus
  RALPH_SMART_REVIEW_EFFORT=medium
  RALPH_SMART_SKIP_REVIEW=0|1
  RALPH_SMART_SKIP_FIX=0|1

Example:
  ralph-loop-smart plan-implement 2 "build me a feature that does X"
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
ORCH_MODEL="${RALPH_SMART_ORCH_MODEL:-openai/gpt-5.5}"
ORCH_THINKING="${RALPH_SMART_ORCH_THINKING:-medium}"
WORKER_MODEL="${RALPH_SMART_WORKER_MODEL:-gpt-5}"
WORKER_EFFORT="${RALPH_SMART_WORKER_EFFORT:-low}"
REVIEW_MODEL="${RALPH_SMART_REVIEW_MODEL:-opus}"
REVIEW_EFFORT="${RALPH_SMART_REVIEW_EFFORT:-medium}"
SKIP_REVIEW="${RALPH_SMART_SKIP_REVIEW:-0}"
SKIP_FIX="${RALPH_SMART_SKIP_FIX:-0}"

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
  {
    git diff --binary 2>/dev/null || true
    git diff --cached --binary 2>/dev/null || true
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

for i in $(seq 1 "$ITERATIONS"); do
  ITER_DIR="$RUN_DIR/iter-$i"
  mkdir -p "$ITER_DIR"

  echo
  echo "=== Smart Ralph loop iteration $i / $ITERATIONS ==="
  echo "    pre-prompt: $PROMPT_FILE"
  echo "    cwd:        $PWD"
  echo "    planner:    claude $PLAN_MODEL / $PLAN_EFFORT"
  echo "    orch:       pi ${ORCH_MODEL:-pi default} / $ORCH_THINKING"
  echo "    worker:     codex $WORKER_MODEL / $WORKER_EFFORT"
  echo "    reviewer:   claude $REVIEW_MODEL / $REVIEW_EFFORT"
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

  ORCH_PROMPT=$(cat <<EOF
You are the orchestrator for a Smart Ralph loop. Convert the Opus plan into a precise prompt for a lower-cost coding worker.

Hard constraints for the worker:
- The worker is the only writer in this iteration.
- The worker must audit current state before editing.
- The worker must implement only the approved highest-value gap.
- The worker must not commit, push, reset, rebase, checkout, clean, rm -rf, or sudo.
- The worker must run focused validation where practical.
- The worker must end with an Iteration summary block.

Original user task:
$USER_REQUEST

Pre-prompt / continuity contract:
$PRE_PROMPT_BODY

Planner output:
$(cat "$ITER_DIR/plan.md")

Return only the final worker prompt. Do not include commentary outside the prompt.
EOF
)

  echo "--- orchestrator (prompt synthesis) ---"
  PI_ARGS=(-p --no-tools --thinking "$ORCH_THINKING")
  [[ -n "$ORCH_MODEL" ]] && PI_ARGS+=(--model "$ORCH_MODEL")
  pi "${PI_ARGS[@]}" "$ORCH_PROMPT" 2>&1 | tee "$ITER_DIR/orchestrator.log" > "$ITER_DIR/worker-prompt.md"
  rc=${PIPESTATUS[0]}
  [[ $rc -ne 0 ]] && echo "ralph-loop-smart: orchestrator exited $rc — worker will still receive captured output" >&2

  echo "--- worker (sole writer) ---"
  codex exec \
    --model "$WORKER_MODEL" \
    --sandbox workspace-write \
    --skip-git-repo-check \
    -c 'approval_policy="never"' \
    -c "model_reasoning_effort=\"$WORKER_EFFORT\"" \
    --output-last-message "$ITER_DIR/worker-summary.md" \
    "$(cat "$ITER_DIR/worker-prompt.md")" 2>&1 | tee "$ITER_DIR/worker.log"
  rc=${PIPESTATUS[0]}
  [[ $rc -ne 0 ]] && echo "ralph-loop-smart: worker exited $rc — continuing to review/fix if enabled" >&2

  if [[ "$SKIP_REVIEW" == "1" ]]; then
    echo "--- review skipped (RALPH_SMART_SKIP_REVIEW=1) ---"
    continue
  fi

  REVIEW_PROMPT=$(cat <<EOF
<role>
You are the reviewer for a Smart Ralph loop. You are read-only. Do not edit files.
Review the current git diff against the original task, planner output, and worker summary.
</role>

<task>
$USER_REQUEST
</task>

<plan>
$(cat "$ITER_DIR/plan.md")
</plan>

<worker-summary>
$(cat "$ITER_DIR/worker-summary.md" 2>/dev/null || true)
</worker-summary>

Return:
# Smart Ralph review — iteration $i
## Blockers
- ... or none
## Fixes worth doing now
- ... or none
## Optional/deferred
- ... or none
## Validation notes
- ...
EOF
)

  echo "--- reviewer (read-only) ---"
  run_readonly_claude "$REVIEW_MODEL" "$REVIEW_EFFORT" "$REVIEW_PROMPT" "$ITER_DIR/review.md" "$ITER_DIR/reviewer.log"
  rc=$?
  [[ $rc -ne 0 ]] && echo "ralph-loop-smart: reviewer exited $rc — continuing with captured output" >&2

  if [[ "$SKIP_FIX" == "1" ]]; then
    echo "--- fix pass skipped (RALPH_SMART_SKIP_FIX=1) ---"
    continue
  fi

  FIX_PROMPT=$(cat <<EOF
You are the sole fix worker for Smart Ralph loop iteration $i.

Apply only blockers and fixes worth doing now from the review below. Do not expand scope. If the review says there are no blockers/fixes worth doing now, inspect briefly and make no edits.

Original task:
$USER_REQUEST

Plan:
$(cat "$ITER_DIR/plan.md")

Review:
$(cat "$ITER_DIR/review.md")

Rules:
- Do not commit, push, reset, rebase, checkout, clean, rm -rf, or sudo.
- Keep edits minimal.
- Run focused validation if you changed files.
- End with an Iteration summary block.
EOF
)

  echo "--- fix worker (sole writer) ---"
  codex exec \
    --model "$WORKER_MODEL" \
    --sandbox workspace-write \
    --skip-git-repo-check \
    -c 'approval_policy="never"' \
    -c "model_reasoning_effort=\"$WORKER_EFFORT\"" \
    --output-last-message "$ITER_DIR/fix-summary.md" \
    "$FIX_PROMPT" 2>&1 | tee "$ITER_DIR/fix.log"
  rc=${PIPESTATUS[0]}
  [[ $rc -ne 0 ]] && echo "ralph-loop-smart: fix worker exited $rc — continuing to next iteration" >&2
done

echo
echo "=== Smart Ralph loop complete: $ITERATIONS iteration(s) ==="
echo "Artifacts: $RUN_DIR"

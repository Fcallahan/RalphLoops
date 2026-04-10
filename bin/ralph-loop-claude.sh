#!/usr/bin/env bash
# ralph-loop-claude — wrap `claude` in a Ralph loop.
# Usage: ralph-loop-claude <pre-prompt> <iterations> <request...>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_LOOPS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF >&2
Usage: ralph-loop-claude <pre-prompt> <iterations> <request...>

  <pre-prompt>   Path to a markdown file, OR the bare name of a prompt
                 in $RALPH_LOOPS_DIR/prompts/ (without .md).
  <iterations>   Positive integer — how many Ralph loop iterations to run.
  <request...>   The task description (everything after iterations is joined).

Example:
  ralph-loop-claude plan-implement 3 "build me a feature that does X"
EOF
  exit 2
}

[[ $# -ge 3 ]] || usage

PROMPT_ARG="$1"; shift
ITERATIONS="$1"; shift
USER_REQUEST="$*"

# Resolve pre-prompt: try as a path, then as a name in prompts/.
if [[ -f "$PROMPT_ARG" ]]; then
  PROMPT_FILE="$PROMPT_ARG"
elif [[ -f "$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" ]]; then
  PROMPT_FILE="$RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md"
else
  echo "ralph-loop-claude: pre-prompt not found: $PROMPT_ARG" >&2
  echo "  tried: $PROMPT_ARG" >&2
  echo "  tried: $RALPH_LOOPS_DIR/prompts/${PROMPT_ARG}.md" >&2
  exit 2
fi

# Validate iterations.
if ! [[ "$ITERATIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ralph-loop-claude: iterations must be a positive integer, got: $ITERATIONS" >&2
  exit 2
fi

[[ -n "$USER_REQUEST" ]] || { echo "ralph-loop-claude: empty request" >&2; exit 2; }

# Tools to deny — destructive verbs only. Reads, edits, builds, tests stay open.
# NOTE: --disallowedTools is variadic (`<tools...>`), so we MUST pass a single
# comma-separated token — otherwise it would eat the trailing prompt positional.
DENY_TOOLS='Bash(git commit:*),Bash(git push:*),Bash(git reset:*),Bash(git rebase:*),Bash(git checkout:*),Bash(git branch:*),Bash(git clean:*),Bash(git tag:*),Bash(rm:*),Bash(sudo:*)'

LOG_DIR="./.ralph-loop"
mkdir -p "$LOG_DIR"
RUN_TS="$(date +%Y%m%d-%H%M%S)"

trap 'echo; echo "ralph-loop-claude: interrupted"; exit 130' INT

render_claude_event_stream() {
  if ! command -v jq >/dev/null 2>&1; then
    cat
    return
  fi

  jq --unbuffered -Rr '
    def shorten($n):
      if . == null then ""
      elif (type != "string") then tostring
      elif length <= $n then .
      else .[0:$n] + "..."
      end;

    def compact_text:
      tostring | gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");

    def summarize:
      if . == null then ""
      elif (type == "object" or type == "array") then (tojson | shorten(180))
      else (compact_text | shorten(180))
      end;

    (fromjson?) as $event
    | if $event == null then
        empty
      elif $event.type == "system" and $event.subtype == "init" then
        "[claude] session started: model=\($event.model // "unknown") permission=\($event.permissionMode // "unknown")"
      elif $event.type == "system" and $event.subtype == "api_retry" then
        "[claude] api retry \($event.attempt // "?")/\($event.max_retries // "?") in \((((($event.retry_delay_ms // 0) / 1000) * 10) | round / 10))s (\($event.error // "unknown"))"
      elif $event.type == "system" and $event.subtype == "hook_response" and ($event.outcome // "") == "error" then
        "[claude] hook \($event.hook_name // "unknown") error: \((($event.output // $event.stderr // "unknown") | compact_text | shorten(220)))"
      elif $event.type == "assistant" then
        (
          $event.message.content[]?
          | if .type == "text" then
              .text
            elif .type == "tool_use" then
              "[tool] \(.name // "unknown"): \((.input | summarize))"
            else
              empty
            end
        )
      elif $event.type == "user" then
        (
          $event.message.content[]?
          | if .type == "tool_result" and (.is_error // false) then
              "[tool-error] \(.tool_use_id // "unknown"): \((.content | summarize))"
            elif .type == "tool_result" then
              "[tool-result] \(.tool_use_id // "unknown"): complete"
            else
              empty
            end
        )
      elif $event.type == "result" and ($event.is_error // false) then
        "[claude] error: \((($event.result // "unknown error") | compact_text | shorten(220)))"
      elif $event.type == "result" then
        "[claude] completed in \($event.duration_ms // 0)ms"
      else
        empty
      end
  '
}

for i in $(seq 1 "$ITERATIONS"); do
  echo
  echo "=== Ralph loop iteration $i / $ITERATIONS (claude) ==="
  echo "    pre-prompt: $PROMPT_FILE"
  echo "    cwd:        $PWD"
  echo "    log:        $LOG_DIR/${RUN_TS}-iter-${i}.log"
  echo

  COMPOSED_PROMPT=$(cat <<EOF
<task>
$USER_REQUEST
</task>

<iteration>
You are iteration $i of $ITERATIONS in a Ralph loop. Follow the system prompt's continuity contract: audit the worktree's current state first, then close the single highest-value gap. End with the Iteration summary block.
</iteration>
EOF
)

  claude -p \
    --permission-mode acceptEdits \
    --output-format stream-json \
    --system-prompt-file "$PROMPT_FILE" \
    --disallowedTools "$DENY_TOOLS" \
    -- "$COMPOSED_PROMPT" 2>&1 \
    | tee "$LOG_DIR/${RUN_TS}-iter-${i}.log" \
    | render_claude_event_stream

  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    echo "ralph-loop-claude: iteration $i exited with code $rc — continuing to next iteration" >&2
  fi
done

echo
echo "=== Ralph loop complete: $ITERATIONS iteration(s) ==="
echo "Logs: $LOG_DIR/${RUN_TS}-iter-*.log"

# Ralphloops

Modern shell harnesses for running coding agents in repeatable **Ralph loops**.

A Ralph loop is a simple pattern:

```text
fresh agent session → audit current worktree → close one high-value gap → verify → hand off
```

Each iteration starts with fresh context and re-discovers the current repository state. That makes the loop resilient: if a previous iteration already finished part of the task, the next iteration should notice instead of redoing it.

## What is included

| Command | Backend | Best for |
| --- | --- | --- |
| `ralph-loop-claude` | Claude Code | General autonomous plan/implement loops. Defaults to Sonnet/high. |
| `ralph-loop-sonnet` | Claude Code | Explicit Sonnet/high loop. |
| `ralph-loop-opus` | Claude Code | Explicit Opus/medium loop. |
| `ralph-loop-codex` | Codex CLI | OpenAI/Codex single-agent loops. |
| `ralph-loop-pi` | Pi coding agent | Pi-based loops using the default Codex model or env overrides. |
| `ralph-loop-pi-deepseek` | Pi coding agent | Pi-based loops defaulting to DeepSeek/high thinking. |
| `ralph-loop-auto` | Pi + Claude CLI | Pi/GPT loop that falls back directly to Claude Opus/medium when Codex 5-hour-limit output is detected. |
| `ralph-loop-smart` | Claude + Pi | Multi-model harness: heavy planning/analysis, Pi file scouts, Pi implementation, review, optional fix pass. |

## Install

```bash
bash /path/to/RalphLoops/install.sh
exec zsh   # or open a new shell
```

The installer:

- makes scripts executable
- appends one managed source block to `~/.zshrc`
- exposes all `ralph-loop-*` functions and short aliases

If you cloned this repo at `~/projects/RalphLoops`, run:

```bash
bash ~/projects/RalphLoops/install.sh
```

## Quick start

From any git worktree:

```bash
ralph-loop-smart plan-implement 2 "add the missing tests for the auth flow"
```

Or use a single backend:

```bash
ralph-loop-claude plan-implement 3 "build feature X"
ralph-loop-codex  plan-implement 2 "fix bug Y"
ralph-loop-pi          plan-implement 1 "audit and document Z"
ralph-loop-pi          --thinking high plan-implement 1 --file ./large-task.md
ralph-loop-pi-deepseek plan-implement 1 "audit and document Z"
ralph-loop-auto        plan-implement 3 "use Pi/GPT until Codex limits, then continue with Claude"
```

Arguments are the same for every wrapper:

1. **pre-prompt** — either a path to a markdown file, or a bare prompt name from `prompts/` without `.md`.
2. **iterations** — positive integer.
3. **request** — everything after `iterations`, joined as the task description.

Examples:

```bash
ralph-loop-sonnet plan-implement 3 "make the dashboard mobile-friendly"
ralph-loop-opus ./my-custom-prompt.md 1 "review the architecture and make the smallest safe improvement"
ralph-loop-smart plan-implement 4 "implement search, tests, and docs"
```

## Smart Ralph loop

`ralph-loop-smart` is the multi-model harness for bigger tasks.

Default pipeline:

```text
1. Claude Opus / high      planner           read-only
2. Pi GPT-5.3 Spark / off scouts            read-only file combing
3. Pi GPT-5.5 / medium    findings reviewer read-only heavy analysis
4. Pi GPT-5.5 / medium    worker            sole writer
5. Pi GPT-5.5 / medium    diff reviewer     read-only
6. Pi GPT-5.5 / medium    fix worker        sole writer, only if review finds fixes
```

Why this shape:

- **Opus plans** when deep reasoning matters.
- **Pi no-thinking scouts** use GPT-5.3-Codex-Spark by default for fast, cheap file discovery and validation/risk scouting.
- **Two default scouts are specialized**: scout 1 maps files/edit surfaces; scout 2 focuses on validation, risk, and edge cases.
- **Pi GPT-5.5 medium reviews scout findings** into a compact implementation contract.
- **Pi medium writes** the approved change using GPT-5.5 by default.
- **Pi GPT-5.5 medium reviews** the actual diff before any fix pass.
- **Shell owns orchestration**, so each phase passes files instead of relying on hidden chat history.

Run it:

```bash
ralph-loop-smart plan-implement 2 "refactor the classes page and keep the build green"

# Optional scout overrides
ralph-loop-smart --scout-model openai-codex/gpt-5.3-codex-spark --scout-thinking off \
  plan-implement 2 "refactor the classes page and keep the build green"
```

Artifacts are written under:

```text
./.ralph-loop/smart-YYYYmmdd-HHMMSS/iter-N/
├── plan.md
├── planner.log
├── scout-1.md
├── scout-1.log
├── scout-findings.md
├── implementation-contract.md
├── findings-reviewer.log
├── worker-prompt.md
├── worker.log
├── worker-summary.md
├── review.md
├── reviewer.log
├── fix.log
└── fix-summary.md
```

Add this to each target project’s `.gitignore`:

```gitignore
.ralph-loop/
```

### Smart loop environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `RALPH_SMART_PLAN_MODEL` | `opus` | Claude planner model. |
| `RALPH_SMART_PLAN_EFFORT` | `high` | Claude planner effort. |
| `RALPH_SMART_SCOUT_MODEL` | `openai-codex/gpt-5.3-codex-spark` | Pi scout model. Can also be set per run with `--scout-model`. |
| `RALPH_SMART_SCOUT_THINKING` | `off` | Pi scout thinking level. Can also be set per run with `--scout-thinking`. |
| `RALPH_SMART_SCOUT_COUNT` | `2` | Number of Pi read-only scout passes. |
| `RALPH_SMART_WORKER_MODEL` | `openai-codex/gpt-5.5` | Pi writer model. |
| `RALPH_SMART_WORKER_THINKING` | `medium` | Pi writer thinking level. |
| `RALPH_SMART_REVIEW_MODEL` | `openai-codex/gpt-5.5` | Pi reviewer model. |
| `RALPH_SMART_REVIEW_THINKING` | `medium` | Pi reviewer thinking level. |
| `RALPH_SMART_SKIP_REVIEW` | `0` | Set to `1` to skip review and fix phases. |
| `RALPH_SMART_SKIP_FIX` | `0` | Set to `1` to review only and skip automatic fixes. |

Examples:

```bash
# Override review model for one run
RALPH_SMART_REVIEW_MODEL=openai/gpt-5.5 \
RALPH_SMART_SKIP_FIX=1 \
ralph-loop-smart plan-implement 1 "inspect and improve the CLI help text"

# Override scout model/thinking for one run
ralph-loop-smart --scout-model openai/gpt-5.5 --scout-thinking "no thinking" \
  plan-implement 2 "build a small feature"

# Force OpenAI only if you have OPENAI_API_KEY configured
RALPH_SMART_SCOUT_MODEL=openai/gpt-5.5 \
RALPH_SMART_WORKER_MODEL=openai/gpt-5.5 \
RALPH_SMART_REVIEW_MODEL=openai/gpt-5.5 \
ralph-loop-smart plan-implement 2 "build a small feature"
```

## Single-backend wrappers

### Claude wrappers

`ralph-loop-claude` defaults to:

```text
model: sonnet
effort: high
permission mode: bypassPermissions
```

Use model-specific wrappers:

```bash
ralph-loop-sonnet plan-implement 2 "..."
ralph-loop-opus   plan-implement 1 "..."
```

Override Claude defaults:

```bash
RALPH_CLAUDE_MODEL=opus \
RALPH_CLAUDE_EFFORT=high \
RALPH_CLAUDE_PERMISSION_MODE=acceptEdits \
ralph-loop-claude plan-implement 1 "..."
```

`ralph-loop-claude` renders Claude’s stream in the terminal and saves the raw event stream to `.ralph-loop/`.

### Codex wrapper

```bash
ralph-loop-codex plan-implement 2 "..."
```

Codex runs with workspace-write sandboxing and non-interactive approval policy. Destructive shell commands are blocked by PATH shims.

### Pi wrappers

```bash
ralph-loop-pi          plan-implement 2 "..."
ralph-loop-pi          --thinking high plan-implement 1 --file ./large-task.md
ralph-loop-pi-deepseek plan-implement 2 "..."
ralph-loop-auto        plan-implement 2 "..."
```

`ralph-loop-pi` defaults to `openai-codex/gpt-5.5` with `medium` thinking. `ralph-loop-pi-deepseek` defaults to `openrouter/deepseek/deepseek-v4-flash` with `high` thinking. `ralph-loop-auto` starts with the Pi/GPT defaults and, if an iteration log contains Codex 5-hour-limit output, reruns that same iteration directly with Claude CLI using Opus/medium, then keeps using Claude for the rest of the run. Override per run:

```bash
RALPH_PI_MODEL=openai/gpt-5.5 \
RALPH_PI_THINKING=medium \
ralph-loop-pi plan-implement 1 "..."
```

You can also pass `--thinking "no thinking"|off|minimal|low|medium|high|xhigh`; aliases `none`, `no`, and `no-thinking` map to `off`.

`ralph-loop-auto` environment overrides:

| Variable | Default | Purpose |
| --- | --- | --- |
| `RALPH_AUTO_PI_MODEL` | `openai-codex/gpt-5.5` | Initial Pi model. |
| `RALPH_AUTO_PI_THINKING` | `medium` | Initial Pi thinking level. |
| `RALPH_AUTO_CLAUDE_MODEL` | `opus` | Direct Claude CLI fallback model. |
| `RALPH_AUTO_CLAUDE_EFFORT` | `medium` | Direct Claude CLI fallback effort. |
| `RALPH_AUTO_CODEX_LIMIT_REGEX` | built-in 5-hour-limit regex | Extended grep regex used to detect Codex subscription limit output. |

## Safety model

RalphLoops is intentionally conservative, but it is still an autonomous coding harness. Run it only in worktrees you are comfortable letting agents edit.

Allowed:

- read files and list directories
- grep/search code
- inspect git status/log/diff
- edit files in the current worktree
- run builds and tests
- run non-destructive shell commands

Blocked by prompts and shell/tool backstops where available:

- `git commit`
- `git push`
- `git reset`
- `git rebase`
- `git tag`
- `git clean`
- destructive checkout patterns
- `rm -r`, `rm -rf`, `rm -f`
- `sudo`

Important notes:

- The harness does **not** commit or push for you.
- Review generated diffs before committing.
- Do not put secrets in prompts.
- Do not commit `.ralph-loop/` logs; they can contain task text, file snippets, or model output.
- Use a dedicated branch/worktree for risky tasks.

## Pre-prompts

Pre-prompts live in `prompts/`.

The built-in prompt is:

```text
prompts/plan-implement.md
```

The core contract every prompt should preserve:

1. The worktree may already contain partial work.
2. Audit before editing.
3. Identify what is done, partial, missing, or broken.
4. Close the single highest-value remaining gap.
5. Verify with build/tests where practical.
6. End with an `## Iteration summary` handoff.

Create your own prompt:

```bash
cp prompts/plan-implement.md prompts/my-loop.md
ralph-loop-smart my-loop 2 "do something specific"
```

## Aliases

After install:

| Alias | Command |
| --- | --- |
| `rlc` | `ralph-loop-claude` |
| `rls` | `ralph-loop-sonnet` |
| `rlo` | `ralph-loop-opus` |
| `rld` | `ralph-loop-codex` |
| `rlp` | `ralph-loop-pi` |
| `rlpds` | `ralph-loop-pi-deepseek` |
| `rla` | `ralph-loop-auto` |
| `rlx` | `ralph-loop-smart` |

## Troubleshooting

### Command not found

Open a new shell or run:

```bash
source /path/to/RalphLoops/shell-init.sh
```

### The loop stalls on permissions

Use the default Claude permission mode, or explicitly set:

```bash
RALPH_CLAUDE_PERMISSION_MODE=bypassPermissions
```

For Smart loops, Claude phases are read-only by tool deny lists, Pi scout phases use read-only tool allowlists, and Pi writer phases run with destructive shell commands blocked by shims.

### A model name is wrong for your setup

Override it with env vars. For example:

```bash
RALPH_SMART_SCOUT_MODEL=provider/model \
RALPH_SMART_WORKER_MODEL=provider/model \
ralph-loop-smart plan-implement 1 "..."
```

### Logs are noisy

That is expected. The latest summary files are usually the most useful:

```bash
find .ralph-loop -name '*summary.md' -o -name 'review.md' -o -name 'plan.md'
```

## Repository layout

```text
RalphLoops/
├── README.md
├── install.sh
├── shell-init.sh
├── bin/
│   ├── ralph-loop-claude.sh
│   ├── ralph-loop-sonnet.sh
│   ├── ralph-loop-opus.sh
│   ├── ralph-loop-codex.sh
│   ├── ralph-loop-pi.sh
│   ├── ralph-loop-pi-deepseek.sh
│   ├── ralph-loop-auto.sh
│   ├── ralph-loop-smart.sh
│   └── shims/
│       ├── git
│       ├── rm
│       └── sudo
└── prompts/
    └── plan-implement.md
```

## Development checks

Useful local checks before committing changes to this repo:

```bash
bash -n bin/*.sh shell-init.sh install.sh
bash tests/test-ralph-loop-pi.sh
bash tests/test-ralph-loop-pi-deepseek.sh
bash tests/test-ralph-loop-auto.sh
bash bin/ralph-loop-smart.sh  # should print usage and exit 2
```

For deeper testing, put fake `claude` and `pi` binaries earlier in `PATH` and run `ralph-loop-smart` inside a temporary git repo. This verifies shell orchestration without spending API credits.

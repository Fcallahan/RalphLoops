# Ralphloops

Shell wrappers that run `claude` or `codex` in a **Ralph loop**: from any worktree, you give the agent a pre-prompt, an iteration count, and a task description, and it autonomously plans → implements → re-evaluates N times. Each iteration starts with a fresh context and re-discovers what's done by reading the current worktree state.

## Install

```bash
bash ~/code/Work/Ralphloops/install.sh
exec zsh   # or open a new shell
```

This appends a single `source` line to `~/.zshrc` (inside `# >>> ralphloops >>>` markers) and makes the scripts executable.

## Use

```bash
# from any worktree
ralph-loop-claude plan-implement 3 "build me a feature that does X"
ralph-loop-codex  plan-implement 3 "build me a feature that does X"
```

Arguments:

1. **pre-prompt** — either a path to a `.md` file, or the bare name of one in `prompts/` (e.g. `plan-implement`).
2. **iterations** — positive integer. Each iteration is a brand-new agent session.
3. **request** — everything after iterations, joined as the task description.

Logs land in `./.ralph-loop/<timestamp>-iter-N.log` in the worktree you ran the command from. Add `.ralph-loop/` to that worktree's `.gitignore`.

For `ralph-loop-claude`, the terminal now shows a live rendered event stream so long-running iterations do not look stuck. The saved Claude log is the raw event stream (JSON lines), which is useful for debugging retries, tool calls, and failures after the fact.

## What the agent can and can't do

**Allowed (no permission prompts):**
- Read files, list directories, grep, cat, git status / log / diff
- Edit files in the current worktree
- Run builds, run tests, run any non-destructive shell command

**Blocked (enforced two ways: Claude's `--disallowedTools` deny list, and a PATH shim for both backends):**
- `git commit`, `git push`, `git reset`, `git rebase`, `git tag`, `git clean`, `git branch -D`, `git checkout -- ...`
- `rm -r`, `rm -rf`, `rm -f`
- `sudo`

The pre-prompt also tells the agent never to attempt these, so the deny layer is a backstop, not the primary control.

## Pre-prompts

Drop new ones in `prompts/`. The filename (without `.md`) becomes the name you pass on the command line. The shipping prompt is `plan-implement.md`; read it for the format.

The key idea every Ralph-loop pre-prompt should encode: **"some of this work may already be done; audit the current state before doing anything; close the single highest-value gap; end with an Iteration summary block."**

## Layout

```
Ralphloops/
├── README.md
├── install.sh                  # appends source line to ~/.zshrc
├── shell-init.sh               # defines the shell functions
├── bin/
│   ├── ralph-loop-claude.sh
│   ├── ralph-loop-codex.sh
│   └── shims/                  # git/rm/sudo wrappers that block destructive verbs
│       ├── git
│       ├── rm
│       └── sudo
└── prompts/
    └── plan-implement.md
```

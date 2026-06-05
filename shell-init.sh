#!/usr/bin/env bash
# Sourced from ~/.zshrc by install.sh. Defines ralph-loop-* shell functions.

if [[ -z "${RALPH_LOOPS_DIR:-}" ]]; then
  _ralph_source=""

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    _ralph_source="${(%):-%x}"
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    _ralph_source="${BASH_SOURCE[0]}"
  fi

  if [[ -n "$_ralph_source" ]]; then
    RALPH_LOOPS_DIR="$(cd "$(dirname "$_ralph_source")" && pwd)"
  else
    RALPH_LOOPS_DIR="$HOME/code/Work/Ralphloops"
  fi

  unset _ralph_source
fi

export RALPH_LOOPS_DIR

# Tab completions for ralph-loop-* commands
fpath+=("$RALPH_LOOPS_DIR/completions")

ralph-loop-claude() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-claude.sh" "$@"
}

ralph-loop-sonnet() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-sonnet.sh" "$@"
}

ralph-loop-opus() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-opus.sh" "$@"
}

ralph-loop-codex() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-codex.sh" "$@"
}

ralph-loop-pi() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-pi.sh" "$@"
}

ralph-loop-pi-deepseek() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-pi-deepseek.sh" "$@"
}

ralph-loop-auto() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-auto.sh" "$@"
}

ralph-loop-smart() {
  "$RALPH_LOOPS_DIR/bin/ralph-loop-smart.sh" "$@"
}

alias rlc='ralph-loop-claude'
alias rls='ralph-loop-sonnet'
alias rlo='ralph-loop-opus'
alias rld='ralph-loop-codex'
alias rlp='ralph-loop-pi'
alias rlpds='ralph-loop-pi-deepseek'
alias rla='ralph-loop-auto'
alias rlx='ralph-loop-smart'

#!/usr/bin/env bash
# Install the /pshare slash command into Claude Code and/or Codex.
#
#   install-pshare-command.sh [--client claude|codex|both] [--project]
#
# --client both (default) installs into whichever of the two is present.
# Defaults to each client's user-level command dir so /pshare works in every
# session. --project installs into this repo's .claude/commands/ instead
# (Claude Code only; Codex has no per-project prompt dir).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLIENT="both"
PROJECT=0
for arg in "$@"; do
  case "$arg" in
    --client=*) CLIENT="${arg#*=}" ;;
    --client)   echo "error: use --client=<value>" >&2; exit 2 ;;
    claude|codex|both) CLIENT="$arg" ;;
    --project)  PROJECT=1 ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

install_one() {
  local name="$1" src="$2" dest_dir="$3"
  if [[ ! -f "$src" ]]; then
    echo "error: $src not found - run this from a pond checkout" >&2
    exit 1
  fi
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/pshare.md"
  echo "installed ($name): $dest_dir/pshare.md"
}

install_claude() {
  local src="$REPO_DIR/integrations/claude-code/commands/pshare.md" dest_dir
  if [[ "$PROJECT" == 1 ]]; then
    dest_dir="$REPO_DIR/.claude/commands"
  else
    # Respects CLAUDE_CONFIG_DIR for multi-instance setups (e.g. CCS); falls
    # back to Claude Code's default ~/.claude.
    dest_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
  fi
  install_one claude "$src" "$dest_dir"
}

install_codex() {
  if [[ "$PROJECT" == 1 ]]; then
    echo "error: --project is Claude Code only; Codex has no per-project prompt dir" >&2
    exit 2
  fi
  # Respects CODEX_HOME; falls back to Codex's default ~/.codex.
  install_one codex \
    "$REPO_DIR/integrations/codex/prompts/pshare.md" \
    "${CODEX_HOME:-$HOME/.codex}/prompts"
}

case "$CLIENT" in
  claude) install_claude ;;
  codex)  install_codex ;;
  both)
    installed=0
    if [[ "$PROJECT" == 1 ]]; then
      install_claude; installed=1
    else
      if [[ -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ]]; then install_claude; installed=1; fi
      if [[ -d "${CODEX_HOME:-$HOME/.codex}" ]]; then install_codex; installed=1; fi
    fi
    if [[ "$installed" == 0 ]]; then
      echo "error: neither ~/.claude nor ~/.codex found; pass --client=claude|codex explicitly" >&2
      exit 1
    fi
    ;;
  *) echo "error: --client must be claude, codex, or both" >&2; exit 2 ;;
esac

echo "start a fresh session in that client to pick it up, then type /pshare"

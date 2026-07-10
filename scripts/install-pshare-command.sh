#!/usr/bin/env bash
# Install the /pshare Claude Code slash command.
#
# Defaults to the user-level commands dir so /pshare works in every session.
# Pass --project to install into this repo's .claude/commands/ instead (only
# available inside this repo).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_DIR/integrations/claude-code/commands/pshare.md"

if [[ ! -f "$SRC" ]]; then
  echo "error: $SRC not found - run this from a pond checkout" >&2
  exit 1
fi

if [[ "${1:-}" == "--project" ]]; then
  DEST_DIR="$REPO_DIR/.claude/commands"
else
  # Respects CLAUDE_CONFIG_DIR for multi-instance setups (e.g. CCS); falls
  # back to Claude Code's default ~/.claude.
  DEST_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
fi

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST_DIR/pshare.md"

echo "installed: $DEST_DIR/pshare.md"
echo "start a new Claude Code session to pick it up, then type /pshare"

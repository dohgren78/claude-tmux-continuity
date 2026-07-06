#!/usr/bin/env bash
# Install the Claude Code tmux session-continuity scripts: symlink them into
# ~/.claude/bin so this repo stays the source of truth (edit here -> live).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.claude/bin"
mkdir -p "$BIN"

for s in tmux-claude-snapshot.sh tmux-claude-restore.sh; do
  ln -sfn "$REPO/$s" "$BIN/$s"
  echo "linked $BIN/$s -> $REPO/$s"
done

echo
echo "Next steps:"
echo "  1. Install tmux-resurrect + tmux-continuum via TPM."
echo "  2. Append tmux.conf.snippet to ~/.tmux.conf, then reload (prefix + I to install plugins)."
echo "  3. Optional: copy RESTORE-CLAUDE-FLEET.command to ~/Desktop as a manual restore button."
echo "  4. Optional: 'brew install terminal-notifier' for the prefix+C snapshot notification."

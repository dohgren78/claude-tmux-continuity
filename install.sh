#!/usr/bin/env bash
# Install the Claude Code tmux session-continuity scripts: symlink them into
# ~/.claude/bin so this repo stays the source of truth (edit here -> live).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.claude/bin"

# tmux is required; the automatic reboot flow also needs the TPM plugins.
command -v tmux >/dev/null 2>&1 || { echo "missing dependency: tmux (install it first)" >&2; exit 1; }
for p in tmux-resurrect tmux-continuum; do
  [ -d "$HOME/.tmux/plugins/$p" ] || echo "note: $p not found under ~/.tmux/plugins — the automatic post-reboot restore won't fire until you add it via TPM (see step 1 below)." >&2
done

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

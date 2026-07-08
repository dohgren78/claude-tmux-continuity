#!/bin/zsh
# Manual fallback: rebuild ALL tmux Claude sessions on their real conversations.
# Normally automatic after reboot (resurrect post-restore hook). Use this only if
# the auto-restore didn't fire or you want to force it.
# Finder double-click gives a minimal PATH — cover both Homebrew prefixes.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
zsh "$HOME/.claude/bin/tmux-claude-restore.sh"
echo
echo "Attaching to tmux..."
exec tmux attach

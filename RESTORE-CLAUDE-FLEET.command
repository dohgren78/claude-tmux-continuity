#!/bin/zsh
# Manual fallback: rebuild ALL tmux Claude sessions on their real conversations.
# Normally automatic after reboot (resurrect post-restore hook). Use this only if
# the auto-restore didn't fire or you want to force it.
zsh "$HOME/.claude/bin/tmux-claude-restore.sh"
echo
echo "Attaching to tmux..."
exec /opt/homebrew/bin/tmux attach

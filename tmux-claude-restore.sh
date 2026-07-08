#!/bin/zsh
# Restore every Claude Code session into its tmux session after a reboot.
# Reads the snapshot TSV and fires `claude --resume <id>` in each named tmux
# session. Idempotent: a pane already running claude is left alone.
# Intended to run from resurrect's @resurrect-hook-post-restore-all, or by hand.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
TSV="$HOME/.claude/tmux-claude-sessions.tsv"
# Resolve the claude binary: $CLAUDE override -> PATH -> native-installer default.
CLAUDE="${CLAUDE:-$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")}"
LOG="$HOME/.claude/tmux-claude-restore.log"
[ -f "$TSV" ] || { echo "no snapshot at $TSV"; exit 1; }
[ -x "$CLAUDE" ] || { echo "claude not found at '$CLAUDE' — set \$CLAUDE or install Claude Code"; exit 1; }
tmux start-server 2>/dev/null

while IFS=$'\t' read -r sess win pane cwd sid; do
  [ -z "$sess" ] && continue
  tmux has-session -t "$sess" 2>/dev/null || tmux new-session -d -s "$sess" -c "$cwd"

  # Prefer the exact saved window.pane; fall back to the session's active pane.
  target="$sess:${win:-1}.${pane:-1}"
  tmux display-message -p -t "$target" '' 2>/dev/null || target="$sess"

  cur=$(tmux display-message -p -t "$target" '#{pane_current_command}' 2>/dev/null)
  case "$cur" in
    claude|*[0-9].[0-9]*) echo "skip $sess (claude running)"; continue ;;
  esac

  tmux send-keys -t "$target" "cd ${cwd} && exec ${CLAUDE} --resume ${sid}" Enter
  echo "restore $sess -> --resume $sid"
done < "$TSV" | tee -a "$LOG"

echo "tmux-claude-restore done. Attach: tmux attach" | tee -a "$LOG"

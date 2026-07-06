#!/bin/zsh
# Snapshot every tmux pane's live Claude Code session so it can be resumed
# verbatim after a reboot. Deterministic join on the controlling tty:
#   tmux pane (#{pane_tty}) <-> claude process tty <-> ~/.claude/sessions/<pid>.json
# Output TSV: <tmux_session>\t<window>\t<pane>\t<cwd>\t<claude_session_id>
# Run periodically (launchd) so the map is always current before any reboot.
OUT="$HOME/.claude/tmux-claude-sessions.tsv"
SESSDIR="$HOME/.claude/sessions"
TMP="$(mktemp)"

command -v tmux >/dev/null 2>&1 || exit 0
tmux info >/dev/null 2>&1 || exit 0   # no server, nothing to snapshot

# Build: tty -> "session\twindow\tpane\tcwd"
typeset -A PANE
while IFS='|' read -r tty sess win pane cwd; do
  PANE[${tty##*/}]="$sess	$win	$pane	$cwd"
done < <(tmux list-panes -a -F '#{pane_tty}|#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}')

# For each live claude session file, resolve its tty and join to the pane.
for f in "$SESSDIR"/*.json(N); do
  pid=$(/usr/bin/sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$f")
  sid=$(/usr/bin/sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' "$f")
  [ -n "$pid" ] && [ -n "$sid" ] || continue
  tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')   # e.g. ttys007 ; empty if dead
  [ -n "$tty" ] || continue
  row="${PANE[$tty]}"
  [ -n "$row" ] || continue
  printf '%s\t%s\n' "$row" "$sid" >> "$TMP"
done

if [ -s "$TMP" ]; then
  sort -u "$TMP" -o "$TMP"
  mv "$TMP" "$OUT"
  COUNT=$(grep -c . "$OUT")
  echo "snapshot: $COUNT sessions -> $OUT"
  tmux display-message -d 3000 "Claude snapshot: $COUNT sessions saved" 2>/dev/null || true
  if [ -n "$CLAUDE_SNAPSHOT_NOTIFY" ]; then
    terminal-notifier -title "Claude Snapshot" -message "$COUNT sessions saved" -sound default 2>/dev/null || true
  fi
else
  rm -f "$TMP"
  echo "snapshot: no live claude sessions found; kept existing $OUT" >&2
fi

#!/bin/zsh
# Snapshot every tmux pane's live Claude Code session so it can be resumed
# verbatim after a reboot.
# Output TSV: <tmux_session>\t<window>\t<pane>\t<cwd>\t<claude_session_id>
# Run periodically (launchd) so the map is always current before any reboot.
#
# Ground truth is the LIVE PROCESS, not ~/.claude/sessions/*.json.
#
# Those JSON files are named by pid and outlive the process that wrote them. When
# the OS reuses a pid, a stale <pid>.json still resolves to a real tty, so the old
# code mapped a live pane to a DEAD session's id. Restoring from that map silently
# swaps a conversation for an unrelated one — observed 2026-07-10, when three panes
# were resumed onto the wrong transcripts.
#
# So: walk panes -> find the claude process on that pane's tty -> take the session id
# out of its argv (`--resume <uuid>` / `--session-id <uuid>`). Only when argv carries
# no id (a plain `claude`, i.e. a brand-new session) do we consult <pid>.json, and then
# only the file belonging to that exact live pid. A stale json can never win.
OUT="$HOME/.claude/tmux-claude-sessions.tsv"
SESSDIR="$HOME/.claude/sessions"
TMP="$(mktemp)"

command -v tmux >/dev/null 2>&1 || exit 0
tmux info >/dev/null 2>&1 || exit 0   # no server, nothing to snapshot

UUID='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'

# tty -> pid of the interactive claude on it. Excludes the daemon and the
# bg-spare / bg-pty-host helpers: those are not sessions and carry no transcript.
typeset -A CLAUDE_PID
while read -r pid tty cmd; do
  [ "$tty" = "??" ] && continue                        # no controlling terminal
  case "$cmd" in
    *bg-spare*|*bg-pty-host*|*"daemon run"*) continue ;;
  esac
  case "${cmd%% *}" in                                 # argv[0] must be claude itself
    claude|*/claude) ;;
    *) continue ;;
  esac
  [ -n "${CLAUDE_PID[$tty]}" ] || CLAUDE_PID[$tty]="$pid"   # lowest pid on the tty wins
done < <(ps -eo pid=,tty=,command= | sort -n)

# sid_of <pid> — argv first, then that pid's own session json.
sid_of() {
  local pid="$1" argv sid f jpid jsid
  argv=$(ps -o command= -p "$pid" 2>/dev/null)
  sid=$(print -r -- "$argv" | grep -oE "(--resume|--session-id)[= ]+$UUID" | grep -oE "$UUID" | head -1)
  if [ -n "$sid" ]; then print -r -- "$sid"; return 0; fi

  f="$SESSDIR/$pid.json"
  [ -f "$f" ] || return 1
  jpid=$(/usr/bin/sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$f")
  jsid=$(/usr/bin/sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' "$f")
  [ "$jpid" = "$pid" ] || return 1      # stale file: pid was reused
  [ -n "$jsid" ] || return 1
  print -r -- "$jsid"
}

MISSING=0
while IFS='|' read -r tty sess win pane cwd; do
  t="${tty##*/}"
  pid="${CLAUDE_PID[$t]}"
  [ -n "$pid" ] || continue                 # no claude in this pane
  sid=$(sid_of "$pid") || { MISSING=$((MISSING+1)); continue; }
  printf '%s\t%s\t%s\t%s\t%s\n' "$sess" "$win" "$pane" "$cwd" "$sid" >> "$TMP"
done < <(tmux list-panes -a -F '#{pane_tty}|#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}')

if [ -s "$TMP" ]; then
  sort -u "$TMP" -o "$TMP"
  mv "$TMP" "$OUT"
  COUNT=$(grep -c . "$OUT")
  echo "snapshot: $COUNT sessions -> $OUT"
  [ "$MISSING" -gt 0 ] && echo "snapshot: $MISSING pane(s) ran claude with no resolvable session id" >&2
  tmux display-message -d 3000 "Claude snapshot: $COUNT sessions saved" 2>/dev/null || true
  if [ -n "$CLAUDE_SNAPSHOT_NOTIFY" ]; then
    terminal-notifier -title "Claude Snapshot" -message "$COUNT sessions saved" -sound default 2>/dev/null || true
  fi
else
  rm -f "$TMP"
  echo "snapshot: no live claude sessions found; kept existing $OUT" >&2
fi

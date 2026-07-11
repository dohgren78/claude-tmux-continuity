#!/bin/zsh
# Snapshot every tmux pane's live Claude Code session so it can be resumed
# verbatim after a reboot.
# Output TSV: <tmux_session>\t<window>\t<pane>\t<cwd>\t<claude_session_id>
# Run periodically (launchd) so the map is always current before any reboot.
#
# Ground truth is the LIVE PROCESS's OWN session json — validated by mtime.
#
# Two failure modes, pulling in opposite directions:
#  - pid reuse: <pid>.json outlives its process; when the OS reuses the pid, the
#    stale file maps a live pane to a DEAD session's id (observed 2026-07-10:
#    three panes resumed onto the wrong transcripts). Argv looks safer here...
#  - sessionId drift: ...but a resumed session can MINT A NEW sessionId, so argv
#    (`--resume <old-uuid>`) goes stale while the json stays correct (observed
#    2026-07-11: TSV pointed a live pane at its pre-resume conversation fork).
#
# The rule that survives both: trust <pid>.json IFF its mtime >= the process's
# start time. A live claude rewrites its json continuously (busy/idle flips), so
# a fresh mtime proves the file belongs to THIS process; a dead predecessor's
# json can never be newer than the reused pid's start. Argv is only a fallback
# for the brief window before a brand-new session first writes its json.
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

# sid_of <pid> — the pid's own session json when provably live (mtime >= proc
# start), else argv. Json first because a resumed session can mint a new
# sessionId, leaving argv's `--resume <uuid>` pointing at the old conversation.
sid_of() {
  local pid="$1" argv sid f jpid jsid jm ps_start
  f="$SESSDIR/$pid.json"
  if [ -f "$f" ]; then
    jpid=$(/usr/bin/sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$f")
    jsid=$(/usr/bin/sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' "$f")
    if [ "$jpid" = "$pid" ] && [ -n "$jsid" ]; then
      jm=$(/usr/bin/stat -f %m "$f" 2>/dev/null)
      ps_start=$(LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null)
      ps_start=$(LC_ALL=C /bin/date -j -f "%a %b %d %T %Y" "${ps_start## }" +%s 2>/dev/null)
      # json written during THIS process's lifetime -> it is this process's json
      if [ -n "$jm" ] && [ -n "$ps_start" ] && [ "$jm" -ge "$ps_start" ]; then
        print -r -- "$jsid"; return 0
      fi
    fi
  fi
  argv=$(ps -o command= -p "$pid" 2>/dev/null)
  sid=$(print -r -- "$argv" | grep -oE "(--resume|--session-id)[= ]+$UUID" | grep -oE "$UUID" | head -1)
  [ -n "$sid" ] || return 1
  print -r -- "$sid"
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

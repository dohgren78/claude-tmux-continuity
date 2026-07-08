# claude-tmux-continuity

Restore every Claude Code session **verbatim** after a Mac reboot — each tmux pane
comes back running `claude --resume <its own sessionId>`, not a bare shell.

Companion to [claude-tmux-dashboard](https://github.com/dohgren78/claude-tmux-dashboard)
(the live fzf overview of sessions). This repo is the reboot-survival half.

## The problem

Running ~14 Claude Code sessions, one per tmux session, a reboot kills them all.
`tmux-resurrect` + `tmux-continuum` bring the *layout* back, but each pane returns as
a fresh shell — you've lost which conversation belonged where, and have to hunt through
cryptic `claude --resume` summaries to reattach each one.

## How it works

Claude Code writes `~/.claude/sessions/<pid>.json` for every **live** session
(`{pid, sessionId, cwd, ...}`). The scripts join tmux panes to those sessions on the
**controlling tty** — the one reliable key:

```
tmux pane (#{pane_tty})  <->  claude process tty (ps -o tty=)  <->  sessions/<pid>.json
```

- **`tmux-claude-snapshot.sh`** — tty-joins every pane to its `sessionId`, writes a TSV
  map to `~/.claude/tmux-claude-sessions.tsv`. Runs on every continuum save (15 min) and
  on `prefix + C`. With `CLAUDE_SNAPSHOT_NOTIFY=1` (set only by the manual `prefix + C`
  bind) it fires a macOS notification via `terminal-notifier`; the auto-saves stay silent.
- **`tmux-claude-restore.sh`** — reads the TSV and sends `cd <cwd> && exec claude --resume
  <id>` into each pane. Idempotent (skips panes already running claude).

tmux hooks wire them to resurrect: `@resurrect-hook-post-save-all` -> snapshot,
`@resurrect-hook-post-restore-all` -> restore. See `tmux.conf.snippet`.

**Post-reboot flow (hands-off):** boot -> tmux server auto-starts (`@continuum-boot`) ->
continuum restores the layout -> post-restore hook fires -> each pane relaunches
`claude --resume <its id>`. If auto-restore doesn't fire, double-click
`RESTORE-CLAUDE-FLEET.command`.

**Caveat:** the snapshot only refreshes on continuum's 15-min save (or `prefix + C`). A
session started <15 min before a reboot may be missed unless you hit `prefix + C` first.

**Limitation — daemon-hosted (background / agent) sessions:** Claude Code 2.1+ can split a
session into a daemon-hosted background *job* and a thin interactive *client* that owns the
tmux pane. The tty-join captures whichever session owns the pane. For ordinary foreground
`claude` sessions (the usual case) that *is* the real conversation, so it resumes correctly.
But when a pane is a client of a background/agent job, the captured `sessionId` is the
client's — which can differ from the job's actual conversation — so `--resume` may reopen the
client rather than the work. Plain interactive sessions are unaffected. (The companion
[dashboard](https://github.com/dohgren78/claude-tmux-dashboard) resolves this by keying on the
job id; continuity may follow — see issues.)

## Install

```sh
git clone https://github.com/dohgren78/claude-tmux-continuity ~/Code/claude-tmux-continuity
cd ~/Code/claude-tmux-continuity && ./install.sh
```

`install.sh` symlinks the scripts into `~/.claude/bin` (this repo stays the source of
truth — edit here, live everywhere). Then append `tmux.conf.snippet` to `~/.tmux.conf`,
install the plugins (`prefix + I`), and optionally
`brew install terminal-notifier` for the snapshot notification.

## Files

| File | Purpose |
|------|---------|
| `tmux-claude-snapshot.sh` | Map live panes -> Claude sessionIds (TSV) |
| `tmux-claude-restore.sh` | Relaunch `claude --resume <id>` per pane after restore |
| `tmux.conf.snippet` | resurrect/continuum config + hooks + `prefix + C` bind |
| `RESTORE-CLAUDE-FLEET.command` | Desktop double-click fallback restore |
| `install.sh` | Symlink scripts into `~/.claude/bin` |

macOS-only (tty joins via `ps`, `terminal-notifier`). Requires Claude Code, tmux,
tmux-resurrect, tmux-continuum.

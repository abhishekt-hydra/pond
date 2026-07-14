# `pond watch`: continuous session backup

`pond watch` is a long-lived daemon that backs up sessions the moment an agent writes to
them, instead of waiting for the next `pond schedule` tick. It complements, and does not
replace, `pond schedule`:

| | trigger | what it does | embeddings |
|---|---|---|---|
| `pond schedule` | timer (default every 5m) | full `pond sync -q --no-wait` | embedded inline, per the `[embeddings]` config |
| `pond watch` | a filesystem write to a session file | incremental **no-embed** sync | left null; fill the backlog with `pond optimize` |

Watch trades embedding cost for latency: a message lands in the store within a couple of
seconds of being written, searchable by full-text immediately, semantically searchable
once you next run `pond optimize` (or the next `pond schedule` tick, which embeds
inline). Run both if you want near-real-time durability *and* periodic embedding
catch-up; either alone is fine too.

## Set it up

```sh
pond watch start     # register with the OS keepalive supervisor
pond watch status     # confirm it's active, and where the logs are
pond watch logs        # tail recent output
pond watch stop        # unregister
```

`start` is idempotent - re-running it with an unchanged registration is a no-op. It needs
at least one enabled filesystem adapter (`pond adapters enable claude-code`, or run
`pond init` first); with none, `pond watch run` refuses to start rather than watching
nothing.

Platform mechanics:

- **macOS**: a `launchd` agent (`sh.pond.watch`, `~/Library/LaunchAgents/sh.pond.watch.plist`) with `KeepAlive=true` and `RunAtLoad=true` - it relaunches if killed and starts at login. Logs go to `$XDG_STATE_HOME/pond/watch.log` (`pond watch logs` tails it).
- **Linux**: a systemd `--user` service (`pond-watch.service`) with `Restart=always`, enabled with `--now`. Logs go to the journal (`pond watch logs` shells out to `journalctl --user -u pond-watch.service`). A machine without a systemd user session has no fallback - watch needs a real process supervisor, unlike `pond schedule`'s cron fallback for interval jobs - so `start` bails with a clear message; run `pond watch run` yourself under `tmux`/`screen`/a container entrypoint instead.
- **Windows**: not supported yet; `start`/`stop`/`status`/`logs` all error.

`pond watch run` runs the daemon in the foreground (what the registered service actually
execs) - useful for watching its output live or running it under your own supervisor.

## What it watches

On startup the daemon resolves the same source roots `pond sync` would read - every
enabled filesystem adapter's configured `path` (or `paths`, if you've pooled more than
one directory - see `pond config schema`) - and places one recursive filesystem watch per
resolved root. API-backed adapters (nothing on local disk) contribute no root and stay
covered by `pond schedule` alone.

```
$ pond watch logs
watch: watching 3 source roots
watch:   claude-code -> /Users/you/.claude/projects
watch:   claude-code -> /Users/you/work/.claude/projects
watch:   codex-cli -> /Users/you/.codex/sessions
watch: startup catch-up sync
```

A root that doesn't exist yet (a fresh install before its agent has written a first
session) is skipped with a warning rather than aborting the daemon - it starts being
watched once it appears, and the next scheduled sync covers it in the meantime. Every
write event across every watched root, however many files changed, debounces into a
single incremental sync (1.5s settle window) so a burst of writes to several sessions at
once still costs one sync, not one per file.

## Troubleshooting

- **`pond watch status` says not running**: `pond watch start` again; check `pond watch logs` for why the previous run may have exited (e.g. a config error).
- **A session isn't showing up seconds after being written**: confirm its adapter is enabled (`pond adapters list`) and its root is actually being watched (`pond watch logs` prints the resolved roots at every startup/catch-up).
- **Search isn't finding recent text**: no-embed sync only fills the FTS arm immediately; semantic search over new messages needs `pond optimize` (or a `pond schedule` tick) to embed them.
- **Linux, no systemd user session**: `pond watch start` bails rather than half-registering; run `pond watch run` under your own supervisor.

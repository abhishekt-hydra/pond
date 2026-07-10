# `/pshare`: publish a session from inside your coding agent

`/pshare` runs `pond share` against *the session you're currently in* — no session
id to look up, no leaving the conversation. It ships for two clients:

- **Claude Code** — `~/.claude/commands/pshare.md`
- **Codex** — `~/.codex/prompts/pshare.md`

Install it once, then type `/pshare` mid-session to get a public link to the
transcript so far. Both versions run the same safety flow (sync → warn → confirm
→ share); they differ only in how they figure out which session you're in.

## Install

The installer copies the right file into the right place for each client:

```sh
scripts/install-pshare-command.sh                 # both, wherever ~/.claude / ~/.codex exist
scripts/install-pshare-command.sh --client=claude # Claude Code only
scripts/install-pshare-command.sh --client=codex  # Codex only
scripts/install-pshare-command.sh --project       # Claude Code, into this repo's .claude/commands/
```

Or copy by hand:

```sh
mkdir -p ~/.claude/commands && cp integrations/claude-code/commands/pshare.md ~/.claude/commands/pshare.md
mkdir -p ~/.codex/prompts   && cp integrations/codex/prompts/pshare.md        ~/.codex/prompts/pshare.md
```

The installer respects `CLAUDE_CONFIG_DIR` (multi-instance setups like CCS) and
`CODEX_HOME`. Either way the command is picked up the next time the client loads
its command list — a fresh session.

## How each client finds "this session"

This is the one real difference between the two.

**Claude Code** sets `CLAUDE_CODE_SESSION_ID` in the process environment for the
whole session (not just for hooks). It's the exact filename Claude Code writes
the live transcript to:

```
$CLAUDE_CONFIG_DIR/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID.jsonl
```

and that same UUID is the `raw_session_id` pond's `claude-code` adapter reads
straight into `Session.id` (`src/adapter/claude_code.rs`). So the command hands
`$CLAUDE_CODE_SESSION_ID` directly to `pond share` — the ids always match.

**Codex** exposes no equivalent session-id env var, so the command resolves the
session from the newest rollout file on disk — the one the live session is
appending to:

```
${CODEX_HOME:-~/.codex}/sessions/<year>/<month>/<day>/rollout-<ts>-<uuid>.jsonl
```

It picks the most-recently-modified `rollout-*.jsonl` and extracts the trailing
`<uuid>`. That UUID is exactly the `session_meta.id` pond's `codex-cli` adapter
reads into `Session.id` (`src/adapter/codex_cli.rs`), so it's the id `pond share`
expects. Newest-by-mtime is reliable while you're actively in the session; if you
had two Codex sessions writing at once it would pick the more recent one.

## Why it syncs before sharing

`pond watch`, if running, backs up writes within a couple of seconds (a 1.5s
debounce — see [`docs/watch.md`](watch.md)), but that's asynchronous: the last
message or two before you type `/pshare` may not have landed in the store yet.
The command runs `pond sync <adapter> -q` first — scoped to the one adapter
(`claude-code` or `codex-cli`), so it's fast — to guarantee the transcript pond
renders is actually current.

## Why it asks before publishing

`pond share` requires `--yes` or an interactive confirm because publishing is
irreversible and unredacted — anything in the transcript, including secrets,
becomes public. `/pshare` is a plain instruction prompt rather than a one-line
auto-exec command for exactly this reason: it lets the agent explain what's about
to go public and get a real answer in chat before it ever passes `--yes`. Don't
edit the command to skip that step.

## Troubleshooting

- **`pond share` errors that no bucket is configured**: `/pshare` needs a
  `[share]` block in `config.toml` (or a `--to <url>` every time, which the
  command doesn't pass). See the "Share a session" section in the README and
  `pond config schema` to set one up — a bucket + a `[creds.share]` credential
  set, kept separate from your data-store creds.
- **Codex: "couldn't resolve the current session"**: no `rollout-*.jsonl` was
  found under `${CODEX_HOME:-~/.codex}/sessions`, or the newest file's name had
  no UUID. Confirm Codex is writing rollouts there; the command refuses to guess
  an id rather than share the wrong session.
- **The published link downloads instead of rendering**: confirm the object was
  written with `Content-Type: text/html` (`pond share`'s publisher sets this
  automatically; a custom `--to` destination still needs to serve that content
  type back).
- **The published link 403s / "access denied"**: by default the link is a
  presigned URL valid for 48h (`[share].presign_expiry_hours` /
  `--expires-hours`) — it expired, or `pond share` was re-run with a mismatched
  `[creds.share]` set. If you're using `[share].public_base_url` instead (a
  genuinely public bucket/CDN), check that origin actually serves the bucket's
  contents.
- **`/pshare` isn't found**: confirm the file landed in the client's command dir
  (`~/.claude/commands/pshare.md` or `~/.codex/prompts/pshare.md`) and start a
  fresh session to pick up new commands.

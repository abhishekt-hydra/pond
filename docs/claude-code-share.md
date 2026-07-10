# `/pshare`: publish a session from inside Claude Code

`/pshare` is a Claude Code slash command that runs `pond share` against *the session you're
currently in* — no session id to look up, no leaving the conversation. Install it once, then
type `/pshare` mid-session to get a public link to the transcript so far.

## Install

Copy the command into Claude Code's commands directory:

```sh
mkdir -p ~/.claude/commands
cp integrations/claude-code/commands/pshare.md ~/.claude/commands/pshare.md
```

Or, to make it available only inside this repo, drop it in `.claude/commands/pshare.md`
instead of the user-level `~/.claude/commands/`. Either way it's picked up the next time
Claude Code loads its command list (a fresh session, or `/commands reload` if your version
supports it).

## How it finds "this session"

Claude Code sets `CLAUDE_CODE_SESSION_ID` in the process environment for the whole session
(not just for hooks) — no heuristics needed. It's the exact filename Claude Code writes the
live transcript to:

```
$CLAUDE_CONFIG_DIR/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID.jsonl
```

and that same UUID is the `raw_session_id` pond's `claude-code` adapter reads straight into
`Session.id` (`src/adapter/claude_code.rs`). So `/pshare` hands `$CLAUDE_CODE_SESSION_ID`
directly to `pond share` — the ids always match for a top-level session.

## Why it syncs before sharing

`pond watch`, if running, backs up writes within a couple of seconds (a 1.5s debounce — see
[`docs/watch.md`](watch.md)), but that's asynchronous: the last message or two before you type
`/pshare` may not have landed in the store yet. The command runs `pond sync claude-code -q`
first — scoped to one adapter, so it's fast — to guarantee the transcript pond renders is
actually current.

## Why it asks before publishing

`pond share` requires `--yes` or an interactive confirm because publishing is irreversible and
unredacted — anything in the transcript, including secrets, becomes public. `/pshare` is a
plain instruction prompt rather than a one-line `!`-exec command for exactly this reason: it
lets Claude explain what's about to go public and get a real answer in chat before it ever
passes `--yes`. Don't edit the command to skip that step.

## Troubleshooting

- **`pond share` errors that no bucket is configured**: `/pshare` needs a `[share]` block in
  `config.toml` (or a `--to <url>` every time, which the command doesn't pass). See the
  "Share a session" section in the README and `pond config schema` to set one up — a bucket +
  a `[creds.share]` credential set, kept separate from your data-store creds.
- **The published link downloads instead of rendering**: confirm the object was written with
  `Content-Type: text/html` (`pond share`'s publisher sets this automatically; a custom `--to`
  destination still needs to serve that content type back).
- **The published link 403s / "access denied"**: by default the link is a presigned URL valid
  for 48h (`[share].presign_expiry_hours` / `--expires-hours`) — it expired, or `pond share` was
  re-run with a mismatched `[creds.share]` set. If you're using `[share].public_base_url`
  instead (a genuinely public bucket/CDN), check that origin actually serves the bucket's
  contents.
- **`/pshare` isn't found**: confirm the file landed in `~/.claude/commands/pshare.md` (or your
  project's `.claude/commands/`) and start a fresh Claude Code session to pick up new commands.

---
description: Publish the current Claude Code session to a public pond share link
---

Publish this conversation with `pond share`.

1. Run `pond sync claude-code -q` so anything not yet caught by `pond watch` is current.
2. Tell the user, plainly: this publishes the ENTIRE transcript (every message, tool call,
   and result — no redaction) to a public URL anyone with the link can open. Ask for explicit
   confirmation before continuing.
3. Once confirmed, run `pond share "$CLAUDE_CODE_SESSION_ID" --yes` (no `--open`) and report
   the printed URL back to the user.
4. If `pond share` fails because no `[share]` bucket is configured, say so plainly and point
   at `pond config schema` / the README's "Share a session" section — don't try to configure
   one yourself.

Publish the current Codex session to a public pond link with `pond share`.

Codex, unlike Claude Code, does not export a session-id env var, so resolve the
session from the newest rollout file on disk (the one this live session is
appending to):

```sh
newest="$(find "${CODEX_HOME:-$HOME/.codex}/sessions" -name 'rollout-*.jsonl' -type f -print0 \
  | xargs -0 ls -t 2>/dev/null | head -1)"
sid="$(basename "$newest" .jsonl \
  | grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')"
```

That trailing UUID is exactly the `session_meta.id` pond's `codex-cli` adapter
reads into `Session.id`, so it's the id `pond share` expects.

Then:

1. Run `pond sync codex-cli -q` so anything not yet in the store is current
   (this session's last turns may not be ingested yet).
2. Tell the user, plainly: this publishes the ENTIRE transcript (every message,
   tool call, and result — no redaction) to a public URL anyone with the link
   can open. Ask for explicit confirmation before continuing.
3. Once confirmed, run `pond share "$sid" --yes` (no `--open`) and report the
   printed URL back to the user.
4. If `$sid` came back empty, say you couldn't resolve the current session and
   stop — don't guess an id.
5. If `pond share` fails because no `[share]` bucket is configured, say so
   plainly and point at `pond config schema` / the README's "Share a session"
   section — don't try to configure one yourself.

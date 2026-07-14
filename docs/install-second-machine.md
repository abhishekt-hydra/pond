# Set up a second machine against your existing bucket

You already have pond running somewhere, backing up sessions to your own S3-compatible
bucket. On a new machine you want the same thing, fast: install pond, point it at that
same bucket, and start backing up this machine's sessions into it too - no embeddings,
just plain session capture. This is that flow, end to end.

## Why "no embeddings" needs nothing special

`pond sync` is a cheap message backup by default: it writes every new session and message,
including null vectors, and never downloads the ~500 MB embedding model or touches the
GPU. That's not a mode you opt into - it's `[embeddings].embed_on_sync = false`, which is
already the built-in default (`src/config.rs`). Embedding only happens two ways:

- `pond optimize` (or `pond optimize --only embed`), run manually.
- Setting `embed_on_sync = true` in config, which makes `pond sync` embed inline. This
  applies to scheduled syncs too: `pond schedule` just runs `pond sync -q --no-wait`, so
  a scheduled tick embeds only if you've turned `embed_on_sync` on.

Neither of those is part of this flow. `pond sync` on its own is the "session backup, no
embeddings" mode you want, unconditionally. Full-text search over the new sessions works
immediately either way; semantic (vector) search over them fills in once you later run
`pond optimize`.

## Why the same bucket is safe

`pond sync` is idempotent and content-addressed - it diffs what's already in the store
against what's on disk and only writes what's missing. Pointing a second machine at the
bucket your first machine already uses doesn't overwrite or duplicate anything; it just
adds this machine's sessions alongside the ones already there. Both machines can sync into
the same bucket independently (including at the same time - Lance's OCC commit protocol
handles concurrent writers).

## Steps

### 1. Install the CLI

Pick one:

```sh
brew install tenequm/tap/pond          # Homebrew
cargo install pond-db                  # crates.io (installs the `pond` command)
```

Or, from a checkout of this repo, use the installer script, which also places the config
for you (step 3 covers what it does with the config):

```sh
scripts/install-pond.sh
```

Pass `--skip-build` if `pond` is already on `PATH` and you only want the config step;
`--config=<file>` to supply an already-filled-in config instead of the template;
`--force` to overwrite an existing `config.toml`.

### 2. Set your credentials as environment variables

Credentials never go in the shared config file - they come from env vars, so the config
itself is safe to copy, paste into chat, or commit to a private dotfiles repo. pond's
`POND_*` env mirror maps these onto the catch-all `[creds.default]` credential set:

```sh
export POND_CREDS_DEFAULT_ACCESS_KEY_ID="..."
export POND_CREDS_DEFAULT_SECRET_ACCESS_KEY="..."

# Only if your bucket needs them:
export POND_CREDS_DEFAULT_REGION="..."
export POND_CREDS_DEFAULT_VIRTUAL_HOSTED_STYLE_REQUEST="true"
```

Add them to your shell profile (`~/.zshrc`, `~/.bashrc`) or a secrets manager - not to
`config.toml`. Precedence is CLI flag > `POND_*` env > config file > the ambient cloud
credential chain, so these env vars win over anything (or nothing) in the file.

### 3. Copy and edit the config

The portable unit is one file: `config.toml`, resolved at
`${XDG_CONFIG_HOME:-$HOME/.config}/pond/config.toml` (or `.pond.toml` in the current
directory with no `HOME`/`XDG_CONFIG_HOME`).

Use [`config.template.toml`](../config.template.toml) as the starting point - it has no
secrets in it, only the bucket URL, adapters, and non-secret settings. `install-pond.sh`
copies it there for you if you don't pass `--config`. Either way, edit one line:

```toml
[storage]
path = "s3+https://<host>/<bucket>/<prefix>"   # same bucket as your other machine
```

The template also enables both filesystem adapters pond ships:

```toml
[adapters.claude-code]
enabled = true
path = "~/.claude/projects"

[adapters.codex-cli]
enabled = true
path = "~/.codex/sessions"
```

Edit `path` only if this machine's install lives somewhere non-default (e.g. a custom
`CLAUDE_CONFIG_DIR`). Disable a section (`enabled = false`) if this machine doesn't run
that tool.

For the fully-annotated reference of every key (including ones this template leaves
commented out - `[search]`, `[maintenance]`, `[runtime]`, `[share]`), run:

```sh
pond config schema
```

### 4. Verify the bucket is reachable

```sh
pond storage check
```

This parses the configured URL, resolves credentials, and does an end-to-end conditional
put/read/delete against the bucket (the same OCC primitive Lance's commit protocol needs).
It exits non-zero with a specific reason if anything's wrong: `1` I/O error (network/DNS/
bucket unreachable), `2` parse error, `3` no credentials found, `4` auth failed, `5` OCC
unsupported by the endpoint. Fix whatever it reports before moving on - a working `pond
sync` depends on this succeeding first.

### 5. Run the first backup

```sh
pond sync
```

This ingests every enabled adapter's sessions from this machine, writes them into the
shared bucket, and updates the full-text index - with null vectors, per the "no
embeddings" behavior above. Re-running `pond sync` any time after (manually, via `pond
schedule`, or via `pond watch` for continuous backup) only picks up what's new.

Once this machine's sessions have landed, `pond search` and any MCP client (`pond mcp` /
`pond serve --transport stdio`) see the merged history from both machines - one store,
searchable from either side.

## What you're deliberately NOT doing

- Not running `pond init`: `init` is the interactive wizard for a *first* machine setting
  up its own bucket from scratch (it can also register MCP and a sync schedule). This
  flow is a *known-good, existing* bucket - editing and copying one file is faster and
  makes zero decisions the wizard would otherwise ask about. You can still run `pond init`
  afterward if you also want MCP registration or a schedule; it's idempotent and won't
  clobber the config this flow wrote (a config with a valid `[storage].path` and enabled
  adapters is already "set up" from `init`'s point of view).
- Not setting `embed_on_sync = true` or running `pond optimize`: this flow is
  backup-only. Turn embeddings on later, on any machine sharing the bucket, if you want
  semantic search over the full corpus - it isn't a per-machine choice.

## Troubleshooting

- **`pond storage check` fails with "no credentials"**: the `POND_CREDS_DEFAULT_*` env
  vars aren't set in this shell (or weren't exported before pond ran). Confirm with `pond
  config show`, which prints each field's source (`cli`/`env`/`file`/`default`) alongside
  its redacted value.
- **`pond sync` says no adapters are enabled**: the config wasn't copied, or both
  `[adapters.*]` sections got disabled. Re-check `${XDG_CONFIG_HOME:-$HOME/.config}/pond/config.toml`.
- **Existing `config.toml` wasn't replaced**: `scripts/install-pond.sh` refuses to
  overwrite one without `--force`, by design - it won't clobber a working setup on a
  machine that already has pond configured.

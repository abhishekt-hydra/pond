#!/usr/bin/env bash
# Install pond on a second machine and point it at an existing bucket - the
# "copy one config and go" flow: no embeddings, just more sessions landing in
# the same store your other machine already backs up to.
#
#   install-pond.sh [--config <file>] [--skip-build] [--force]
#
# 1. Installs the `pond` CLI: `cargo install --path .` from this checkout
#    (skip with --skip-build if `pond` is already on PATH).
# 2. Places a config.toml at the resolved config path
#    (${XDG_CONFIG_HOME:-$HOME/.config}/pond/config.toml): either the file
#    passed via --config (already filled in with your bucket), or this repo's
#    config.template.toml as a starting point. Never overwrites an existing
#    config.toml unless --force is passed.
# 3. Prints the POND_CREDS_DEFAULT_* environment variables still needed -
#    credentials never go in the copied config file.
#
# This script does not touch the network and does not run `pond sync` - see
# docs/install-second-machine.md for the walkthrough after it finishes.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_SRC=""
SKIP_BUILD=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --config=*)   CONFIG_SRC="${arg#*=}" ;;
    --config)     echo "error: use --config=<file>" >&2; exit 2 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --force)      FORCE=1 ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "error: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

# ---- 1. install the CLI ----------------------------------------------------
if [[ "$SKIP_BUILD" == 1 ]]; then
  if ! command -v pond >/dev/null 2>&1; then
    echo "error: --skip-build passed but 'pond' is not on PATH" >&2
    exit 1
  fi
  echo "using existing pond: $(command -v pond)"
else
  if [[ ! -f "$REPO_DIR/Cargo.toml" ]]; then
    echo "error: $REPO_DIR/Cargo.toml not found - run this from a pond checkout, or pass --skip-build" >&2
    exit 1
  fi
  echo "building and installing pond (cargo install --path .)..."
  (cd "$REPO_DIR" && cargo install --path .)
  if ! command -v pond >/dev/null 2>&1; then
    echo "error: cargo install finished but 'pond' is not on PATH - check that ~/.cargo/bin is in PATH" >&2
    exit 1
  fi
  echo "installed: $(command -v pond)"
fi

# ---- 2. place config.toml --------------------------------------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pond"
CONFIG_DEST="$CONFIG_DIR/config.toml"

if [[ -z "$CONFIG_SRC" ]]; then
  CONFIG_SRC="$REPO_DIR/config.template.toml"
fi
if [[ ! -f "$CONFIG_SRC" ]]; then
  echo "error: config source '$CONFIG_SRC' not found" >&2
  exit 1
fi

if [[ -f "$CONFIG_DEST" && "$FORCE" != 1 ]]; then
  echo "warning: $CONFIG_DEST already exists - not overwriting (pass --force to replace it)" >&2
else
  mkdir -p "$CONFIG_DIR"
  cp "$CONFIG_SRC" "$CONFIG_DEST"
  echo "config written: $CONFIG_DEST (from $CONFIG_SRC)"
  if [[ "$CONFIG_SRC" == "$REPO_DIR/config.template.toml" ]]; then
    echo "  -> edit [storage].path in that file to point at your bucket before syncing"
  fi
fi

# ---- 3. credentials ---------------------------------------------------------
cat <<'EOF'

Set credentials as environment variables - never put them in config.toml.
Add these to your shell profile (~/.zshrc, ~/.bashrc) or a secrets manager:

  export POND_CREDS_DEFAULT_ACCESS_KEY_ID="..."
  export POND_CREDS_DEFAULT_SECRET_ACCESS_KEY="..."

Optional, only if your bucket needs them:

  export POND_CREDS_DEFAULT_REGION="..."
  export POND_CREDS_DEFAULT_VIRTUAL_HOSTED_STYLE_REQUEST="true"

Next steps:
  pond storage check   # verify the bucket is reachable with these credentials
  pond sync            # first backup - no embeddings, sync is idempotent
EOF

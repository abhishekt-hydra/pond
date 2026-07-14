#!/usr/bin/env bash
# Build pond from this working tree and install it over the brew-managed
# binary, so `pond` on PATH reflects local (including uncommitted) changes
# instead of the last tagged release from tenequm/homebrew-tap.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

POND_BIN="$(command -v pond || true)"
if [[ -z "$POND_BIN" ]]; then
  echo "error: no 'pond' on PATH - install the brew formula first (tenequm/tap/pond)" >&2
  exit 1
fi

# Resolve past the brew-managed symlink (opt/bin -> Cellar/<version>/bin) so
# we overwrite the real binary, not the symlink itself.
TARGET="$(readlink -f "$POND_BIN" 2>/dev/null || readlink "$POND_BIN" || echo "$POND_BIN")"
case "$TARGET" in
  /*) ;;
  *) TARGET="$(dirname "$POND_BIN")/$TARGET" ;;
esac

echo "building release binary from $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))..."
if ! git diff --quiet; then
  echo "note: working tree has uncommitted changes - building those too"
fi
cargo build --release

echo "installing target/release/pond -> $TARGET"
# Atomic replace: cp-in-place reuses the destination's inode, and macOS ties
# its code-signing trust cache to that inode - overwriting a binary that was
# ever loaded/execed at this path leaves the new bytes killed with SIGKILL
# (exit 137) on every future exec. Writing to a temp file and renaming it
# into place gives a fresh inode instead.
TMP="${TARGET}.new.$$"
cp target/release/pond "$TMP"
chmod +x "$TMP"
mv -f "$TMP" "$TARGET"

echo "done: $("$TARGET" --version)"

#!/usr/bin/env bash
# Re-extract the GDScript compiler from libriscv/godot-sandbox.
#
#   ./scripts/sync_upstream.sh            # latest master
#   ./scripts/sync_upstream.sh <commit>   # a specific commit
#
# Upstream paths are preserved, so this is a copy. The one local change is in
# src/gdscript/compiler/CMakeLists.txt (see UPSTREAM.md); the script reports it
# so it can be re-applied by hand.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
REF=${1:-master}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone --quiet https://github.com/libriscv/godot-sandbox.git "$WORK/godot-sandbox"
git -C "$WORK/godot-sandbox" checkout --quiet "$REF"
SHA=$(git -C "$WORK/godot-sandbox" rev-parse HEAD)

rm -rf "$REPO/src/gdscript/compiler"
mkdir -p "$REPO/src/gdscript"
cp -R "$WORK/godot-sandbox/src/gdscript/compiler" "$REPO/src/gdscript/compiler"
rm -rf "$REPO/src/gdscript/compiler/Testing"
cp "$WORK/godot-sandbox/src/syscalls.h" "$REPO/src/syscalls.h"
cp "$WORK/godot-sandbox/.clang-format" "$REPO/.clang-format"

sed -i.bak -e "s/^| Commit | \`.*\` |$/| Commit | \`$SHA\` |/" \
           -e "s/^| Synced | .* |$/| Synced | $(date +%F) |/" "$REPO/UPSTREAM.md"
rm -f "$REPO/UPSTREAM.md.bak"

echo "Synced to $SHA"
echo "Re-apply the local CMakeLists.txt change described in UPSTREAM.md, then build."

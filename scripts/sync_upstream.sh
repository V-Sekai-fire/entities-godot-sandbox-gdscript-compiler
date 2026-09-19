#!/usr/bin/env bash
# Re-extract the GDScript compiler from libriscv/godot-sandbox.
#
#   ./scripts/sync_upstream.sh            # latest master
#   ./scripts/sync_upstream.sh <commit>   # a specific commit
#
# Upstream paths are preserved, so the compiler sources are a copy. The test
# suite is not: it was converted to doctest and witness-cpp here, so this script
# leaves src/gdscript/compiler/tests alone and prints which test files upstream
# has changed since the recorded commit. Those changes are ported by hand.
# The other local change is in src/gdscript/compiler/CMakeLists.txt; both are
# described in UPSTREAM.md.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
REF=${1:-master}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone --quiet https://github.com/libriscv/godot-sandbox.git "$WORK/godot-sandbox"
git -C "$WORK/godot-sandbox" checkout --quiet "$REF"
SHA=$(git -C "$WORK/godot-sandbox" rev-parse HEAD)

PREVIOUS=$(sed -n 's/^| Commit | `\(.*\)` |$/\1/p' "$REPO/UPSTREAM.md")

# The converted test suite stays; everything else is replaced.
mv "$REPO/src/gdscript/compiler/tests" "$WORK/tests-ours"
rm -rf "$REPO/src/gdscript/compiler"
mkdir -p "$REPO/src/gdscript"
cp -R "$WORK/godot-sandbox/src/gdscript/compiler" "$REPO/src/gdscript/compiler"
rm -rf "$REPO/src/gdscript/compiler/Testing" "$REPO/src/gdscript/compiler/tests"
mv "$WORK/tests-ours" "$REPO/src/gdscript/compiler/tests"
cp "$WORK/godot-sandbox/src/syscalls.h" "$REPO/src/syscalls.h"
cp "$WORK/godot-sandbox/.clang-format" "$REPO/.clang-format"

sed -i.bak -e "s/^| Commit | \`.*\` |$/| Commit | \`$SHA\` |/" \
           -e "s/^| Synced | .* |$/| Synced | $(date +%F) |/" "$REPO/UPSTREAM.md"
rm -f "$REPO/UPSTREAM.md.bak"

echo "Synced to $SHA"
echo "Re-apply the local CMakeLists.txt change described in UPSTREAM.md, then build."

if [ -n "$PREVIOUS" ] && [ "$PREVIOUS" != "$SHA" ]; then
	echo
	echo "Upstream test files changed since ${PREVIOUS}; port these by hand:"
	git -C "$WORK/godot-sandbox" diff --name-only "$PREVIOUS" "$SHA" \
		-- src/gdscript/compiler/tests || echo "  (could not diff: $PREVIOUS not in the clone)"
fi

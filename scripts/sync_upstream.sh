#!/usr/bin/env bash
# Re-extract the GDScript compiler from libriscv/godot-sandbox.
#
#   ./scripts/sync_upstream.sh                      # latest master
#   ./scripts/sync_upstream.sh <commit>             # a specific commit
#   ./scripts/sync_upstream.sh --reapply [<commit>] # and carry the local patches over
#
# Upstream paths are preserved, so the compiler sources are upstream's files
# plus the local patches UPSTREAM.md lists. Before it replaces anything, the
# script compares every committed file it would overwrite with the upstream
# commit UPSTREAM.md records. A file that differs carries a local patch, so
# the script stops and names it rather than copying over it. With --reapply it
# takes the new upstream files and carries each local patch onto them with a
# three-way merge (git merge-file), leaving conflict markers where upstream
# changed the same lines.
#
# The test suite is not a copy: it was converted to doctest and witness-cpp
# here, so this script leaves src/gdscript/compiler/tests alone and prints
# which test files upstream has changed since the recorded commit. Those
# changes are ported by hand.
set -euo pipefail

REAPPLY=0
if [ "${1:-}" = "--reapply" ]; then
	REAPPLY=1
	shift
fi
REPO=$(cd "$(dirname "$0")/.." && pwd)
REF=${1:-master}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
UPSTREAM_GIT="$WORK/godot-sandbox"
EXTRACTED=(src/gdscript/compiler src/syscalls.h .clang-format)

PREVIOUS=$(sed -n 's/^| Commit | `\(.*\)` |$/\1/p' "$REPO/UPSTREAM.md")
if [ -z "$PREVIOUS" ]; then
	echo "UPSTREAM.md records no upstream commit, so local patches cannot be told apart." >&2
	exit 1
fi
if ! git -C "$REPO" diff --quiet HEAD -- "${EXTRACTED[@]}" ||
	[ -n "$(git -C "$REPO" ls-files --others --exclude-standard -- "${EXTRACTED[@]}")" ]; then
	echo "Commit or stash the changes under ${EXTRACTED[*]} first; a sync replaces those files." >&2
	exit 1
fi

# Byte-exact upstream files: no line-ending conversion, whatever the host's git config.
git -c core.autocrlf=false clone --quiet --no-checkout \
	https://github.com/libriscv/godot-sandbox.git "$UPSTREAM_GIT"
git -C "$UPSTREAM_GIT" config core.autocrlf false

# extract <dir>: the files this repository takes from the checked-out commit.
extract() {
	mkdir -p "$1/src/gdscript"
	cp -R "$UPSTREAM_GIT/src/gdscript/compiler" "$1/src/gdscript/compiler"
	rm -rf "$1/src/gdscript/compiler/Testing" "$1/src/gdscript/compiler/tests"
	# src/syscalls.h is a symlink upstream; what is kept is its target. A
	# checkout without symlink support (Windows) leaves the target path in a
	# plain file, so follow that by hand.
	local syscalls="$UPSTREAM_GIT/src/syscalls.h"
	if [ ! -L "$syscalls" ] && [ "$(git -C "$UPSTREAM_GIT" ls-tree HEAD src/syscalls.h | cut -c1-6)" = 120000 ]; then
		syscalls="$UPSTREAM_GIT/src/$(cat "$syscalls")"
	fi
	cp -L "$syscalls" "$1/src/syscalls.h"
	cp "$UPSTREAM_GIT/.clang-format" "$1/.clang-format"
}

if ! git -C "$UPSTREAM_GIT" checkout --quiet "$PREVIOUS"; then
	echo "The recorded upstream commit $PREVIOUS is not in libriscv/godot-sandbox." >&2
	exit 1
fi
extract "$WORK/base"
git -C "$UPSTREAM_GIT" checkout --quiet "$REF"
SHA=$(git -C "$UPSTREAM_GIT" rev-parse HEAD)
extract "$WORK/new"

# The local patches: every committed file that differs from the recorded
# upstream commit, found by comparing rather than read from a list, so none
# is missed. Blob ids are compared, so the checkout's line endings do not count.
PATCHED=()
mkdir -p "$WORK/ours"
while IFS=$'\t' read -r meta f; do
	blob=${meta##* }
	if [ ! -e "$WORK/base/$f" ] || [ "$blob" != "$(git hash-object --no-filters "$WORK/base/$f")" ]; then
		PATCHED+=("$f")
		mkdir -p "$WORK/ours/$(dirname "$f")"
		git -C "$REPO" cat-file blob "$blob" > "$WORK/ours/$f"
	fi
done < <(git -C "$REPO" ls-tree -r HEAD -- "${EXTRACTED[@]}" | grep -v $'\tsrc/gdscript/compiler/tests/')
while IFS= read -r f; do
	[ -n "$(git -C "$REPO" ls-tree HEAD -- "$f")" ] || PATCHED+=("$f")
done < <(cd "$WORK/base" && find src .clang-format -type f | sort)

if [ ${#PATCHED[@]} -gt 0 ] && [ $REAPPLY -eq 0 ]; then
	echo "Not syncing: these files differ from upstream $PREVIOUS," >&2
	echo "so they carry local patches (see UPSTREAM.md) that copying $REF over them would drop:" >&2
	printf '  %s\n' "${PATCHED[@]}" >&2
	echo "Re-run with --reapply to carry them onto $REF with a three-way merge." >&2
	exit 1
fi

# The converted test suite stays; everything else is replaced.
mv "$REPO/src/gdscript/compiler/tests" "$WORK/tests-ours"
rm -rf "$REPO/src/gdscript/compiler"
cp -R "$WORK/new/src/gdscript/compiler" "$REPO/src/gdscript/compiler"
mv "$WORK/tests-ours" "$REPO/src/gdscript/compiler/tests"
cp "$WORK/new/src/syscalls.h" "$REPO/src/syscalls.h"
cp "$WORK/new/.clang-format" "$REPO/.clang-format"

# Carry each local patch from the recorded commit onto the new one.
: > "$WORK/empty"
CONFLICTS=()
for f in ${PATCHED[@]+"${PATCHED[@]}"}; do
	if [ ! -e "$WORK/ours/$f" ]; then
		rm -f "$REPO/$f"
		echo "  kept deleted: $f"
		continue
	fi
	base="$WORK/base/$f"
	[ -e "$base" ] || base="$WORK/empty"
	theirs="$WORK/new/$f"
	[ -e "$theirs" ] || theirs="$WORK/empty"
	mkdir -p "$REPO/$(dirname "$f")"
	cp "$WORK/ours/$f" "$REPO/$f"
	if git merge-file -L "local" -L "upstream ${PREVIOUS:0:12}" -L "upstream ${SHA:0:12}" \
		"$REPO/$f" "$base" "$theirs"; then
		echo "  re-applied: $f"
	else
		CONFLICTS+=("$f")
	fi
done

sed -i.bak -e "s/^| Commit | \`.*\` |$/| Commit | \`$SHA\` |/" \
           -e "s/^| Synced | .* |$/| Synced | $(date +%F) |/" "$REPO/UPSTREAM.md"
rm -f "$REPO/UPSTREAM.md.bak"

echo "Synced to $SHA"
if [ ${#CONFLICTS[@]} -gt 0 ]; then
	echo
	echo "These local patches conflict with upstream; resolve the markers, then build:"
	printf '  %s\n' "${CONFLICTS[@]}"
fi
if [ ${#PATCHED[@]} -gt 0 ]; then
	echo "Then update UPSTREAM.md's local patch table for any patch upstream now carries."
fi

if [ "$PREVIOUS" != "$SHA" ]; then
	echo
	echo "Upstream test files changed since ${PREVIOUS}; port these by hand:"
	git -C "$UPSTREAM_GIT" diff --name-only "$PREVIOUS" "$SHA" \
		-- src/gdscript/compiler/tests || echo "  (could not diff: $PREVIOUS not in the clone)"
fi
[ ${#CONFLICTS[@]} -eq 0 ] || exit 2

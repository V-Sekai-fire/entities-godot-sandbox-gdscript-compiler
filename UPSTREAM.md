# Upstream

The compiler sources in `src/` are extracted from
[libriscv/godot-sandbox](https://github.com/libriscv/godot-sandbox) and carry
the local patches listed below.

| | |
| --- | --- |
| Commit | `b43ed1619abc12a669c59cb0aa25c4582873a7b9` |
| Synced | 2026-10-01 |

## What is extracted

| This repository | godot-sandbox |
| --- | --- |
| `src/gdscript/compiler/` | `src/gdscript/compiler/` |
| `src/syscalls.h` | `src/syscalls.h` (a symlink upstream; its target's content is kept) |
| `.clang-format` | `.clang-format` |

Upstream paths are kept as-is so a sync is a copy plus the local patches, not
a port. `globals.cpp` and `syscall_numbers.h` include `../../syscalls.h`, which
only resolves with that layout.

The compiler sources do not match the `.clang-format` they ship beside, and
upstream does not run it over them, so this repository's clang-format hook
covers `src/gdscript/compiler/tests` only. Formatting them would turn every
sync into a merge.

## Re-syncing

```bash
./scripts/sync_upstream.sh                      # latest master
./scripts/sync_upstream.sh <commit>             # a specific commit
./scripts/sync_upstream.sh --reapply [<commit>] # and carry the local patches over
```

Before it replaces anything, the script compares every committed file it would
overwrite with the upstream commit recorded above. A file that differs carries
a local patch, so without `--reapply` the script stops and lists those files
instead of copying over them. With `--reapply` it takes the new upstream files
and carries each local patch onto them with a three-way merge, leaving conflict
markers where upstream changed the same lines, and exits 2 if any are left. It
then rewrites the commit recorded here. Update the table below for any patch
that upstream now carries or that was dropped.

## Local patches

Every file the script would find is listed here, by its path under
`src/gdscript/compiler/`. The test suite is not: it is this repository's own
(see below).

| File | Patch | Commits |
| --- | --- | --- |
| `CMakeLists.txt` | Links doctest's main (`gdscript_test_main`) into every test instead of upstream's `assert()` and `-UNDEBUG`; drops `test_api_tables`, which needs `ext/godot-cpp`, not part of this extraction; registers `test_extensions_gate`, `test_gdscript_syntax`, `test_class_dispatch` | 4682d72, ecd7bf5, 194144f, be73eb0, b9ff6bb |
| `compiler.h`, `compiler.cpp`, `lexer.h`, `lexer.cpp`, `tool_check.h`, `dump_ir.cpp`, `gdscript_to_riscv.cpp` | `CompilerOptions::extensions` and `--extensions`, off by default: `struct`, `trait`, `uses`, `switch`, `?` types and `??`/`?.` are SafeGDScript extensions, and with the gate closed the keywords lex as identifiers; the script bases a native class imports are gated the same way | 194144f, f4a1f72 |
| `source_model.h`, `source_model.cpp` | `ANALYZE_EXTENSIONS` (and `ANALYZE_ALL` widened to `0x3f`); warnings and errors capped separately; a bare call inside a class resolves to the class's method | 194144f, 3f6100c |
| `parser.h`, `parser.cpp` | Union types, `@test` and `@requires_host_hook` behind the gate; nested classes hoisted to file scope; expression statements; compound assignment into call results; class field getters; operators after a cast (checked in `parse_unary` before upstream's prefix `not`); file-level strings; `:=` recorded on declarations; a keyword after `.` or `?.` is a member name; `pass` as a class-body statement | 194144f, be73eb0, 476b98f, 42d450b, 3f6100c, f4a1f72, census |
| `ast.h` | `VarDeclStmt::inferred` | f4a1f72 |
| `codegen.h`, `codegen.cpp` | Sealed class instances (`@seal`) and method dispatch on untyped receivers; field getters; class names as values (`@class:Name`) and their `.new()`, the seal and class-value objects created at startup only when some code reads them; a script-class local accepting null without `?`; an Array assigned to a packed array; untyped variables typed as GDScript types them; non-folding class constants other than `preload()`; a lambda in a member initializer is lifted instead of dropped | b9ff6bb, 476b98f, 0052a97, 42d450b, f4a1f72, e1a73fd, census |

The `.def` tables are taken as given: upstream regenerates them with
`test_api_tables`, which this extraction cannot run.

**The test suite.** `src/gdscript/compiler/tests` was converted from upstream's
`assert()`-and-`main()` style to doctest, with property and falsifiability tests
on top of it (see README). A sync therefore leaves that directory alone and
prints the upstream test files that changed, so they can be ported by hand.

The differential tests (`test_differential`, `test_profiling`,
`test_instances` and the rest that run real RISC-V code) need libriscv at
`ext/libriscv`, which is a submodule here as it is upstream. Without it the
build skips them and says so.

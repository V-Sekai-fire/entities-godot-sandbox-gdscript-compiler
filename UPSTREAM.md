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
| `CMakeLists.txt` | Links doctest's main (`gdscript_test_main`) into every test instead of upstream's `assert()` and `-UNDEBUG`; drops `test_api_tables`, which needs `ext/godot-cpp`, not part of this extraction; registers `test_extensions_gate`, `test_gdscript_syntax`, `test_class_dispatch`, `test_packed_regions`, `test_rewrite`; builds `rewrite.cpp`; `GDSCRIPT_FAST_ARRAYS` and `GDSCRIPT_REWRITE` (both `ON`) set the defaults of the two options below, so the whole suite can be run with either off | 4682d72, ecd7bf5, 194144f, be73eb0, b9ff6bb, ceb49bc, 878b16b |
| `compiler.h`, `compiler.cpp`, `lexer.h`, `lexer.cpp`, `tool_check.h`, `dump_ir.cpp`, `gdscript_to_riscv.cpp` | `CompilerOptions::extensions` and `--extensions`, off by default: `struct`, `trait`, `uses`, `switch`, `?` types and `??`/`?.` are SafeGDScript extensions, and with the gate closed the keywords lex as identifiers; the script bases a native class imports are gated the same way | 194144f, f4a1f72 |
| `source_model.h`, `source_model.cpp` | `ANALYZE_EXTENSIONS` (and `ANALYZE_ALL` widened to `0x3f`); warnings and errors capped separately; a bare call inside a class resolves to the class's method | 194144f, 3f6100c |
| `parser.h`, `parser.cpp` | Union types, `@test` and `@requires_host_hook` behind the gate; nested classes hoisted to file scope; expression statements; compound assignment into call results; class field getters; operators after a cast (checked in `parse_unary` before upstream's prefix `not`); file-level strings; `:=` recorded on declarations | 194144f, be73eb0, 476b98f, 42d450b, 3f6100c, f4a1f72 |
| `ast.h` | `VarDeclStmt::inferred` | f4a1f72 |
| `compiler.h`, `compiler.cpp`, `dump_ir.cpp`, `gdscript_to_riscv.cpp` | `CompilerOptions::fast_arrays` (`--fast-arrays` / `--no-fast-arrays`) and `CompilerOptions::rewrite` (`--rewrite` / `--no-rewrite`), both on; `--emit-rewritten <path>`; the rewritten text compiled with the authored line numbers, and the authored text compiled instead if it ever did not compile; `compile_to_c` turns both off | ceb49bc, 878b16b |
| `rewrite.h`, `rewrite.cpp` | New: the GDScript rewrite of loops over packed arrays (see below) | 878b16b |
| `ir_opcodes.def` | `PACKED_DATA`, `PACKED_SIZE`, `PACKED_IDENTITY`, `PACKED_INDEX` (a branch), `PACKED_GET`, `PACKED_SET` | ceb49bc |
| `ir_optimizer.cpp`, `ir_interpreter.cpp`, `c_codegen.cpp` | The packed opcodes in their dispatch (constant folding: only the destination changes; the interpreter and the C backend refuse them, as they refuse host calls); `PACKED_INDEX` is never removed as a branch to the next instruction | ceb49bc |
| `riscv_codegen.h`, `riscv_codegen.cpp` | A loop scope is released only when the pass left something to release: inline constructors and inline member access allocate nothing, a call's dirty bit ignores an inline answer (a Color, a vector), and residency leaves loop scopes their dirty registers. The packed opcodes and `ECALL_PACKED_ACQUIRE` / `ECALL_PACKED_RELEASE` lowered; the descriptors in the frame | a82a23c, ceb49bc |
| `codegen.h`, `codegen.cpp` | Packed array regions (see below); under fast arrays a typed packed array's element read and `size()` are typed | ceb49bc |
| `../../syscalls.h` (`src/syscalls.h`) | `ECALL_PACKED_ACQUIRE` and `ECALL_PACKED_RELEASE` (`GAME_API_BASE + 67`, `+ 68`) and `PACKED_WRITTEN`; `ECALL_LAST` moves to `+ 69`. The addon's `program/cpp/docker/api/syscalls.h` must say the same | ceb49bc |
| `codegen.h`, `codegen.cpp` | Sealed class instances (`@seal`) and method dispatch on untyped receivers; field getters; class names as values (`@class:Name`) and their `.new()`, the seal and class-value objects created at startup only when some code reads them; a script-class local accepting null without `?`; an Array assigned to a packed array; untyped variables typed as GDScript types them; non-folding class constants other than `preload()` | b9ff6bb, 476b98f, 0052a97, 42d450b, f4a1f72, e1a73fd |

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

## Packed array regions and the loop rewrite

Two layers, each behind its own option and both on by default, make loops
over `Packed*Array`s stop paying a host call per element.

**Fast arrays** (`codegen.cpp`, "Packed array regions"). A loop that indexes
typed `Packed*Array` locals copies each of them into guest memory once
(`ECALL_PACKED_ACQUIRE`), reads and writes the copies with plain loads and
stores, and stores the written ones back into the same host arrays, in place,
when it leaves (`ECALL_PACKED_RELEASE`), so every reference to an array sees
what element-by-element access would have shown it. The loop is versioned:
guards at its entry (every acquire succeeds; no written copy shares its array
with another candidate) pick the copy loop or the original loop, kept as the
fallback. An index out of range repeats the access through the host, which
reports it as before. The copy loop's IR is scanned with each operand's type
and a candidate the host could reach behind its copy is dropped. A host error
or assert inside a region stores the copies from the addon's exception path.

The two calls are the addon's, not upstream's: they ship with the V-Sekai-fire
godot-sandbox fork's packed-bulk change (`src/sandbox_syscalls_packed.cpp`).
An addon without them answers the acquire with `-ENOSYS`, and every region
runs its fallback loop, so a new compiler is safe on an old addon.

**The rewrite** (`rewrite.h`). Before compiling, `for x in v` over a packed
array the loop cannot resize becomes an index walk (or, without fast arrays and
when the loop never writes `v`, a walk over `Array(v)`, fetched sixteen
elements a host call); an untyped `v` gets that walk under a `typeof` test with
the authored loop as the fallback; `while ... v.size() ...` reads the size once.
The rewritten text is GDScript and a build artifact (`--emit-rewritten`).

Prior art. JNI's `Get<Type>ArrayElements` / `Release<Type>ArrayElements`, whose
release modes are these: store and free (0), store and keep (`JNI_COMMIT`),
free without storing (`JNI_ABORT`, a copy nobody wrote); and
`GetPrimitiveArrayCritical`, whose region may not call back into Java -- here,
may not let the host reach an array behind its copy. wasm-bindgen copies a
`&[u8]` across the boundary once per call rather than per element. PEP 3118
hands out a buffer view in place of an element protocol. HotSpot C2's range
check elimination by loop predication versions a loop on guards at its entry,
as the copy loop is versioned here.

**Checked.** `test_packed_regions` (with the planted host-call test and its
failing control) and `test_rewrite` run in ctest. What the two layers compute
is checked in Godot against interpreted GDScript, in all four combinations of
the two options and with both rewritten texts run as GDScript:
`src/gdscript/compiler/tests/godot_packed/` holds those cases (aliasing, a
caller observing writes, the identity guard's fallback, out-of-range indices,
NaN payloads, every element type) and their runner.

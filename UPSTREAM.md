# Upstream

The compiler sources in `src/` are extracted verbatim from
[libriscv/godot-sandbox](https://github.com/libriscv/godot-sandbox).

| | |
| --- | --- |
| Commit | `ce6f6b843a81bd0e9737411227c79e04bf049c76` |
| Synced | 2026-09-19 |

## What is extracted

| This repository | godot-sandbox |
| --- | --- |
| `src/gdscript/compiler/` | `src/gdscript/compiler/` |
| `src/syscalls.h` | `src/syscalls.h` |
| `.clang-format` | `.clang-format` |

Upstream paths are kept as-is so a sync is a copy, not a patch. `globals.cpp`
and `syscall_numbers.h` include `../../syscalls.h`, which only resolves with
that layout.

## Re-syncing

```bash
./scripts/sync_upstream.sh          # latest master
./scripts/sync_upstream.sh <commit> # a specific commit
```

The script refreshes the files above and rewrites the commit recorded here.

## Local differences

`src/gdscript/compiler/CMakeLists.txt` drops one upstream test,
`test_api_tables`, which regenerates the `.def` tables from
`ext/godot-cpp/gdextension/extension_api.json`. That checkout is not part of
this extraction. Everything else in the file is upstream's.

The differential tests (`test_differential`, `test_profiling`,
`test_instances` and the rest that run real RISC-V code) need libriscv at
`ext/libriscv`, which is a submodule here as it is upstream. Without it the
build skips them and says so.

# entities-godot-sandbox-gdscript-compiler

A compiler from GDScript to RISC-V ELF programs that run as godot-sandbox guests.

## What it is for

It turns a script into a sandboxed guest program through its own IR, which has an optimizer, a
verifier and an interpreter used for differential testing against the generated code. The
sources are extracted from `libriscv/godot-sandbox`, and `UPSTREAM.md` records the commit they
track, the local patches and how to re-sync.

## Build and test

```sh
git clone --recurse-submodules https://github.com/V-Sekai-fire/entities-godot-sandbox-gdscript-compiler
cd entities-godot-sandbox-gdscript-compiler
pixi run test
```

`pixi.toml` pins the toolchain, so the build is the same on every host.

## Licence

BSD-3-Clause, as upstream; see `LICENSE`.

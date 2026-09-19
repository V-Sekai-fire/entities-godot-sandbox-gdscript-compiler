# GDScript to RISC-V Compiler

A GDScript compiler that produces RISC-V ELF binaries, executable in Godot
Sandbox. The sources are extracted from
[libriscv/godot-sandbox](https://github.com/libriscv/godot-sandbox); see
[UPSTREAM.md](UPSTREAM.md) for the commit this tracks and how to re-sync.

## Layout

Upstream paths are kept, so the compiler lives at
`src/gdscript/compiler/` and the syscall numbers it emits against at
`src/syscalls.h`.

### Frontend
- **lexer**, **token**, **parser**, **ast** — GDScript source to AST
- **source_model**, **function_signature**, **property_signature**,
  **traits**, **globals** — name resolution, signatures, trait conformance
- **codegen** — AST to IR
- **ir**, **ir_optimizer**, **ir_verifier**, **ir_interpreter** — IR, its
  optimization passes, a verifier and an interpreter for differential testing
- **c_codegen** — the C backend, with type inference, unboxing and a typed ABI

### RISC-V backend
- **riscv_codegen**, **riscv_globals**, **riscv_profiling**, **riscv_debug** —
  IR to RISC-V machine code
- **register_allocator** — register allocation
- **elf_builder** — RISC-V ELF binary output
- **line_table**, **debug_layout**, **gdsmeta** — debug info and metadata

## Building

```bash
git clone --recurse-submodules https://github.com/V-Sekai-fire/entities-godot-sandbox-gdscript-compiler
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build --parallel
cd build && ctest --output-on-failure
```

`ext/libriscv` is a submodule. Without it the build skips the tests that run
generated code on a real RISC-V machine (`test_differential`, `test_profiling`,
`test_instances` and the rest) and says so at configure time.

Two options are worth knowing:

| Option | Default | Effect |
| --- | --- | --- |
| `GDSCRIPT_BUILD_RISCV` | `ON` | `OFF` builds only the frontend and its IR, for a native backend |
| `DOUBLE_PRECISION` | `OFF` | Match a Godot built with `real_t = double` |

## API usage

```cpp
#include <compiler.h>
using namespace gdscript;

Compiler compiler;
CompilerOptions options;
options.output_elf = true;

std::vector<uint8_t> elf_data = compiler.compile(R"(
func sum(n):
    var total = 0
    var i = 0
    while i <= n:
        total += i
        i += 1
    return total
)", options);

if (elf_data.empty()) {
    std::cerr << "Compilation failed: " << compiler.get_error() << std::endl;
}
```

## Pipeline

1. **Lexing**: GDScript source to tokens
2. **Parsing**: tokens to AST
3. **Code generation**: AST to IR
4. **Optimization**: IR optimization passes
5. **RISC-V codegen**: IR to RISC-V machine code
6. **ELF building**: machine code to an executable ELF binary

## Debug tools

### dump_ir
Inspect the IR generated from GDScript:
```bash
cat script.gd | ./dump_ir
cat script.gd | ./dump_ir --no-optimize
cat script.gd | ./dump_ir --codegen
```

### gdscript_to_riscv
Compile and disassemble:
```bash
cat script.gd | ./gdscript_to_riscv
cat script.gd | ./gdscript_to_riscv -f function_name
```

## License

BSD 3-Clause, as the original godot-sandbox repository. See [LICENSE](LICENSE).

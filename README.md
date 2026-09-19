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

`ext/libriscv`, `ext/doctest` and `ext/witness-cpp` are submodules. Without
libriscv the build skips the tests that run generated code on a real RISC-V
machine (`test_differential`, `test_profiling`, `test_instances` and the rest)
and says so at configure time.

Two options are worth knowing:

| Option | Default | Effect |
| --- | --- | --- |
| `GDSCRIPT_BUILD_RISCV` | `ON` | `OFF` builds only the frontend and its IR, for a native backend |
| `DOUBLE_PRECISION` | `OFF` | Match a Godot built with `real_t = double` |

## Tests

The suite is [doctest](https://github.com/doctest/doctest), and property tests
are [witness-cpp](https://github.com/V-Sekai-fire/repository-witness-cpp). Every
subject is covered three ways:

| Kind | What it is | Where |
| --- | --- | --- |
| Unit | A named case with a written-down input and expected result | Throughout |
| Property | `PROP_HOLDS`: a statement that has to hold for every program the generator can produce | `test_lexer`, `test_operators`, `test_strings`, `test_containers`, `test_dictionaries`, `test_ir_optimizer`, `test_opt_invariance`, `test_fuzz` |
| Falsifiability | `PROP_FALSIFIABLE`: a statement that is false on purpose, which the same generator and ladder have to catch | Beside every property |

The third is what keeps the second honest. A property tested with a generator
that only reaches trivial programs passes while checking nothing; its
falsifiability case fails in exactly that situation, because a generator that
cannot reach a counterexample cannot find the planted one either. Both macros
live in `src/gdscript/compiler/tests/property_support.h`.

Running one binary, or one case:

```bash
./build/src/gdscript/compiler/test_operators
./build/src/gdscript/compiler/test_operators -ts="*property*"
./build/src/gdscript/compiler/test_operators --list-test-cases
```

doctest owns `argv`, so the fuzzing knobs are environment variables:

| Variable | Effect |
| --- | --- |
| `GDSC_FUZZ_SEED`, `GDSC_FUZZ_COUNT` | Where `test_fuzz` starts and how far it goes |
| `GDSC_DIFF_FUZZ`, `GDSC_DIFF_SEED`, `GDSC_DIFF_COUNT` | Turn on and steer `test_differential`'s generated programs, which are opt-in as they are upstream |
| `GDSC_DIFF_FILE` | Run one program from a file through `test_differential` |
| `PROPERTY_SEED` | The seed witness-cpp generates from |

`tests/fuzz_nightly.sh build 30` runs both fuzzers for half an hour from a seed
nobody has tried.

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

# GDScript to RISC-V Compiler (standalone extraction of godot-sandbox)
cmake_minimum_required(VERSION 3.10)

project(gdscript_compiler_standalone)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# enable_testing() has to be called from the top-level list file as well, or
# ctest run from the build root finds no tests -- the subdirectory's own call
# only registers them under src/gdscript/compiler.
option(BUILD_TESTING "Build the compiler test suite" ON)
if (BUILD_TESTING)
	enable_testing()
endif()

# The sources keep the paths they have in godot-sandbox (src/gdscript/compiler,
# src/syscalls.h), so a sync is a copy and never a patch. The build for them
# lives in their own CMakeLists.txt, likewise taken from upstream.
add_subdirectory(src/gdscript/compiler)

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

# doctest and witness-cpp are the test suite's two dependencies, both header
# only, both submodules. They are declared here rather than inside the
# compiler's own list file so that file stays upstream's.
if (BUILD_TESTING)
	if (NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/ext/doctest/doctest/doctest.h)
		message(FATAL_ERROR "ext/doctest is missing: git submodule update --init")
	endif()
	# doctest is a single header. Its own list file is not used: v2.4.11 asks
	# for a CMake policy version that CMake 4 no longer accepts, and an
	# interface target over the header is all this suite needs from it.
	add_library(doctest INTERFACE)
	add_library(doctest::doctest ALIAS doctest)
	target_include_directories(doctest INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/ext/doctest)

	set(WITNESS_BUILD_TESTS OFF CACHE BOOL "" FORCE)
	add_subdirectory(ext/witness-cpp EXCLUDE_FROM_ALL)
endif()

# The sources keep the paths they have in godot-sandbox (src/gdscript/compiler,
# src/syscalls.h), so a sync is a copy and never a patch. The build for them
# lives in their own CMakeLists.txt, likewise taken from upstream.
add_subdirectory(src/gdscript/compiler)

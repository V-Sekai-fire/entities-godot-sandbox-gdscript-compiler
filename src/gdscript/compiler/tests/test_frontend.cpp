#include "../compiler.h"
#include "../ir_interpreter.h"
#include "../ir_verifier.h"
#include "witness/doctest.h"
#include <algorithm>
#include <stdexcept>

using namespace gdscript;

namespace {

const char *const EXAMPLE =
		"@tool\nclass_name FrontendExample\n"
		"var count: int = 7\n"
		"func answer(value: int) -> int:\n\treturn value * 2 + 2\n";

} // namespace

TEST_CASE("the frontend means the same thing optimized or not") {
	Compiler compiler;
	for (bool optimize : { false, true }) {
		CompilerOptions options;
		options.optimize = optimize;
		auto ir = compiler.compile_to_ir(EXAMPLE, options);
		REQUIRE_MESSAGE(ir.has_value(), compiler.get_error());
		ir_verify(*ir);
		IRInterpreter interpreter(*ir);
		CHECK_MESSAGE(std::get<int64_t>(interpreter.call("answer", { int64_t(20) })) == 42,
					  "optimized and unoptimized frontend semantics differ");
		CHECK_MESSAGE(compiler.is_tool(), "lost script metadata");
		CHECK(compiler.get_class_name() == "FrontendExample");
		CHECK_MESSAGE(compiler.get_property_signatures().size() == 1, "lost property metadata");
		CHECK(ir->properties.size() == 1);
		CHECK_MESSAGE(!compiler.get_function_signatures().empty(), "lost signatures");
		CHECK_MESSAGE(compiler.get_line_table().entries.empty(),
					  "the frontend emitted machine addresses");
	}
}

TEST_CASE("a failed parse reports diagnostics and clears the metadata") {
	Compiler compiler;
	auto invalid = compiler.compile_to_ir("func broken(:\n\tpass\n");
	CHECK_MESSAGE(!invalid, "a broken source compiled");
	CHECK(compiler.get_error_info().has_error);
	CHECK(!compiler.get_error().empty());
	CHECK_MESSAGE(!compiler.is_tool(), "stale script metadata after a failure");
	CHECK(compiler.get_class_name().empty());
}

TEST_CASE("an empty source succeeds and says nothing went wrong") {
	Compiler compiler;
	auto empty = compiler.compile_to_ir("");
	REQUIRE(empty.has_value());
	CHECK_MESSAGE(!compiler.get_error_info().has_error,
				  "an empty success must differ from a failure");
	CHECK(compiler.get_error().empty());
}

TEST_CASE("a shipping build drops the tests") {
	Compiler compiler;
	CompilerOptions options;
	options.emit_tests = false;
	auto shipping = compiler.compile_to_ir(
			"@test\nfunc check_answer():\n\tpass\nfunc answer():\n\treturn 42\n", options);
	REQUIRE_MESSAGE(shipping.has_value(), compiler.get_error());
	CHECK(shipping->tests.empty());
	CHECK_MESSAGE(std::none_of(shipping->functions.begin(), shipping->functions.end(),
							   [](const IRFunction &function) { return function.name == "check_answer"; }),
				  "the frontend retained a test in a shipping build");
}

TEST_CASE("a base script is merged, and a restricted build refuses one") {
	Compiler compiler;
	CompilerOptions options;
	options.base_sources.push_back({ "Base", "res://base.sgd",
									 "func inherited() -> int:\n\treturn 42\n", false });
	auto derived = compiler.compile_to_ir(
			"extends Base\nfunc answer() -> int:\n\treturn inherited()\n", options);
	REQUIRE_MESSAGE(derived.has_value(), compiler.get_error());
	ir_verify(*derived);
	IRInterpreter inherited(*derived);
	CHECK_MESSAGE(std::get<int64_t>(inherited.call("answer")) == 42,
				  "the frontend skipped base merging");

	options.restricted = true;
	CHECK_MESSAGE(!compiler.compile_to_ir("extends Base\n", options),
				  "the frontend skipped the restricted policy");
}

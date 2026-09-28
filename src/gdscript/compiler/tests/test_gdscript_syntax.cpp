// GDScript that Godot accepts and the compiler has to as well: nested classes,
// expression statements, and compound assignment into call results.
#include "../codegen.h"
#include "../compiler_exception.h"
#include "../ir_interpreter.h"
#include "../ir_optimizer.h"
#include "../ir_verifier.h"
#include "../lexer.h"
#include "../parser.h"
#include "witness/doctest.h"
#include <string>

using namespace gdscript;

static Program parse(const std::string &source) {
	Lexer lexer(source);
	lexer.set_extensions(false);
	Parser parser(lexer.tokenize());
	parser.set_extensions(false);
	return parser.parse();
}

static IRProgram compile_to_ir(const std::string &source) {
	Program program = parse(source);
	CodeGenerator codegen;
	IRProgram ir = codegen.generate(program);
	ir_verify(ir);
	return ir;
}

static int count_calls(const IRProgram &ir, const std::string &function, const std::string &callee) {
	int calls = 0;
	for (const IRFunction &func : ir.functions) {
		if (func.name != function) {
			continue;
		}
		for (const IRInstruction &instr : func.instructions) {
			if (instr.opcode == IROpcode::CALL && ir.strings[instr.operands[0].string_id] == callee) {
				calls++;
			}
		}
	}
	return calls;
}

TEST_CASE("a class nested in a class is hoisted to file scope") {
	const Program program = parse(
			"class Outer:\n"
			"\tclass Inner:\n"
			"\t\tvar n = 1\n"
			"\tvar inner = Inner.new()\n");
	bool outer = false;
	bool inner = false;
	for (const StructDecl &decl : program.structs) {
		outer = outer || decl.name == "Outer";
		inner = inner || decl.name == "Inner";
	}
	CHECK(outer);
	CHECK(inner);
}

TEST_CASE("an expression statement parses whole and changes nothing") {
	IRProgram ir = compile_to_ir(
			"func test():\n"
			"\tvar c = 3\n"
			"\tc ++ 1\n"
			"\tc + 4\n"
			"\treturn c\n");
	IRInterpreter interp(ir);
	CHECK(std::get<int64_t>(interp.call("test")) == 3);
}

TEST_CASE("compound assignment into a call result evaluates the call once") {
	const IRProgram ir = compile_to_ir(
			"func g(a):\n"
			"\treturn a\n"
			"func test(a):\n"
			"\tg(a)[0] += 5\n"
			"\tg(a).size += 1\n"
			"\treturn a\n");
	CHECK(count_calls(ir, "test", "g") == 2);
}

TEST_CASE("compound assignment through a negative index") {
	CHECK_NOTHROW(compile_to_ir(
			"func test(a):\n"
			"\ta[-1] -= 1\n"
			"\treturn a\n"));
}

TEST_CASE("a call on its own is still not an assignment target") {
	CHECK_THROWS_AS(compile_to_ir(
							"func g():\n"
							"\treturn 1\n"
							"func test():\n"
							"\tg() += 1\n"),
					CompilerException);
}

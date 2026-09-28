// GDScript that Godot accepts and the compiler has to as well: nested classes,
// expression statements, and compound assignment into call results.
#include "../codegen.h"
#include "../compiler_exception.h"
#include "../ir_interpreter.h"
#include "../ir_optimizer.h"
#include "../ir_verifier.h"
#include "../lexer.h"
#include "../parser.h"
#include "../source_model.h"
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

static const Expr *returned(const Program &program) {
	const ReturnStmt *ret = dynamic_cast<const ReturnStmt *>(program.functions.front().body.back().get());
	REQUIRE(ret != nullptr);
	return ret->value.get();
}

TEST_CASE("operators after a cast take the cast as their left operand") {
	const Program compared = parse("func f(n):\n\treturn n as Node3D != null\n");
	const BinaryExpr *ne = dynamic_cast<const BinaryExpr *>(returned(compared));
	REQUIRE(ne != nullptr);
	CHECK(dynamic_cast<const CastExpr *>(ne->left.get()) != nullptr);

	const Program joined = parse("func f(n, c):\n\treturn n as Node3D == null and c\n");
	const BinaryExpr *both = dynamic_cast<const BinaryExpr *>(returned(joined));
	REQUIRE(both != nullptr);
	const BinaryExpr *eq = dynamic_cast<const BinaryExpr *>(both->left.get());
	REQUIRE(eq != nullptr);
	CHECK(dynamic_cast<const CastExpr *>(eq->left.get()) != nullptr);

	CHECK_NOTHROW(compile_to_ir("func f(n, c):\n\treturn n as Node3D if c else null\n"));
	CHECK_NOTHROW(compile_to_ir("func f(n):\n\treturn n as int - 1\n"));
}

TEST_CASE("a class getter on an untyped field, below comment lines") {
	CHECK_NOTHROW(compile_to_ir(
			"class A:\n"
			"\tvar keys = {}\n"
			"\tvar coefficients:\n"
			"\t\tget:\n"
			"\t\t\treturn keys.get(\"c\", [])\n"
			"\tvar flag: bool:\n"
			"\t\t# a note\n"
			"\t\tget:\n"
			"\t\t\treturn true\n"));
}

TEST_CASE("built-in type enums are integers") {
	IRProgram ir = compile_to_ir("func test():\n\treturn Vector3.AXIS_Z + Vector2i.AXIS_Y * 10\n");
	IRInterpreter interp(ir);
	CHECK(std::get<int64_t>(interp.call("test")) == 12);
}

TEST_CASE("a class or engine typed local starts null and takes an instance") {
	CHECK_NOTHROW(compile_to_ir(
			"class Def:\n"
			"\tvar n = 1\n"
			"func f(c):\n"
			"\tvar d: Def = null\n"
			"\tif c:\n"
			"\t\td = Def.new()\n"
			"\tvar s: Node3D = null\n"
			"\ts = Node3D.new()\n"
			"\treturn [d, s]\n"));
}

TEST_CASE("an Array literal fills a packed array slot") {
	const IRProgram ir = compile_to_ir(
			"var lines: PackedStringArray = []\n"
			"func f():\n"
			"\tvar local: PackedStringArray = [\"a\"]\n"
			"\treturn [lines, local]\n");
	int conversions = 0;
	for (const IRFunction &func : ir.functions) {
		for (const IRInstruction &instr : func.instructions) {
			conversions += instr.opcode == IROpcode::MAKE_PACKED_STRING_ARRAY;
		}
	}
	for (const IRInstruction &instr : ir.member_init.instructions) {
		conversions += instr.opcode == IROpcode::MAKE_PACKED_STRING_ARRAY;
	}
	CHECK(conversions == 2);
}

TEST_CASE("a bare string at file level is a comment") {
	CHECK_NOTHROW(parse("func f():\n\tpass\n'''\nnot code: (\n'''\n"));
}

static int count_code(const SourceModel &model, const std::string &code) {
	int n = 0;
	for (const SourceDiagnostic &d : model.diagnostics) {
		n += d.code == code;
	}
	return n;
}

TEST_CASE("a bare call in a class names the class's method before the file's function") {
	const SourceModel model = analyze_source(
			"func run(a, b):\n"
			"\treturn a\n"
			"class Handler:\n"
			"\tfunc run(a, b, c, d = 0):\n"
			"\t\treturn a\n"
			"\tfunc go():\n"
			"\t\treturn run(1, 2, 3)\n",
			"arity.gd", ANALYZE_DIAGNOSTICS | ANALYZE_DECLARATIONS);
	CHECK(count_code(model, "TOO_MANY_ARGUMENTS") == 0);

	const SourceModel outside = analyze_source(
			"func run(a, b):\n"
			"\treturn a\n"
			"func go():\n"
			"\treturn run(1, 2, 3)\n",
			"arity.gd", ANALYZE_DIAGNOSTICS | ANALYZE_DECLARATIONS);
	CHECK(count_code(outside, "TOO_MANY_ARGUMENTS") == 1);
}

TEST_CASE("an expression statement is reported once") {
	const SourceModel model = analyze_source("func f():\n\tvar c = 1\n\tc ++ 1\n\treturn c\n", "once.gd",
											 ANALYZE_DIAGNOSTICS | ANALYZE_DECLARATIONS);
	CHECK(count_code(model, "STANDALONE_EXPRESSION") == 1);
}

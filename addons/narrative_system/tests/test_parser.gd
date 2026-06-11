extends "res://addons/narrative_system/tests/harness/test_case.gd"
## DSL parser tests (grammar shape, precedence, rejections).

const Parser := preload("res://addons/narrative_system/runtime/dsl/parser.gd")


func _cond(source: String) -> Dictionary:
	return Parser.new().parse_condition(source)


func _acts(source: String) -> Dictionary:
	return Parser.new().parse_actions(source)


func test_empty_condition_is_true() -> void:
	var result := _cond("   \n\t ")
	assert_true(result.ok)
	assert_eq(result.ast, ["lit", true])


func test_precedence_arithmetic_over_comparison_over_bool() -> void:
	var result := _cond("1 + 2 * 3 >= x and not done or extra")
	assert_true(result.ok)
	var mul := ["bin", "*", ["lit", 2], ["lit", 3]]
	var add := ["bin", "+", ["lit", 1], mul]
	var cmp := ["bin", ">=", add, ["var", "x"]]
	var and_node := ["and", cmp, ["not", ["var", "done"]]]
	assert_eq(result.ast, ["or", and_node, ["var", "extra"]])


func test_parentheses_override_precedence() -> void:
	var result := _cond("(1 + 2) * 3")
	assert_true(result.ok)
	assert_eq(result.ast, ["bin", "*", ["bin", "+", ["lit", 1], ["lit", 2]], ["lit", 3]])


func test_function_calls_zero_and_n_args() -> void:
	var zero := _cond("ready()")
	assert_true(zero.ok)
	assert_eq(zero.ast, ["call", "ready", []])
	var nested := _cond('f(1, "a", g(2))')
	assert_true(nested.ok)
	assert_eq(nested.ast, ["call", "f", [["lit", 1], ["lit", "a"], ["call", "g", [["lit", 2]]]]])


func test_literals_and_unary_minus() -> void:
	var result := _cond("-x + -2")
	assert_true(result.ok)
	assert_eq(result.ast, ["bin", "+", ["neg", ["var", "x"]], ["neg", ["lit", 2]]])
	assert_eq(_cond("true").ast, ["lit", true])
	assert_eq(_cond("null").ast, ["lit", null])


func test_chained_comparison_rejected() -> void:
	var result := _cond("1 < x < 10")
	assert_false(result.ok)
	assert_contains(result.error.message, "chained comparisons")


func test_assignment_rejected_in_condition_mode() -> void:
	var result := _cond("gold = 10")
	assert_false(result.ok)
	assert_contains(result.error.message, "did you mean '=='")


func test_action_separators_semicolon_and_newline() -> void:
	var result := _acts("a = 1; b += 2\n\nf(3)")
	assert_true(result.ok)
	assert_eq(result.statements, [
		["assign", "=", "a", ["lit", 1]],
		["assign", "+=", "b", ["lit", 2]],
		["call", "f", [["lit", 3]]],
	])


func test_missing_separator_between_statements_rejected() -> void:
	var result := _acts("a = 1 b = 2")
	assert_false(result.ok)
	assert_contains(result.error.message, "expected ';' or a new line")


func test_sequence_mode_rejects_assignment() -> void:
	var result := Parser.new().parse_sequence("wait(1); gold = 5")
	assert_false(result.ok)
	assert_contains(result.error.message, "commands only")


func test_keyword_cannot_start_statement() -> void:
	var result := _acts("true = 1")
	assert_false(result.ok)
	assert_contains(result.error.message, "keyword")


func test_malformed_inputs_error_not_crash() -> void:
	for bad in ["1 +", "foo(", "= 3", "a ++ b", ")", "f(1,", "(a or)", "not"]:
		var result := _cond(bad)
		assert_false(result.ok, "should reject: %s" % bad)
		assert_true(result.error.message.length() > 0, "error message for: %s" % bad)


func _seq(source: String) -> Dictionary:
	return Parser.new().parse_sequence(source)


func test_sequence_decorations_parse() -> void:
	var timed := _seq("wait(1) @ 2.5")
	assert_true(timed.ok)
	assert_eq(timed.statements, [["timed", 2.5, ["call", "wait", [["lit", 1]]]]])
	var on_msg := _seq("show_actor(\"g\") @ message(\"ready\")")
	assert_true(on_msg.ok)
	assert_eq(on_msg.statements, [["on_message", "ready", ["call", "show_actor", [["lit", "g"]]]]])
	var notify := _seq("wait(1) -> \"done\"")
	assert_true(notify.ok)
	assert_eq(notify.statements, [["notify", "done", ["call", "wait", [["lit", 1]]]]])
	var combo := _seq("wait(1) @ 0.5 -> message(\"done\")")
	assert_true(combo.ok)
	assert_eq(combo.statements, [["timed", 0.5, ["notify", "done", ["call", "wait", [["lit", 1]]]]]])
	var plain := _seq("wait(1)\nhide_actor(\"g\") @ 1")
	assert_true(plain.ok)
	assert_eq(plain.statements[0], ["call", "wait", [["lit", 1]]], "undecorated lines keep the plain call shape")


func test_sequence_decoration_errors() -> void:
	var bad_at := _seq("wait(1) @ oops")
	assert_false(bad_at.ok)
	assert_contains(bad_at.error.message, "after '@'")
	var negative := _seq("wait(1) @ -2")
	assert_false(negative.ok)
	var bad_arrow := _seq("wait(1) -> 5")
	assert_false(bad_arrow.ok)
	assert_contains(bad_arrow.error.message, "after '->'")
	var empty_name := _seq("wait(1) -> \"\"")
	assert_false(empty_name.ok)
	var bad_msg := _seq("wait(1) @ message(name)")
	assert_false(bad_msg.ok)
	assert_contains(bad_msg.error.message, "string literal")
	var actions_reject := Parser.new().parse_actions("wait(1) @ 2")
	assert_false(actions_reject.ok, "decorations are sequencer-only")


func test_condition_rejects_seq_tokens() -> void:
	var arrow := _cond("a -> b")
	assert_false(arrow.ok)
	var at := _cond("a @ 1")
	assert_false(at.ok)

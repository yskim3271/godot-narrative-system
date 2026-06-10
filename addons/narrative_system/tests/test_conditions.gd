extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Evaluator semantics: type rules, failure policy, builtins, registration.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const Parser := preload("res://addons/narrative_system/runtime/dsl/parser.gd")

var ctx: NarrativeContext


func before_each() -> void:
	ctx = NarrativeContext.create(DbFactory.standard())


## Pure expression evaluation (bypasses the bool-only condition rule).
func _eval(source: String) -> Dictionary:
	var parsed := Parser.new().parse_condition(source)
	assert_true(parsed.ok, "parse should succeed: %s" % source)
	if not parsed.ok:
		return {"ok": false, "error": "parse failed"}
	return ctx.evaluator.evaluate(parsed.ast)


func _value(source: String) -> Variant:
	var result := _eval(source)
	assert_true(result.ok, "eval should succeed: %s (%s)" % [source, result.get("error", "")])
	return result.get("value")


func test_int_float_promotion() -> void:
	var int_sum: Variant = _value("1 + 2")
	assert_eq(typeof(int_sum), TYPE_INT)
	assert_eq(int_sum, 3)
	var float_sum: Variant = _value("1 + 2.5")
	assert_eq(typeof(float_sum), TYPE_FLOAT)
	assert_almost_eq(float_sum, 3.5)
	assert_eq(_value("2 * 3"), 6)
	assert_eq(_value("7 - 2.0"), 5.0)


func test_division_always_float_and_div_zero_errors() -> void:
	var q: Variant = _value("3 / 2")
	assert_eq(typeof(q), TYPE_FLOAT)
	assert_almost_eq(q, 1.5)
	assert_false(_eval("1 / 0").ok)
	assert_false(_eval("5 % 0").ok)
	assert_eq(_value("7 % 3"), 1)


func test_string_concat_and_mixed_plus_errors() -> void:
	assert_eq(_value("'ab' + 'cd'"), "abcd")
	var mixed := _eval("'gold: ' + 5")
	assert_false(mixed.ok)
	assert_contains(mixed.error, "str()")
	assert_eq(_value("'gold: ' + str(5)"), "gold: 5")


func test_equality_mixed_types_false_no_error() -> void:
	assert_eq(_value("1 == 'a'"), false)
	assert_eq(_value("1 != 'a'"), true)
	assert_eq(_value("3 == 3.0"), true)
	assert_eq(_value("null == null"), true)
	assert_eq(_value("true == 1"), false)


func test_ordering_numeric_and_string() -> void:
	assert_eq(_value("2 < 10"), true)
	assert_eq(_value("'apple' < 'banana'"), true)
	assert_false(_eval("1 < 'a'").ok)
	assert_false(_eval("true < false").ok)


func test_logical_ops_and_short_circuit() -> void:
	var calls: Array = [0]
	ctx.evaluator.functions.register("probe", func() -> bool:
		calls[0] += 1
		return true)
	assert_eq(_value("false and probe()"), false)
	assert_eq(calls[0], 0, "rhs of short-circuited 'and' must not run")
	assert_eq(_value("true or probe()"), true)
	assert_eq(calls[0], 0, "rhs of short-circuited 'or' must not run")
	assert_eq(_value("true and probe()"), true)
	assert_eq(calls[0], 1)
	assert_false(_eval("1 and true").ok, "non-bool logical operand errors")


func test_unknown_variable_reads_as_null() -> void:
	assert_eq(_value("missing_thing == null"), true)
	assert_eq(_value("missing_thing == 5"), false)


func test_unknown_function_makes_condition_false() -> void:
	assert_false(ctx.evaluator.eval_condition("definitely_missing()", "test"))
	assert_false(_eval("definitely_missing()").ok)


func test_registered_function_args_and_arity() -> void:
	ctx.evaluator.functions.register("add", func(a: int, b: int) -> int: return a + b)
	assert_eq(_value("add(2, 3)"), 5)
	var too_many := _eval("add(1, 2, 3)")
	assert_false(too_many.ok)
	assert_contains(too_many.error, "at most")
	# duplicate registration rejected without override
	assert_false(ctx.evaluator.functions.register("add", func() -> int: return 0))
	assert_true(ctx.evaluator.functions.register("add", func() -> int: return 9, true))


func test_compound_assignment() -> void:
	ctx.evaluator.run_actions("gold += 5", "test")
	assert_eq(ctx.state.get_value("gold"), 15)
	ctx.evaluator.run_actions("gold -= 3", "test")
	assert_eq(ctx.state.get_value("gold"), 12)
	# compound assignment to unknown variable is skipped
	ctx.evaluator.run_actions("nope += 1", "test")
	assert_false(ctx.state.has_value("nope"))


func test_action_statement_error_continues_remaining() -> void:
	ctx.evaluator.run_actions("gold = 'oops'; met_guard = true", "test")
	assert_eq(ctx.state.get_value("gold"), 10, "type-mismatched assignment must be skipped")
	assert_eq(ctx.state.get_value("met_guard"), true, "later statements still run")


func test_type_coercion_on_assignment() -> void:
	ctx.evaluator.run_actions("gold = 12.9", "test")
	assert_eq(ctx.state.get_value("gold"), 12, "float into int variable truncates")
	assert_eq(typeof(ctx.state.get_value("gold")), TYPE_INT)


func test_non_bool_condition_is_false() -> void:
	assert_false(ctx.evaluator.eval_condition("1 + 1", "test"))
	assert_true(ctx.evaluator.eval_condition("", "test"), "empty condition is true")
	assert_true(ctx.evaluator.eval_condition("   ", "test"))


func test_condition_with_variables() -> void:
	assert_true(ctx.evaluator.eval_condition("gold >= 10 and not met_guard", "test"))
	ctx.state.set_value("met_guard", true)
	assert_false(ctx.evaluator.eval_condition("gold >= 10 and not met_guard", "test"))


func test_has_seen_builtin() -> void:
	assert_false(ctx.evaluator.eval_condition("has_seen(\"linear\")", "test"))
	ctx.state.mark_seen("linear", "n1")
	assert_true(ctx.evaluator.eval_condition("has_seen(\"linear\")", "test"))
	assert_true(ctx.evaluator.eval_condition("has_seen(\"linear\", \"n1\")", "test"))
	assert_false(ctx.evaluator.eval_condition("has_seen(\"linear\", \"n2\")", "test"))


func test_variable_changed_signal_from_actions() -> void:
	var recorder: RefCounted = load("res://addons/narrative_system/tests/harness/signal_recorder.gd").new()
	recorder.watch(ctx.state, ["variable_changed"])
	ctx.evaluator.run_actions("gold = 99", "test")
	assert_eq(recorder.count("variable_changed"), 1)
	assert_eq(recorder.args_of("variable_changed"), ["gold", 99])
	# assigning the same value again must not re-emit
	ctx.evaluator.run_actions("gold = 99", "test2")
	assert_eq(recorder.count("variable_changed"), 1)


func test_parse_cache_returns_same_result() -> void:
	var first := ctx.evaluator.parse_sequence_cached("wait(1)")
	var second := ctx.evaluator.parse_sequence_cached("wait(1)")
	assert_true(first.ok)
	assert_true(is_same(first, second), "cached parse should return the identical dictionary")

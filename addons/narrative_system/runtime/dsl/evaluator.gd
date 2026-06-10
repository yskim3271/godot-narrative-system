extends RefCounted
## Evaluates Narrative DSL conditions, actions and sequencer lines.
##
## Layers:
##  - evaluate(ast) is pure: returns {ok, value} or {ok: false, error} and
##    never pushes engine warnings (fully unit-testable).
##  - eval_condition()/run_actions() are the convenience layer used by the
##    runner: parse cache per source string + warn-once deduplication, and
##    the documented failure policy (failed condition -> false, failed action
##    statement -> skipped while the remaining statements still run).

const Lexer := preload("lexer.gd")
const Parser := preload("parser.gd")
const FunctionRegistry := preload("function_registry.gd")

var functions: FunctionRegistry = FunctionRegistry.new()

var _state: NarrativeState
var _parser: Parser = Parser.new()
var _parse_cache: Dictionary = {}
var _warned: Dictionary = {}


func setup(state: NarrativeState) -> void:
	_state = state


# --- convenience layer (parse cache + warn-once + failure policy) ---


## Evaluates a condition source string. Empty source is true. Any parse or
## evaluation failure logs one warning per unique site and yields false.
func eval_condition(source: String, label := "") -> bool:
	if source.strip_edges() == "":
		return true
	var parsed := _parse_cached("cond", source)
	if not parsed.ok:
		_warn_once(label, source, "condition parse error at %d: %s" % [parsed.error.pos, parsed.error.message])
		return false
	var result := evaluate(parsed.ast)
	if not result.ok:
		_warn_once(label, source, "condition error: %s" % result.error)
		return false
	if typeof(result.value) != TYPE_BOOL:
		_warn_once(label, source, "condition must evaluate to true/false, got %s" % type_string(typeof(result.value)))
		return false
	return result.value


## Executes action statements. A failing statement is skipped with one
## warning per unique site; the remaining statements still execute.
func run_actions(source: String, label := "") -> void:
	if source.strip_edges() == "":
		return
	var parsed := _parse_cached("act", source)
	if not parsed.ok:
		_warn_once(label, source, "actions parse error at %d: %s" % [parsed.error.pos, parsed.error.message])
		return
	for i in parsed.statements.size():
		var result := execute_statement(parsed.statements[i])
		if not result.ok:
			_warn_once(label, source + "#%d" % i, "action statement %d skipped: %s" % [i + 1, result.error])


## Parses sequencer command lines (calls only), cached. Returns the parser
## result dictionary; the sequencer interprets the statements itself.
func parse_sequence_cached(source: String) -> Dictionary:
	return _parse_cached("seq", source)


# --- pure evaluation ---


## Evaluates an expression AST. Returns {ok: true, value} or
## {ok: false, error: String}. (Unknown-variable reads warn once and
## evaluate to null — reads are forgiving, everything else is strict.)
func evaluate(ast: Array) -> Dictionary:
	match str(ast[0]):
		"lit":
			return {"ok": true, "value": ast[1]}
		"var":
			var name: String = ast[1]
			if _state == null or not _state.has_value(name):
				_warn_once("", "var:" + name, "unknown variable '%s' (evaluates to null)" % name)
				return {"ok": true, "value": null}
			return {"ok": true, "value": _state.get_value(name)}
		"not":
			var operand := evaluate(ast[1])
			if not operand.ok:
				return operand
			if typeof(operand.value) != TYPE_BOOL:
				return _eval_error("'not' needs a bool, got %s" % type_string(typeof(operand.value)))
			return {"ok": true, "value": not operand.value}
		"and", "or":
			return _eval_logical(str(ast[0]), ast[1], ast[2])
		"bin":
			var left := evaluate(ast[2])
			if not left.ok:
				return left
			var right := evaluate(ast[3])
			if not right.ok:
				return right
			return apply_binary(str(ast[1]), left.value, right.value)
		"neg":
			var operand := evaluate(ast[1])
			if not operand.ok:
				return operand
			if not _is_number(operand.value):
				return _eval_error("unary '-' needs a number, got %s" % type_string(typeof(operand.value)))
			return {"ok": true, "value": -operand.value}
		"call":
			var name: String = ast[1]
			var args: Array = []
			for arg_ast in ast[2]:
				var arg := evaluate(arg_ast)
				if not arg.ok:
					return arg
				args.append(arg.value)
			return functions.call_function(name, args)
	return _eval_error("internal: unknown AST node '%s'" % str(ast[0]))


## Executes one statement AST: ["assign", op, name, expr] or ["call", ...].
func execute_statement(stmt: Array) -> Dictionary:
	if str(stmt[0]) == "call":
		return evaluate(stmt)
	# assignment
	var op: String = stmt[1]
	var name: String = stmt[2]
	var rhs := evaluate(stmt[3])
	if not rhs.ok:
		return rhs
	var new_value: Variant = rhs.value
	if op != "=":
		if not _state.has_value(name):
			return _eval_error("compound assignment to unknown variable '%s'" % name)
		var combined := apply_binary("+" if op == "+=" else "-", _state.get_value(name), rhs.value)
		if not combined.ok:
			return combined
		new_value = combined.value
	var assigned := _state.set_value(name, new_value)
	if not assigned.ok:
		return _eval_error(str(assigned.error))
	if assigned.has("warning"):
		_warn_once("", "assign:" + name, str(assigned.warning))
	return {"ok": true, "value": null}


## Binary operator semantics (shared with compound assignment).
func apply_binary(op: String, left: Variant, right: Variant) -> Dictionary:
	match op:
		"+":
			if _is_number(left) and _is_number(right):
				return {"ok": true, "value": left + right}
			if typeof(left) == TYPE_STRING and typeof(right) == TYPE_STRING:
				return {"ok": true, "value": str(left) + str(right)}
			return _eval_error("cannot add %s and %s (use str() to concatenate)" % [type_string(typeof(left)), type_string(typeof(right))])
		"-", "*":
			if _is_number(left) and _is_number(right):
				return {"ok": true, "value": left - right if op == "-" else left * right}
			return _eval_error("'%s' needs numbers, got %s and %s" % [op, type_string(typeof(left)), type_string(typeof(right))])
		"/":
			if not (_is_number(left) and _is_number(right)):
				return _eval_error("'/' needs numbers, got %s and %s" % [type_string(typeof(left)), type_string(typeof(right))])
			if float(right) == 0.0:
				return _eval_error("division by zero")
			return {"ok": true, "value": float(left) / float(right)}
		"%":
			if typeof(left) != TYPE_INT or typeof(right) != TYPE_INT:
				return _eval_error("'%' needs two integers")
			if right == 0:
				return _eval_error("modulo by zero")
			return {"ok": true, "value": left % right}
		"==":
			return {"ok": true, "value": _values_equal(left, right)}
		"!=":
			return {"ok": true, "value": not _values_equal(left, right)}
		"<", "<=", ">", ">=":
			return _apply_ordering(op, left, right)
	return _eval_error("internal: unknown operator '%s'" % op)


# --- internals ---


func _eval_logical(op: String, left_ast: Array, right_ast: Array) -> Dictionary:
	var left := evaluate(left_ast)
	if not left.ok:
		return left
	if typeof(left.value) != TYPE_BOOL:
		return _eval_error("'%s' needs bool operands, got %s" % [op, type_string(typeof(left.value))])
	# short-circuit
	if op == "and" and left.value == false:
		return {"ok": true, "value": false}
	if op == "or" and left.value == true:
		return {"ok": true, "value": true}
	var right := evaluate(right_ast)
	if not right.ok:
		return right
	if typeof(right.value) != TYPE_BOOL:
		return _eval_error("'%s' needs bool operands, got %s" % [op, type_string(typeof(right.value))])
	return {"ok": true, "value": right.value}


func _apply_ordering(op: String, left: Variant, right: Variant) -> Dictionary:
	var comparable := (_is_number(left) and _is_number(right)) \
		or (typeof(left) == TYPE_STRING and typeof(right) == TYPE_STRING)
	if not comparable:
		return _eval_error("'%s' needs two numbers or two strings, got %s and %s" % [op, type_string(typeof(left)), type_string(typeof(right))])
	var result: bool
	match op:
		"<":
			result = left < right
		"<=":
			result = left <= right
		">":
			result = left > right
		_:
			result = left >= right
	return {"ok": true, "value": result}


func _values_equal(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		return float(left) == float(right)
	if typeof(left) != typeof(right):
		return false
	return left == right


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _eval_error(message: String) -> Dictionary:
	return {"ok": false, "error": message}


func _parse_cached(mode: String, source: String) -> Dictionary:
	var key := mode + "" + source
	if _parse_cache.has(key):
		return _parse_cache[key]
	var result: Dictionary
	match mode:
		"cond":
			result = _parser.parse_condition(source)
		"act":
			result = _parser.parse_actions(source)
		_:
			result = _parser.parse_sequence(source)
	_parse_cache[key] = result
	return result


func _warn_once(label: String, site: String, message: String) -> void:
	var key := label + "" + site + "" + message
	if _warned.has(key):
		return
	_warned[key] = true
	var where := " [%s]" % label if label != "" else ""
	push_warning("Narrative DSL%s: %s" % [where, message])

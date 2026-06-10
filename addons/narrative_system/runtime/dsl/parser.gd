extends RefCounted
## Recursive-descent parser for the Narrative DSL.
##
## Three entry points (see docs/dsl.md for the grammar):
##  - parse_condition(): single expression; empty source parses to true.
##    Assignments are grammatically impossible here, so `=` vs `==` typos
##    are parse errors. Chained comparisons are rejected with a hint.
##  - parse_actions(): statements (assignment | call) separated by ';'/newline.
##  - parse_sequence(): like actions, but calls only (sequencer commands).
##
## ASTs are nested plain Arrays (serializable, cheap):
##   ["lit", value] | ["var", name] | ["call", name, [args]]
##   ["not", e] | ["and", l, r] | ["or", l, r] | ["bin", op, l, r] | ["neg", e]
## Statements: ["assign", op, name, expr] | ["call", name, [args]]
##
## Every public method returns {ok: true, ...} or
## {ok: false, error: {message: String, pos: int}}.

const Lexer := preload("lexer.gd")

const COMPARE_OPS: PackedStringArray = ["==", "!=", "<", "<=", ">", ">="]
const ASSIGN_OPS: PackedStringArray = ["=", "+=", "-="]

var _tokens: Array[Dictionary] = []
var _pos := 0


## {ok, ast} — empty/whitespace-only source is the constant true.
func parse_condition(source: String) -> Dictionary:
	if source.strip_edges() == "":
		return {"ok": true, "ast": ["lit", true]}
	var lex := Lexer.tokenize(source, false)
	if not lex.ok:
		return lex
	_tokens = lex.tokens
	_pos = 0
	var expr := _parse_expr()
	if not expr.ok:
		return expr
	if not _at_type("eof"):
		if _at_op_any(ASSIGN_OPS):
			return _error_here("assignment is not allowed in conditions (did you mean '=='?)")
		return _error_here("unexpected %s after expression" % _describe(_peek()))
	return {"ok": true, "ast": expr.value}


## {ok, statements: Array} — assignments and calls.
func parse_actions(source: String) -> Dictionary:
	return _parse_statements(source, true)


## {ok, statements: Array} — calls only (sequencer command lines).
func parse_sequence(source: String) -> Dictionary:
	return _parse_statements(source, false)


func _parse_statements(source: String, allow_assign: bool) -> Dictionary:
	if source.strip_edges() == "":
		return {"ok": true, "statements": []}
	var lex := Lexer.tokenize(source, true)
	if not lex.ok:
		return lex
	_tokens = lex.tokens
	_pos = 0
	var statements: Array = []
	_skip_separators()
	while not _at_type("eof"):
		var stmt := _parse_stmt(allow_assign)
		if not stmt.ok:
			return stmt
		statements.append(stmt.value)
		if _at_type("eof"):
			break
		if not _at_separator():
			return _error_here("expected ';' or a new line between statements, got %s" % _describe(_peek()))
		_skip_separators()
	return {"ok": true, "statements": statements}


func _parse_stmt(allow_assign: bool) -> Dictionary:
	if not _at_type("ident"):
		return _error_here("expected a statement, got %s" % _describe(_peek()))
	var name: String = _peek().value
	if Lexer.KEYWORDS.has(name):
		return _error_here("keyword '%s' cannot start a statement" % name)
	_take()
	if _at_punct("("):
		var call := _parse_call_args(name)
		if not call.ok:
			return call
		return {"ok": true, "value": call.value}
	if _at_op_any(ASSIGN_OPS):
		if not allow_assign:
			return _error_here("assignments are not allowed here (sequencer lines are commands only)")
		var op: String = _take().value
		var rhs := _parse_expr()
		if not rhs.ok:
			return rhs
		return {"ok": true, "value": ["assign", op, name, rhs.value]}
	if allow_assign:
		return _error_here("expected '(' or an assignment operator after '%s'" % name)
	return _error_here("expected '(' after command name '%s'" % name)


# --- expression levels (low to high precedence) ---


func _parse_expr() -> Dictionary:
	return _parse_or()


func _parse_or() -> Dictionary:
	var left := _parse_and()
	if not left.ok:
		return left
	var node: Array = left.value
	while _at_keyword("or"):
		_take()
		var right := _parse_and()
		if not right.ok:
			return right
		node = ["or", node, right.value]
	return {"ok": true, "value": node}


func _parse_and() -> Dictionary:
	var left := _parse_not()
	if not left.ok:
		return left
	var node: Array = left.value
	while _at_keyword("and"):
		_take()
		var right := _parse_not()
		if not right.ok:
			return right
		node = ["and", node, right.value]
	return {"ok": true, "value": node}


func _parse_not() -> Dictionary:
	if _at_keyword("not"):
		_take()
		var operand := _parse_not()
		if not operand.ok:
			return operand
		return {"ok": true, "value": ["not", operand.value]}
	return _parse_comparison()


func _parse_comparison() -> Dictionary:
	var left := _parse_additive()
	if not left.ok:
		return left
	if not _at_op_any(COMPARE_OPS):
		return left
	var op: String = _take().value
	var right := _parse_additive()
	if not right.ok:
		return right
	if _at_op_any(COMPARE_OPS):
		return _error_here("chained comparisons are not allowed (write 'a < b and b < c')")
	return {"ok": true, "value": ["bin", op, left.value, right.value]}


func _parse_additive() -> Dictionary:
	var left := _parse_multiplicative()
	if not left.ok:
		return left
	var node: Array = left.value
	while _at_op_any(["+", "-"]):
		var op: String = _take().value
		var right := _parse_multiplicative()
		if not right.ok:
			return right
		node = ["bin", op, node, right.value]
	return {"ok": true, "value": node}


func _parse_multiplicative() -> Dictionary:
	var left := _parse_unary()
	if not left.ok:
		return left
	var node: Array = left.value
	while _at_op_any(["*", "/", "%"]):
		var op: String = _take().value
		var right := _parse_unary()
		if not right.ok:
			return right
		node = ["bin", op, node, right.value]
	return {"ok": true, "value": node}


func _parse_unary() -> Dictionary:
	if _at_op("-"):
		_take()
		var operand := _parse_unary()
		if not operand.ok:
			return operand
		return {"ok": true, "value": ["neg", operand.value]}
	return _parse_primary()


func _parse_primary() -> Dictionary:
	var tok := _peek()
	match str(tok.type):
		"number", "string":
			_take()
			return {"ok": true, "value": ["lit", tok.value]}
		"ident":
			var name: String = tok.value
			match name:
				"true":
					_take()
					return {"ok": true, "value": ["lit", true]}
				"false":
					_take()
					return {"ok": true, "value": ["lit", false]}
				"null":
					_take()
					return {"ok": true, "value": ["lit", null]}
				"and", "or", "not":
					return _error_here("unexpected keyword '%s'" % name)
			_take()
			if _at_punct("("):
				return _parse_call_args(name)
			return {"ok": true, "value": ["var", name]}
		"punct":
			if tok.value == "(":
				_take()
				var inner := _parse_expr()
				if not inner.ok:
					return inner
				if not _at_punct(")"):
					return _error_here("expected ')' to close '(', got %s" % _describe(_peek()))
				_take()
				return inner
	return _error_here("unexpected %s" % _describe(tok))


func _parse_call_args(name: String) -> Dictionary:
	_take()  # consume "("
	var args: Array = []
	if _at_punct(")"):
		_take()
		return {"ok": true, "value": ["call", name, args]}
	while true:
		var arg := _parse_expr()
		if not arg.ok:
			return arg
		args.append(arg.value)
		if _at_punct(","):
			_take()
			continue
		if _at_punct(")"):
			_take()
			return {"ok": true, "value": ["call", name, args]}
		return _error_here("expected ',' or ')' in argument list of '%s', got %s" % [name, _describe(_peek())])
	return _error_here("unreachable")  # keeps the analyzer happy


# --- token plumbing ---


func _peek() -> Dictionary:
	return _tokens[_pos]


func _take() -> Dictionary:
	var tok := _tokens[_pos]
	if tok.type != "eof":
		_pos += 1
	return tok


func _at_type(type: String) -> bool:
	return str(_peek().type) == type


func _at_punct(value: String) -> bool:
	return _at_type("punct") and str(_peek().value) == value


func _at_op(value: String) -> bool:
	return _at_type("op") and str(_peek().value) == value


func _at_op_any(values) -> bool:
	return _at_type("op") and str(_peek().value) in values


func _at_keyword(keyword: String) -> bool:
	return _at_type("ident") and str(_peek().value) == keyword


func _at_separator() -> bool:
	return _at_type("newline") or _at_punct(";")


func _skip_separators() -> void:
	while _at_separator():
		_take()


func _describe(tok: Dictionary) -> String:
	if str(tok.type) == "eof":
		return "end of input"
	return "'%s'" % str(tok.value)


func _error_here(message: String) -> Dictionary:
	return {"ok": false, "error": {"message": message, "pos": int(_peek().pos)}}

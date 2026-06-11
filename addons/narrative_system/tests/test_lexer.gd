extends "res://addons/narrative_system/tests/harness/test_case.gd"
## DSL lexer tests.

const Lexer := preload("res://addons/narrative_system/runtime/dsl/lexer.gd")


func _tokens(source: String, statement_mode := false) -> Array:
	var result := Lexer.tokenize(source, statement_mode)
	assert_true(result.ok, "tokenize should succeed for: %s" % source)
	if not result.ok:
		return []
	var compact: Array = []
	for tok in result.tokens:
		compact.append("%s:%s" % [tok.type, str(tok.value)])
	return compact


func test_numbers_int_and_float() -> void:
	assert_eq(_tokens("12 3.5 0"), ["number:12", "number:3.5", "number:0", "eof:"])
	var result := Lexer.tokenize("7", false)
	assert_eq(typeof(result.tokens[0].value), TYPE_INT)
	var fresult := Lexer.tokenize("7.25", false)
	assert_eq(typeof(fresult.tokens[0].value), TYPE_FLOAT)


func test_malformed_number_errors() -> void:
	var result := Lexer.tokenize("3.", false)
	assert_false(result.ok)
	assert_contains(result.error.message, "digit required")


func test_strings_both_quotes_and_escapes() -> void:
	assert_eq(_tokens("'ab' \"cd\""), ["string:ab", "string:cd", "eof:"])
	var result := Lexer.tokenize('"a\\n\\t\\"b\\\\"', false)
	assert_true(result.ok)
	assert_eq(result.tokens[0].value, "a\n\t\"b\\")


func test_unterminated_string_errors_with_pos() -> void:
	var result := Lexer.tokenize('gold == "oops', false)
	assert_false(result.ok)
	assert_contains(result.error.message, "unterminated")
	assert_eq(result.error.pos, 8)


func test_identifiers_with_dots() -> void:
	assert_eq(_tokens("player.gold _x a1.b2"), ["ident:player.gold", "ident:_x", "ident:a1.b2", "eof:"])
	assert_false(Lexer.tokenize("a..b", false).ok)
	assert_false(Lexer.tokenize("a.", false).ok)


func test_two_char_operators_maximal_munch() -> void:
	assert_eq(
		_tokens("a<=b==c!=d>=e"),
		["ident:a", "op:<=", "ident:b", "op:==", "ident:c", "op:!=", "ident:d", "op:>=", "ident:e", "eof:"]
	)
	assert_eq(_tokens("x+=1", true), ["ident:x", "op:+=", "number:1", "eof:"])


func test_comments_and_whitespace_skipped() -> void:
	assert_eq(_tokens("gold # the money\n + 1"), ["ident:gold", "op:+", "number:1", "eof:"])


func test_newlines_only_in_statement_mode() -> void:
	assert_eq(_tokens("a\nb", false), ["ident:a", "ident:b", "eof:"])
	assert_eq(_tokens("a\nb", true), ["ident:a", "newline:\n", "ident:b", "eof:"])


func test_illegal_character_reports_position() -> void:
	var result := Lexer.tokenize("gold $ 1", false)
	assert_false(result.ok)
	assert_contains(result.error.message, "unexpected character '$'")
	assert_eq(result.error.pos, 5)


func test_sequencer_decoration_tokens() -> void:
	# '@' is a punct and '->' an op (sequencer line decorations); the parser
	# rejects them outside sequencer lines with positioned errors.
	assert_eq(_tokens("wait(1) @ 2 -> 'go'", true),
		["ident:wait", "punct:(", "number:1", "punct:)", "punct:@", "number:2", "op:->", "string:go", "eof:"])

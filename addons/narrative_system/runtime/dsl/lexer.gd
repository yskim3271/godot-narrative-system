@tool
extends RefCounted
## Tokenizer for the Narrative DSL (conditions / actions / sequencer lines).
##
## No eval, no Expression class — this hand-written lexer feeds parser.gd.
## In statement mode, newlines are significant (statement separators);
## in condition mode they are plain whitespace.
##
## Token: { "type": String, "value": Variant, "pos": int }
## Types: "ident" | "number" | "string" | "op" | "punct" | "newline" | "eof"

const KEYWORDS: PackedStringArray = ["and", "or", "not", "true", "false", "null"]
const TWO_CHAR_OPS: PackedStringArray = ["==", "!=", "<=", ">=", "+=", "-=", "->"]
const ONE_CHAR_OPS: PackedStringArray = ["<", ">", "+", "-", "*", "/", "%", "="]


## Returns {ok: true, tokens: Array[Dictionary]} or
## {ok: false, error: {message: String, pos: int}}.
static func tokenize(source: String, statement_mode: bool) -> Dictionary:
	var tokens: Array[Dictionary] = []
	var i := 0
	var n := source.length()
	while i < n:
		var c := source[i]

		if c == " " or c == "\t" or c == "\r":
			i += 1
			continue

		if c == "#":  # comment to end of line
			while i < n and source[i] != "\n":
				i += 1
			continue

		if c == "\n":
			if statement_mode:
				tokens.append({"type": "newline", "value": "\n", "pos": i})
			i += 1
			continue

		if _is_digit(c):
			var start := i
			while i < n and _is_digit(source[i]):
				i += 1
			var is_float := false
			if i < n and source[i] == ".":
				if i + 1 < n and _is_digit(source[i + 1]):
					is_float = true
					i += 1
					while i < n and _is_digit(source[i]):
						i += 1
				else:
					return _error("malformed number: digit required after '.'", i)
			var lexeme := source.substr(start, i - start)
			var value: Variant = lexeme.to_float() if is_float else lexeme.to_int()
			tokens.append({"type": "number", "value": value, "pos": start})
			continue

		if c == '"' or c == "'":
			var result := _read_string(source, i)
			if not result.ok:
				return result
			tokens.append(result.token)
			i = result.next
			continue

		if _is_ident_start(c):
			var start := i
			while i < n and _is_ident_char(source[i]):
				i += 1
			var lexeme := source.substr(start, i - start)
			if lexeme.ends_with(".") or lexeme.contains(".."):
				return _error("malformed identifier '%s' (misplaced '.')" % lexeme, start)
			tokens.append({"type": "ident", "value": lexeme, "pos": start})
			continue

		if i + 1 < n and TWO_CHAR_OPS.has(source.substr(i, 2)):
			tokens.append({"type": "op", "value": source.substr(i, 2), "pos": i})
			i += 2
			continue

		if ONE_CHAR_OPS.has(c):
			tokens.append({"type": "op", "value": c, "pos": i})
			i += 1
			continue

		if c == "(" or c == ")" or c == "," or c == ";" or c == "@":
			# '@' decorates sequencer lines (schedule); the parser rejects it
			# anywhere else with a positioned error instead of a lexer error.
			tokens.append({"type": "punct", "value": c, "pos": i})
			i += 1
			continue

		return _error("unexpected character '%s'" % c, i)

	tokens.append({"type": "eof", "value": "", "pos": n})
	return {"ok": true, "tokens": tokens}


static func _read_string(source: String, start: int) -> Dictionary:
	var quote := source[start]
	var n := source.length()
	var i := start + 1
	var buf := ""
	while i < n:
		var c := source[i]
		if c == "\\":
			if i + 1 >= n:
				return _error("unterminated string", start)
			var esc := source[i + 1]
			match esc:
				"n":
					buf += "\n"
				"t":
					buf += "\t"
				"\\":
					buf += "\\"
				'"':
					buf += '"'
				"'":
					buf += "'"
				_:
					return _error("unknown escape sequence '\\%s'" % esc, i)
			i += 2
			continue
		if c == quote:
			return {
				"ok": true,
				"token": {"type": "string", "value": buf, "pos": start},
				"next": i + 1,
			}
		if c == "\n":
			return _error("unterminated string (newline inside string)", i)
		buf += c
		i += 1
	return _error("unterminated string", start)


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_ident_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


static func _is_ident_char(c: String) -> bool:
	return _is_ident_start(c) or _is_digit(c) or c == "."


static func _error(message: String, pos: int) -> Dictionary:
	return {"ok": false, "error": {"message": message, "pos": pos}}

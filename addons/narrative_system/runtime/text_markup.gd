@tool
extends RefCounted
## Inline text markup: substitutes [var=name] tags with the current value of
## the narrative variable `name`.
##
## Applied AFTER localization resolves a text (runner lines/choices, context
## barks/alerts), so translated strings carry tags too. Unknown variables and
## malformed tags stay verbatim in the output — visible in-game and flagged
## by the validator (markup_unknown_variable). Substituted values are NOT
## re-scanned (no recursion).
##
## Any other [bracket] markup (e.g. BBCode like [color=...]) passes through
## untouched: RichTextLabel renders it natively.

const TAG_OPEN := "[var="


## Replaces every well-formed [var=name] with str(state.get_value(name)).
static func substitute_variables(text: String, state) -> String:
	if state == null or not text.contains(TAG_OPEN):
		return text
	var out := ""
	var i := 0
	while true:
		var start := text.find(TAG_OPEN, i)
		if start < 0:
			return out + text.substr(i)
		var close := text.find("]", start + TAG_OPEN.length())
		if close < 0:  # no closing bracket: keep the malformed tail verbatim
			return out + text.substr(i)
		out += text.substr(i, start - i)
		var name := text.substr(start + TAG_OPEN.length(), close - start - TAG_OPEN.length()).strip_edges()
		if name != "" and state.has_value(name):
			out += str(state.get_value(name))
		else:
			out += text.substr(start, close - start + 1)  # unknown: keep the tag visible
		i = close + 1
	return text  # unreachable


## Variable names referenced by well-formed [var=name] tags (validator support).
static func find_variable_tags(text: String) -> PackedStringArray:
	var names := PackedStringArray()
	var i := 0
	while true:
		var start := text.find(TAG_OPEN, i)
		if start < 0:
			return names
		var close := text.find("]", start + TAG_OPEN.length())
		if close < 0:
			return names
		names.append(text.substr(start + TAG_OPEN.length(), close - start - TAG_OPEN.length()).strip_edges())
		i = close + 1
	return names

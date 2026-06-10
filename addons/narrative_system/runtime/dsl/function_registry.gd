extends RefCounted
## Whitelist registry of functions callable from the Narrative DSL.
##
## This is the ONLY bridge from dialogue data to game code — there is no
## other way for authored content to execute anything. Returned values must
## stay inside the DSL value domain (null/bool/int/float/String).

const ALLOWED_RETURN_TYPES: Array = [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]

var _functions: Dictionary = {}  # name -> Callable


## Registers a function. Collisions with existing names (including built-ins)
## are rejected unless override is true.
func register(name: String, callable: Callable, override := false) -> bool:
	if name == "" or not name.is_valid_ascii_identifier():
		push_error("Narrative: invalid DSL function name '%s'" % name)
		return false
	if not callable.is_valid():
		push_error("Narrative: cannot register '%s' — callable is invalid" % name)
		return false
	if _functions.has(name) and not override:
		push_error("Narrative: DSL function '%s' is already registered (pass override = true to replace it)" % name)
		return false
	_functions[name] = callable
	return true


func unregister(name: String) -> void:
	_functions.erase(name)


func has_function(name: String) -> bool:
	return _functions.has(name)


func registered_names() -> PackedStringArray:
	var names := PackedStringArray()
	for name: String in _functions:
		names.append(name)
	names.sort()
	return names


## Invokes a registered function. Returns {ok, value} or {ok: false, error}.
func call_function(name: String, args: Array) -> Dictionary:
	if not _functions.has(name):
		return {"ok": false, "error": "unknown function '%s'" % name}
	var callable: Callable = _functions[name]
	if not callable.is_valid():
		return {"ok": false, "error": "function '%s' is no longer valid (object freed?)" % name}
	var argc := callable.get_argument_count()
	if argc >= 0 and args.size() > argc:
		return {
			"ok": false,
			"error": "function '%s' takes at most %d argument(s), got %d" % [name, argc, args.size()],
		}
	var value: Variant = callable.callv(args)
	if not ALLOWED_RETURN_TYPES.has(typeof(value)):
		return {
			"ok": false,
			"error": "function '%s' returned unsupported type %s" % [name, type_string(typeof(value))],
		}
	return {"ok": true, "value": value}

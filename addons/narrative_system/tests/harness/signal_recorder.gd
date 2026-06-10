extends RefCounted
## Records signal emissions in order, for order-sensitive assertions.
##
## Usage:
##   var rec = SignalRecorderScript.new()
##   rec.watch(runner, ["dialogue_started", "node_entered", "line_presented"])
##   ... act ...
##   assert_eq(rec.names(), ["dialogue_started", "node_entered", "line_presented"])

var records: Array[Dictionary] = []  # [{name: String, args: Array}]


func watch(obj: Object, signal_names: Array) -> void:
	for raw_name in signal_names:
		var sig_name: String = raw_name
		var argc := _signal_arg_count(obj, sig_name)
		if argc < 0:
			push_error("SignalRecorder: object has no signal '%s'" % sig_name)
			continue
		match argc:
			0: obj.connect(sig_name, func() -> void: _record(sig_name, []))
			1: obj.connect(sig_name, func(a: Variant) -> void: _record(sig_name, [a]))
			2: obj.connect(sig_name, func(a: Variant, b: Variant) -> void: _record(sig_name, [a, b]))
			3: obj.connect(sig_name, func(a: Variant, b: Variant, c: Variant) -> void: _record(sig_name, [a, b, c]))
			4: obj.connect(sig_name, func(a: Variant, b: Variant, c: Variant, d: Variant) -> void: _record(sig_name, [a, b, c, d]))
			_: push_error("SignalRecorder: signals with %d args are not supported" % argc)


## Names of all recorded emissions, in order.
func names() -> Array[String]:
	var result: Array[String] = []
	for r in records:
		result.append(r.name)
	return result


## Args of the n-th emission of the given signal (default: first).
func args_of(sig_name: String, occurrence := 0) -> Array:
	var seen := 0
	for r in records:
		if r.name == sig_name:
			if seen == occurrence:
				return r.args
			seen += 1
	return []


func count(sig_name: String) -> int:
	var n := 0
	for r in records:
		if r.name == sig_name:
			n += 1
	return n


func has(sig_name: String) -> bool:
	return count(sig_name) > 0


func clear() -> void:
	records.clear()


func _record(sig_name: String, args: Array) -> void:
	records.append({"name": sig_name, "args": args})


func _signal_arg_count(obj: Object, sig_name: String) -> int:
	for info in obj.get_signal_list():
		if info.name == sig_name:
			return info.args.size()
	return -1

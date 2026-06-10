extends RefCounted
## Base class for all Narrative System test cases.
##
## Test scripts live in tests/ as test_*.gd, extend this file by path, and
## define methods named test_*. Each test method runs on a fresh instance.
## Assertions accumulate failures instead of aborting, so a single test can
## report multiple problems. Async tests just use `await` — the runner awaits
## every test method uniformly.

var scene_tree: SceneTree
var current_test := ""
var _failures: Array[String] = []

# Overridable hooks (run on the same instance as the test method).
func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	_failures.append("[%s] %s" % [current_test, message])


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		fail(_compose("expected true, got false", message))


func assert_false(condition: bool, message := "") -> void:
	if condition:
		fail(_compose("expected false, got true", message))


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if not _values_equal(actual, expected):
		fail(_compose("expected %s, got %s" % [_repr(expected), _repr(actual)], message))


func assert_ne(actual: Variant, not_expected: Variant, message := "") -> void:
	if _values_equal(actual, not_expected):
		fail(_compose("expected anything but %s" % _repr(not_expected), message))


func assert_almost_eq(actual: float, expected: float, tolerance := 0.0001, message := "") -> void:
	if absf(actual - expected) > tolerance:
		fail(_compose("expected %s ± %s, got %s" % [expected, tolerance, actual], message))


func assert_null(value: Variant, message := "") -> void:
	if value != null:
		fail(_compose("expected null, got %s" % _repr(value), message))


func assert_not_null(value: Variant, message := "") -> void:
	if value == null:
		fail(_compose("expected non-null value", message))


func assert_contains(collection: Variant, item: Variant, message := "") -> void:
	var found := false
	match typeof(collection):
		TYPE_STRING:
			found = (collection as String).contains(str(item))
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			found = item in collection
		TYPE_DICTIONARY:
			found = (collection as Dictionary).has(item)
		_:
			fail(_compose("assert_contains: unsupported collection type %s" % type_string(typeof(collection)), message))
			return
	if not found:
		fail(_compose("expected %s to contain %s" % [_repr(collection), _repr(item)], message))


## Await a real timer on the harness SceneTree (for sequencer/typewriter tests).
func wait_seconds(seconds: float) -> void:
	await scene_tree.create_timer(seconds).timeout


## Await the next processed frame.
func wait_frame() -> void:
	await scene_tree.process_frame


func _values_equal(a: Variant, b: Variant) -> bool:
	# Exact comparison, but treat int/float pairs numerically (3 == 3.0)
	# to mirror common expectations in assertions.
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return float(a) == float(b) and (typeof(a) == typeof(b) or float(a) == floorf(float(a)))
	return typeof(a) == typeof(b) and a == b


func _repr(value: Variant) -> String:
	if value is String:
		return '"%s"' % value
	return "%s(%s)" % [type_string(typeof(value)), str(value)]


func _compose(base: String, message: String) -> String:
	if message.is_empty():
		return base
	return "%s — %s" % [base, message]

extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Harness smoke tests: verifies assertions, isolation and async support.

var _counter := 0


func test_basic_assertions() -> void:
	assert_true(true)
	assert_false(false)
	assert_eq(1 + 1, 2)
	assert_eq("ab" + "c", "abc")
	assert_ne(1, 2)
	assert_null(null)
	assert_not_null([])
	assert_almost_eq(0.1 + 0.2, 0.3)
	assert_contains([1, 2, 3], 2)
	assert_contains("hello world", "world")
	assert_contains({"k": 1}, "k")


func test_instances_are_isolated() -> void:
	# _counter would leak between tests if the runner reused instances.
	assert_eq(_counter, 0)
	_counter += 1


func test_instances_are_isolated_second() -> void:
	assert_eq(_counter, 0)


func test_async_await_works() -> void:
	# SceneTreeTimers are frame-quantized and may fire up to ~1 frame early
	# in wall-clock terms, so assert a generous lower bound: this still
	# catches "await returned instantly" regressions.
	var before := Time.get_ticks_msec()
	await wait_seconds(0.05)
	var elapsed := Time.get_ticks_msec() - before
	assert_true(elapsed >= 30, "timer should actually wait (elapsed=%dms)" % elapsed)


func test_signal_recorder_orders_and_args() -> void:
	var recorder: RefCounted = load("res://addons/narrative_system/tests/harness/signal_recorder.gd").new()
	var emitter := _Emitter.new()
	recorder.watch(emitter, ["zero_args", "two_args"])
	emitter.zero_args.emit()
	emitter.two_args.emit("guard", 42)
	emitter.zero_args.emit()
	assert_eq(recorder.names(), ["zero_args", "two_args", "zero_args"] as Array[String])
	assert_eq(recorder.args_of("two_args"), ["guard", 42])
	assert_eq(recorder.count("zero_args"), 2)


class _Emitter:
	extends RefCounted
	signal zero_args
	signal two_args(a: String, b: int)

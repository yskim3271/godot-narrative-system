extends SceneTree
## Headless test runner for the Narrative System addon (no external framework).
##
## Usage (from the project root, console build required on Windows for stdout):
##   godot --headless --path . -s res://addons/narrative_system/tests/run_tests.gd
##   godot --headless --path . -s res://addons/narrative_system/tests/run_tests.gd -- --filter=lexer,parser
##
## Discovers tests/test_*.gd, runs every test_* method on a fresh instance,
## awaits each method (sync and async tests are handled uniformly),
## prints a summary and exits with code 0 (all passed) or 1 (failures).

const TESTS_DIR := "res://addons/narrative_system/tests/"

var _total := 0
var _passed := 0
var _failed := 0
var _failed_names: Array[String] = []


func _initialize() -> void:
	# Not awaited: async tests suspend here and resume while the loop pumps frames.
	_run_all()


func _run_all() -> void:
	# The first frame's delta includes the whole engine startup time, which
	# instantly expires SceneTreeTimers created during _initialize. Pump two
	# frames so timing-dependent tests see normal deltas.
	await process_frame
	await process_frame

	var filters := _parse_filters()
	var scripts := _discover_tests(filters)
	if scripts.is_empty():
		printerr("run_tests: no test scripts found (filter: %s)" % ",".join(filters))
		quit(1)
		return

	var started := Time.get_ticks_msec()
	print("Narrative System test run — %d script(s)" % scripts.size())
	for script_path in scripts:
		await _run_script(script_path)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0

	print("")
	print("============================================================")
	print("Tests: %d   Passed: %d   Failed: %d   (%.2fs)" % [_total, _passed, _failed, elapsed])
	if _failed > 0:
		print("Failed tests:")
		for name in _failed_names:
			print("  - %s" % name)
		print("RESULT: FAIL")
	else:
		print("RESULT: PASS")
	quit(1 if _failed > 0 else 0)


func _run_script(script_path: String) -> void:
	var script: GDScript = load(script_path)
	if script == null or not script.can_instantiate():
		_total += 1
		_failed += 1
		_failed_names.append("%s (failed to load)" % script_path.get_file())
		printerr("  LOAD FAIL  %s" % script_path)
		return

	var method_names: Array[String] = []
	for info in script.get_script_method_list():
		if info.name.begins_with("test_") and not method_names.has(info.name):
			method_names.append(info.name)

	print("")
	print("[%s] %d test(s)" % [script_path.get_file(), method_names.size()])
	for method_name in method_names:
		# Start every test on a fresh frame boundary: synchronous work from
		# previous tests would otherwise be credited to this test's first
		# frame delta, making SceneTreeTimers fire early in wall-clock terms.
		await process_frame
		# Fresh instance per test = full isolation.
		var case: RefCounted = script.new()
		case.scene_tree = self
		case.current_test = method_name
		await case.before_each()
		await case.call(method_name)
		await case.after_each()
		_total += 1
		var failures: Array = case._failures
		if failures.is_empty():
			_passed += 1
			print("  PASS  %s" % method_name)
		else:
			_failed += 1
			_failed_names.append("%s :: %s" % [script_path.get_file(), method_name])
			print("  FAIL  %s" % method_name)
			for message in failures:
				print("          %s" % message)


func _parse_filters() -> PackedStringArray:
	var filters := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			for part in arg.trim_prefix("--filter=").split(",", false):
				filters.append(part.strip_edges())
	return filters


func _discover_tests(filters: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("test_") and fname.ends_with(".gd"):
			if filters.is_empty() or _matches(fname, filters):
				result.append(TESTS_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _matches(fname: String, filters: PackedStringArray) -> bool:
	for f in filters:
		if fname.contains(f):
			return true
	return false

extends "res://addons/narrative_system/tests/harness/test_case.gd"
## SaveManager: roundtrip, resume semantics, corruption, versioning, atomicity.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const SignalRecorder := preload("res://addons/narrative_system/tests/harness/signal_recorder.gd")

var ctx: NarrativeContext


func before_each() -> void:
	_purge_test_saves()
	ctx = NarrativeContext.create(DbFactory.standard())


func after_each() -> void:
	disconnect_all_signals(ctx.runner)
	disconnect_all_signals(ctx.state)
	disconnect_all_signals(ctx)
	ctx = null
	_purge_test_saves()


func _purge_test_saves() -> void:
	var dir := DirAccess.open("user://saves")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("t_"):
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _read_save(slot: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(ctx.save_manager.save_path(slot))
	var parsed: Variant = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "save file should parse")
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func test_roundtrip_full_state_and_resume_at_choices() -> void:
	ctx.state.set_value("gold", 42)
	ctx.quests.start_quest("rats")
	ctx.quests.update_objective("rats", "kill_rats", 2)
	ctx.runner.start_dialogue("branch")  # waits at choices
	assert_eq(ctx.save_manager.save_game("t_roundtrip"), OK)

	var fresh := NarrativeContext.create(DbFactory.standard())
	var rec: RefCounted = SignalRecorder.new()
	rec.watch(fresh.runner, ["dialogue_resumed", "line_presented", "choices_presented"])
	assert_eq(fresh.save_manager.load_game("t_roundtrip"), OK)

	assert_eq(fresh.state.get_value("gold"), 42)
	assert_eq(fresh.quests.get_quest_state("rats"), "active")
	assert_eq(fresh.quests.get_objectives_progress("rats")[0].count, 2)
	assert_true(fresh.state.has_seen("branch", "q"))
	assert_true(fresh.runner.is_dialogue_running())
	assert_true(fresh.runner.is_waiting_for_choice())
	assert_eq(rec.names(), ["dialogue_resumed", "line_presented", "choices_presented"] as Array[String])
	assert_eq(rec.args_of("dialogue_resumed"), ["branch", "q"])
	var choices := fresh.runner.get_available_choices()
	assert_eq(choices.size(), 2)
	assert_true(fresh.runner.select_choice("stay"), "resumed dialogue is fully playable")
	disconnect_all_signals(fresh.runner)


func test_int_variables_restore_as_int() -> void:
	ctx.state.set_value("gold", 77)
	assert_eq(ctx.save_manager.save_game("t_int"), OK)
	var fresh := NarrativeContext.create(DbFactory.standard())
	fresh.save_manager.load_game("t_int")
	assert_eq(typeof(fresh.state.get_value("gold")), TYPE_INT, "JSON floats must coerce back to declared int")
	assert_eq(fresh.state.get_value("gold"), 77)


func test_resume_does_not_rerun_actions() -> void:
	ctx.runner.start_dialogue("actions")  # node a1 actions: gold += 5 -> 15
	assert_eq(ctx.state.get_value("gold"), 15)
	assert_eq(ctx.save_manager.save_game("t_noreplay"), OK)
	var fresh := NarrativeContext.create(DbFactory.standard())
	fresh.save_manager.load_game("t_noreplay")
	assert_true(fresh.runner.is_dialogue_running())
	assert_eq(fresh.runner.get_current_node().id, "a1")
	assert_eq(fresh.state.get_value("gold"), 15, "resume must not re-run node actions (would be 20)")


func test_resume_missing_node_drops_gracefully() -> void:
	ctx.runner.start_dialogue("linear")
	var data := ctx.save_manager.capture()
	data.dialogue.current.node_id = "ghost_node"
	var fresh := NarrativeContext.create(DbFactory.standard())
	assert_eq(fresh.save_manager.apply(data), OK, "a stale position is not a load failure")
	assert_false(fresh.runner.is_dialogue_running())
	assert_true(fresh.state.current_dialogue.is_empty())


func test_corrupted_file_quarantined_state_untouched() -> void:
	ctx.state.set_value("gold", 123)
	DirAccess.make_dir_recursive_absolute("user://saves")
	var path: String = ctx.save_manager.save_path("t_corrupt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ this is not json !!!")
	file.close()
	assert_eq(ctx.save_manager.load_game("t_corrupt"), ERR_FILE_CORRUPT)
	assert_eq(ctx.state.get_value("gold"), 123, "state must stay untouched on corrupt load")
	assert_false(FileAccess.file_exists(path), "corrupt file moved away")
	# quarantined copy exists
	var dir := DirAccess.open("user://saves")
	dir.list_dir_begin()
	var found := false
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("t_corrupt.json.corrupt-"):
			found = true
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	assert_true(found, "quarantine file should exist")


func test_future_version_refused() -> void:
	ctx.state.set_value("gold", 55)
	var data := ctx.save_manager.capture()
	data.save_version = int(data.save_version) + 5
	assert_eq(ctx.save_manager.apply(data), ERR_INVALID_DATA)
	assert_eq(ctx.state.get_value("gold"), 55, "state untouched after refused load")


func test_migration_chain_applies() -> void:
	var data := ctx.save_manager.capture()
	data.save_version = 0
	var fresh := NarrativeContext.create(DbFactory.standard())
	# without a 0 -> 1 step the load must refuse
	assert_eq(fresh.save_manager.apply(data.duplicate(true)), ERR_INVALID_DATA)
	# with the step registered it migrates and loads
	fresh.save_manager.migrations[0] = func(old: Dictionary) -> Dictionary:
		old.custom["migrated_marker"] = true
		return old
	assert_eq(fresh.save_manager.apply(data.duplicate(true)), OK)
	assert_eq(fresh.state.custom_data.get("migrated_marker"), true)


func test_atomic_write_rotates_backup() -> void:
	ctx.state.set_value("gold", 10)
	assert_eq(ctx.save_manager.save_game("t_atomic"), OK)
	ctx.state.set_value("gold", 99)
	assert_eq(ctx.save_manager.save_game("t_atomic"), OK)
	var main := _read_save("t_atomic")
	assert_eq(int(main.variables.gold), 99)
	var bak_text := FileAccess.get_file_as_string(ctx.save_manager.save_path("t_atomic") + ".bak")
	var bak: Variant = JSON.parse_string(bak_text)
	assert_eq(int(bak.variables.gold), 10, ".bak keeps the previous good save")
	assert_false(FileAccess.file_exists(ctx.save_manager.save_path("t_atomic") + ".tmp"))


func test_save_during_transition_returns_busy() -> void:
	var results: Array = []
	ctx.runner.node_entered.connect(func(_id: String) -> void:
		results.append(ctx.save_manager.save_game("t_busy")))
	ctx.runner.start_dialogue("linear")
	assert_eq(results[0], ERR_BUSY)
	assert_false(ctx.save_manager.has_save("t_busy"))
	# between lines saving is fine
	assert_eq(ctx.save_manager.save_game("t_busy"), OK)


func test_non_persistent_variables_excluded() -> void:
	ctx.state.set_value("session_tmp", 999)
	assert_eq(ctx.save_manager.save_game("t_persist"), OK)
	var data := _read_save("t_persist")
	assert_false(data.variables.has("session_tmp"))
	var fresh := NarrativeContext.create(DbFactory.standard())
	fresh.save_manager.load_game("t_persist")
	assert_eq(fresh.state.get_value("session_tmp"), 7, "non-persistent variable resets to default")


func test_repeated_save_is_deterministic() -> void:
	ctx.quests.start_quest("rats")
	ctx.runner.start_dialogue("linear")
	assert_eq(ctx.save_manager.save_game("t_det"), OK)
	var first := _read_save("t_det")
	assert_eq(ctx.save_manager.save_game("t_det"), OK)
	var second := _read_save("t_det")
	for key in ["saved_at", "saved_at_unix"]:
		first.erase(key)
		second.erase(key)
	assert_eq(JSON.stringify(first, "\t"), JSON.stringify(second, "\t"), "same state must serialize identically")


func test_has_and_delete_save() -> void:
	assert_false(ctx.save_manager.has_save("t_del"))
	ctx.save_manager.save_game("t_del")
	assert_true(ctx.save_manager.has_save("t_del"))
	assert_true(ctx.save_manager.delete_save("t_del"))
	assert_false(ctx.save_manager.has_save("t_del"))
	assert_false(ctx.save_manager.delete_save("t_del"), "deleting a missing slot reports false")
	assert_eq(ctx.save_manager.load_game("t_del"), ERR_FILE_NOT_FOUND)

extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Save loading under hostile data: wrong-typed sections, malformed inner
## entries, truncated files, out-of-range counts, legacy quests.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")

var ctx: NarrativeContext


func before_each() -> void:
	ctx = NarrativeContext.create(DbFactory.standard())


func after_each() -> void:
	disconnect_all_signals(ctx.runner)
	disconnect_all_signals(ctx.state)
	disconnect_all_signals(ctx)
	ctx = null
	var dir := DirAccess.open("user://saves")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with("t_hard"):
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()


func test_wrong_typed_sections_degrade_to_defaults() -> void:
	var data := ctx.save_manager.capture()
	data.variables = "not a dict"
	data.quests = [1, 2, 3]
	data.dialogue = 42
	data.custom = false
	assert_eq(ctx.save_manager.apply(data), OK, "broken sections must not abort the whole load")
	assert_eq(ctx.state.get_value("gold"), 10, "variables reset to declared defaults")
	assert_true(ctx.state.quest_states.is_empty())
	assert_false(ctx.runner.is_dialogue_running())
	assert_true(ctx.state.custom_data.is_empty())


func test_malformed_inner_entries_are_dropped() -> void:
	ctx.quests.start_quest("rats")
	ctx.quests.update_objective("rats", "kill_rats", 2)
	var data := ctx.save_manager.capture()
	data.quests["rats"]["objectives"]["kill_rats"] = "boom"
	data.quests["bogus"] = {"state": "flying"}
	data.dialogue["history"] = [1, {"d": "x"}, {"d": "linear", "n": "n1", "t": "not_a_number"}]
	data.dialogue["seen_nodes"] = {"linear": "not_an_array", "branch": ["q"]}
	assert_eq(ctx.save_manager.apply(data), OK)
	assert_eq(ctx.quests.get_quest_state("rats"), "active", "valid quest entry survives")
	assert_eq(ctx.quests.get_objective_count("rats", "kill_rats"), 0, "garbage objective entry dropped")
	assert_eq(ctx.quests.get_quest_state("bogus"), "inactive", "invalid state dropped")
	assert_eq(ctx.state.history.size(), 1, "only the structurally valid history entry survives")
	assert_eq(ctx.state.history[0].t, 0, "non-numeric timestamp coerces to 0")
	assert_false(ctx.state.has_seen("linear"), "non-array seen list skipped")
	assert_true(ctx.state.has_seen("branch", "q"))


func test_truncated_save_file_quarantined() -> void:
	ctx.state.set_value("gold", 64)
	assert_eq(ctx.save_manager.save_game("t_hard_trunc"), OK)
	var path: String = ctx.save_manager.save_path("t_hard_trunc")
	var full := FileAccess.get_file_as_string(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(full.substr(0, full.length() / 2))
	file.close()
	assert_eq(ctx.save_manager.load_game("t_hard_trunc"), ERR_FILE_CORRUPT)
	assert_eq(ctx.state.get_value("gold"), 64, "state untouched")
	var dir := DirAccess.open("user://saves")
	dir.list_dir_begin()
	var quarantined := false
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("t_hard_trunc.json.corrupt-"):
			quarantined = true
		fname = dir.get_next()
	dir.list_dir_end()
	assert_true(quarantined)


func test_objective_counts_reclamped_against_database() -> void:
	ctx.quests.start_quest("rats")
	var data := ctx.save_manager.capture()
	data.quests["rats"]["objectives"]["kill_rats"] = {"count": 999, "completed": false}
	assert_eq(ctx.save_manager.apply(data), OK)
	var progress := ctx.quests.get_objectives_progress("rats")[0]
	assert_eq(progress.count, 5, "counts clamp to the database target")
	assert_true(bool(progress.completed), "completed recomputed from the clamped count")

	data.quests["rats"]["objectives"]["kill_rats"] = {"count": -3, "completed": true}
	assert_eq(ctx.save_manager.apply(data), OK)
	progress = ctx.quests.get_objectives_progress("rats")[0]
	assert_eq(progress.count, 0)
	assert_false(bool(progress.completed))


func test_legacy_quest_entries_survive_database_removal() -> void:
	var data := ctx.save_manager.capture()
	data.quests["removed_quest"] = {"state": "completed", "tracked": false, "objectives": {}}
	assert_eq(ctx.save_manager.apply(data), OK)
	assert_eq(ctx.quests.get_quest_state("removed_quest"), "completed",
		"state from removed quests is kept (forward compatibility)")


func test_repeated_bad_condition_stays_stable() -> void:
	var db := DbFactory.standard()
	db.dialogues.append(DbFactory.make_dialogue("badcond", "b1", [
		DbFactory.make_node("b1", {"conditions": "gold >= ", "next": "b2", "text": "never shown"}),
		DbFactory.make_node("b2", {"text": "landed safely"}),
	]))
	var local_ctx := NarrativeContext.create(db)
	for i in 3:
		assert_true(local_ctx.runner.start_dialogue("badcond"))
		assert_eq(local_ctx.runner.get_current_node().id, "b2", "broken condition is false -> skip, every time")
		local_ctx.runner.end_dialogue()
	disconnect_all_signals(local_ctx.runner)

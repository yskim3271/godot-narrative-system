extends "res://addons/narrative_system/tests/harness/test_case.gd"
## End-to-end happy path on the SHIPPED demo database through the facade:
## start -> branch -> quest -> mid-dialogue save -> fresh process load ->
## resume -> complete -> language switch -> final roundtrip.
##
## This test must stay free of engine errors AND warnings —
## scripts/run_tests.ps1 greps its output as the happy-path purity gate.

const SAVE_SLOT := "t_flow"

var facade: Node
var guard_node: Node2D
var camera: Camera2D


func before_each() -> void:
	_purge()
	# A minimal "world" so the demo's sequencer cutscene finds its targets
	# (actor with a wave animation + an active camera) — exactly what the
	# demo scene provides.
	guard_node = Node2D.new()
	guard_node.name = "GuardNPC"
	var anim_player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 0.1
	library.add_animation("wave", animation)
	anim_player.add_animation_library("", library)
	guard_node.add_child(anim_player)
	scene_tree.root.add_child(guard_node)
	camera = Camera2D.new()
	scene_tree.root.add_child(camera)
	camera.make_current()

	facade = load("res://addons/narrative_system/runtime/narrative.gd").new()
	scene_tree.root.add_child(facade)  # _ready auto-loads the project database
	facade.register_actor("guard", guard_node)


func after_each() -> void:
	facade.queue_free()
	guard_node.queue_free()
	camera.queue_free()
	# The q_give cutscene parks a sequencer coroutine on wait() timers; a
	# cancelled run only unwinds when its timer fires. Let the longest wait
	# (0.5 + 0.6s) elapse so nothing is parked at process exit — otherwise
	# the engine reports the held context as leaked objects/RIDs.
	await wait_seconds(1.3)
	_purge()


func _purge() -> void:
	var dir := DirAccess.open("user://saves")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.begins_with(SAVE_SLOT):
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()


func test_full_playthrough_with_mid_dialogue_save() -> void:
	assert_true(facade.is_ready(), "autoload path loads the demo database")
	assert_eq(facade.get_variable("gold"), 30)
	assert_eq(facade.get_language(), "ko")

	# --- first conversation: take the quest ---
	assert_true(facade.start_dialogue("guard_talk"))
	assert_eq(facade.get_current_node().id, "g_first")
	assert_true(facade.advance())
	assert_true(facade.is_waiting_for_choice())
	assert_true(facade.select_choice("c_quest"))
	assert_true(facade.is_quest_active("rat_hunt"))
	assert_true(facade.is_quest_tracked("rat_hunt"))
	assert_true(facade.advance())
	assert_false(facade.is_dialogue_running())

	# --- progress 3/5, then save in the middle of the choice menu ---
	for i in 3:
		assert_true(facade.update_objective("rat_hunt", "kill_rats"))
	assert_true(facade.start_dialogue("guard_talk"))
	assert_eq(facade.get_current_node().id, "g_return", "return greeting on the second visit")
	assert_true(facade.advance())
	assert_true(facade.is_waiting_for_choice())
	assert_eq(facade.save_game(SAVE_SLOT), OK)
	assert_true(facade.end_dialogue())

	# --- "fresh process": a second facade with its own context ---
	var second: Node = load("res://addons/narrative_system/runtime/narrative.gd").new()
	scene_tree.root.add_child(second)
	second.register_actor("guard", guard_node)
	assert_true(second.is_ready())
	assert_eq(second.get_variable("gold"), 30, "fresh context starts clean")
	assert_eq(second.load_game(SAVE_SLOT), OK)
	assert_true(second.is_dialogue_running(), "resumed mid-dialogue")
	assert_true(second.is_waiting_for_choice())
	assert_eq(second.get_quest_state("rat_hunt"), "active")

	var ids: Array[String] = []
	for choice in second.get_available_choices():
		ids.append(str(choice.id))
	assert_contains(ids, "c_progress")
	assert_false(ids.has("c_done"), "3/5 rats: completion choice still hidden")
	assert_true(second.select_choice("c_progress"))
	assert_true(second.advance())

	# --- finish the objectives and turn the quest in ---
	for i in 2:
		assert_true(second.update_objective("rat_hunt", "kill_rats"))
	assert_true(second.are_all_objectives_completed("rat_hunt"))
	assert_true(second.start_dialogue("guard_talk"))
	assert_true(second.advance())
	assert_true(second.select_choice("c_done"))
	assert_true(second.is_quest_completed("rat_hunt"))
	assert_eq(second.get_variable("gold"), 130, "reward paid")
	assert_true(second.advance())
	assert_false(second.is_dialogue_running())

	# --- language switch + final roundtrip ---
	second.set_language("en")
	assert_eq(second.get_quest_title("rat_hunt"), "Rat Hunt")
	assert_eq(second.get_character_display_name("guard"), "Guard")
	second.set_language("ko")
	assert_eq(second.save_game(SAVE_SLOT), OK)
	assert_eq(second.load_game(SAVE_SLOT), OK)
	assert_true(second.is_quest_completed("rat_hunt"))
	assert_eq(second.get_variable("gold"), 130)
	assert_eq(second.get_quests_in_state("completed"), ["rat_hunt"] as Array[String])

	second.queue_free()
	await wait_frame()

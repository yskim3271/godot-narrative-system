extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Sequencer: command execution, waits, cancellation, actors, barks.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const SignalRecorder := preload("res://addons/narrative_system/tests/harness/signal_recorder.gd")

var ctx: NarrativeContext
var npc: Node2D
var anim_player: AnimationPlayer


func before_each() -> void:
	ctx = NarrativeContext.create(DbFactory.standard(), scene_tree)
	npc = Node2D.new()
	npc.name = "GuardNPC"
	anim_player = AnimationPlayer.new()
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 0.1
	library.add_animation("wave", animation)
	anim_player.add_animation_library("", library)
	npc.add_child(anim_player)
	scene_tree.root.add_child(npc)
	ctx.register_actor("guard", npc)


func after_each() -> void:
	disconnect_all_signals(ctx.sequencer)
	disconnect_all_signals(ctx.runner)
	disconnect_all_signals(ctx.state)
	disconnect_all_signals(ctx)
	npc.queue_free()
	await wait_frame()
	ctx = null


func test_wait_blocks_then_continues() -> void:
	ctx.sequencer.start_run("set_variable(\"gold\", 1)\nwait(0.15)\nset_variable(\"gold\", 2)", "t")
	assert_eq(ctx.state.get_value("gold"), 1, "commands before wait run synchronously")
	assert_true(ctx.sequencer.is_running())
	await wait_seconds(0.35)
	assert_eq(ctx.state.get_value("gold"), 2, "commands after wait run later")
	assert_false(ctx.sequencer.is_running())


func test_run_finished_signal() -> void:
	var rec: RefCounted = SignalRecorder.new()
	rec.watch(ctx.sequencer, ["run_finished"])
	ctx.sequencer.start_run("set_variable(\"gold\", 3)", "lbl")
	assert_eq(rec.count("run_finished"), 1, "synchronous run finishes inline")
	assert_eq(rec.args_of("run_finished"), ["lbl"])


func test_unknown_command_warns_and_skips() -> void:
	ctx.sequencer.start_run("definitely_not_a_command(1)\nset_variable(\"gold\", 5)", "t")
	assert_eq(ctx.state.get_value("gold"), 5, "remaining commands still run")


func test_parse_error_no_crash() -> void:
	ctx.sequencer.start_run("wait(", "t")
	assert_false(ctx.sequencer.is_running())
	assert_eq(ctx.state.get_value("gold"), 10)


func test_cancellation_on_advance() -> void:
	ctx.runner.start_dialogue("seqtest")  # sequence: wait(0.3) then gold = 99
	assert_eq(ctx.state.get_value("gold"), 10)
	ctx.runner.advance()  # cancels the in-flight run
	await wait_seconds(0.5)
	assert_eq(ctx.state.get_value("gold"), 10, "cancelled run must not execute post-wait commands")
	ctx.runner.end_dialogue()


func test_quest_visibility_and_method_commands() -> void:
	ctx.sequencer.start_run("start_quest(\"intro\")\nhide_actor(\"guard\")\ncall_method(\"guard\", \"set_meta\", \"touched\", true)", "t")
	assert_true(ctx.quests.is_quest_active("intro"))
	assert_false(npc.visible)
	assert_eq(npc.get_meta("touched"), true)
	ctx.sequencer.start_run("show_actor(\"guard\")", "t")
	assert_true(npc.visible)


func test_play_animation() -> void:
	ctx.sequencer.start_run("play_animation(\"guard\", \"wave\")", "t")
	assert_true(anim_player.is_playing())
	assert_eq(anim_player.current_animation, "wave")
	# unknown animation / unknown actor: warn + skip, no crash
	ctx.sequencer.start_run("play_animation(\"guard\", \"nope\")\nplay_animation(\"ghost\", \"wave\")", "t")


func test_play_audio_wait_uses_length_fallback() -> void:
	var audio := AudioStreamPlayer.new()
	audio.stream = AudioStreamWAV.new()  # zero-length: falls back to a minimal timer
	npc.add_child(audio)
	ctx.sequencer.start_run("play_audio_wait(\"guard\")\nset_variable(\"met_guard\", true)", "t")
	await wait_seconds(0.15)
	assert_eq(ctx.state.get_value("met_guard"), true, "run completes even though 'finished' never fires headless")


func test_emit_signal_event() -> void:
	var rec: RefCounted = SignalRecorder.new()
	rec.watch(ctx.sequencer, ["sequence_event"])
	ctx.sequencer.start_run("emit_signal(\"boom\", 7, \"x\")", "t")
	assert_eq(rec.count("sequence_event"), 1)
	assert_eq(rec.args_of("sequence_event"), ["boom", [7, "x"]])


func test_args_are_dsl_expressions() -> void:
	ctx.state.set_value("gold", 4)
	ctx.sequencer.start_run("set_variable(\"gold\", gold + 6)", "t")
	assert_eq(ctx.state.get_value("gold"), 10, "command args evaluate against narrative variables")


func test_custom_command_registration() -> void:
	var calls: Array = []
	assert_true(ctx.sequencer.register_command("custom_cmd", func(args: Array) -> void:
		calls.append(args)))
	ctx.sequencer.start_run("custom_cmd(1, \"a\")", "t")
	assert_eq(calls, [[1, "a"]])
	assert_false(ctx.sequencer.register_command("custom_cmd", func(_args: Array) -> void: pass),
		"duplicate registration rejected without override")
	assert_true(ctx.sequencer.has_command("wait"))


func test_bark_bubble_spawns_replaces_and_expires() -> void:
	var bark_ui = load("res://addons/narrative_system/ui/bark_ui.tscn").instantiate()
	bark_ui.lifetime = 0.15
	scene_tree.root.add_child(bark_ui)
	bark_ui.setup(ctx)

	ctx.bark("guard", "Hi!")
	var bubbles := npc.find_children("*", "PanelContainer", true, false)
	assert_eq(bubbles.size(), 1)
	assert_eq((bubbles[0].find_children("BarkLabel", "Label", true, false)[0] as Label).text, "Hi!")

	ctx.bark("guard", "Second")
	await wait_frame()
	bubbles = npc.find_children("*", "PanelContainer", true, false)
	assert_eq(bubbles.size(), 1, "a new bark replaces the previous bubble")
	assert_eq((bubbles[0].find_children("BarkLabel", "Label", true, false)[0] as Label).text, "Second")

	await wait_seconds(0.4)
	assert_eq(npc.find_children("*", "PanelContainer", true, false).size(), 0, "bubble expires")

	ctx.bark("ghost", "no target")  # unregistered actor: warn, no crash
	bark_ui.queue_free()
	await wait_frame()


func test_timed_lines_run_in_parallel() -> void:
	var rec: RefCounted = SignalRecorder.new()
	rec.watch(ctx.sequencer, ["run_finished"])
	ctx.sequencer.start_run("set_variable(\"gold\", 1) @ 0.15\nset_variable(\"met_guard\", true)", "t")
	assert_eq(ctx.state.get_value("met_guard"), true, "sequential thread runs immediately")
	assert_eq(ctx.state.get_value("gold"), 10, "@time line has not fired yet")
	assert_true(ctx.sequencer.is_running(), "run stays alive until scheduled lines finish")
	assert_eq(rec.count("run_finished"), 0)
	await wait_seconds(0.35)
	assert_eq(ctx.state.get_value("gold"), 1, "@time line fired in parallel")
	assert_false(ctx.sequencer.is_running())
	assert_eq(rec.count("run_finished"), 1, "run_finished waits for every job")


func test_timed_zero_runs_at_start() -> void:
	ctx.sequencer.start_run("set_variable(\"gold\", 3) @ 0", "t")
	assert_eq(ctx.state.get_value("gold"), 3, "@0 runs synchronously at run start")
	assert_false(ctx.sequencer.is_running())


func test_notify_releases_message_waiter_synchronously() -> void:
	var rec: RefCounted = SignalRecorder.new()
	rec.watch(ctx.sequencer, ["run_finished", "sequencer_message"])
	ctx.sequencer.start_run("set_variable(\"met_guard\", true) @ message(\"ready\")\nset_variable(\"gold\", 1) -> \"ready\"", "t")
	assert_eq(ctx.state.get_value("gold"), 1)
	assert_eq(ctx.state.get_value("met_guard"), true, "-> released the @message waiter")
	assert_eq(rec.count("sequencer_message"), 1)
	assert_eq(rec.args_of("sequencer_message"), ["ready"])
	assert_eq(rec.count("run_finished"), 1)


func test_send_message_releases_waiter_from_game_code() -> void:
	ctx.sequencer.start_run("set_variable(\"gold\", 42) @ message(\"go\")", "t")
	assert_eq(ctx.state.get_value("gold"), 10, "waiter is pending")
	assert_true(ctx.sequencer.is_running())
	ctx.sequencer.send_message("nope")
	assert_eq(ctx.state.get_value("gold"), 10, "different message does not release it")
	ctx.sequencer.send_message("go")
	assert_eq(ctx.state.get_value("gold"), 42)
	assert_false(ctx.sequencer.is_running())


func test_cancellation_kills_scheduled_lines() -> void:
	ctx.sequencer.start_run("set_variable(\"gold\", 99) @ 0.2\nset_variable(\"met_guard\", true) @ message(\"evt\")", "t")
	ctx.sequencer.cancel_current()
	ctx.sequencer.send_message("evt")
	await wait_seconds(0.4)
	assert_eq(ctx.state.get_value("gold"), 10, "cancelled @time line never fires")
	assert_eq(ctx.state.get_value("met_guard"), false, "cancelled @message waiter never fires")
	assert_false(ctx.sequencer.is_running())


func test_notify_fires_even_for_skipped_command() -> void:
	ctx.sequencer.start_run("definitely_missing(1) -> \"done\"\nset_variable(\"gold\", 7) @ message(\"done\")", "t")
	assert_eq(ctx.state.get_value("gold"), 7, "skipped command still notifies, waiters cannot deadlock")


func test_decoration_parse_error_no_crash() -> void:
	ctx.sequencer.start_run("wait(1) @ oops", "t")
	assert_false(ctx.sequencer.is_running())
	assert_eq(ctx.state.get_value("gold"), 10)


func test_camera_3d_commands() -> void:
	var camera := Camera3D.new()
	scene_tree.root.add_child(camera)
	camera.make_current()
	var npc3d := Node3D.new()
	npc3d.name = "Guard3D"
	scene_tree.root.add_child(npc3d)
	npc3d.global_position = Vector3(10, 0, 0)
	ctx.register_actor("guard3d", npc3d)
	ctx.sequencer.start_run("move_camera_3d(1, 2, 3, 0)", "t")
	assert_eq(camera.global_position, Vector3(1, 2, 3), "instant 3D camera move")
	var position_before: Vector3 = camera.global_position
	ctx.sequencer.start_run("focus_camera(\"guard3d\", 0)", "t")
	assert_eq(camera.global_position, position_before, "3D focus rotates in place")
	var forward := -camera.global_transform.basis.z
	var direction := (npc3d.global_position - camera.global_position).normalized()
	assert_true(forward.dot(direction) > 0.99, "camera aims at the 3D actor")
	camera.queue_free()
	npc3d.queue_free()
	await wait_frame()


func test_bark_bubble_3d_follows_and_expires() -> void:
	var camera := Camera3D.new()
	scene_tree.root.add_child(camera)
	camera.make_current()
	camera.global_position = Vector3(0, 0, 8)  # default orientation looks down -Z
	var npc3d := Node3D.new()
	npc3d.name = "Guard3D"
	scene_tree.root.add_child(npc3d)
	ctx.register_actor("guard3d", npc3d)
	var bark_ui = load("res://addons/narrative_system/ui/bark_ui.tscn").instantiate()
	bark_ui.lifetime = 0.2
	scene_tree.root.add_child(bark_ui)
	bark_ui.setup(ctx)

	ctx.bark("guard3d", "3D!")
	var bubbles: Array[Node] = bark_ui.find_children("*", "PanelContainer", true, false)
	assert_eq(bubbles.size(), 1, "3D bubble is a screen-space child of the BarkUI")
	assert_eq((bubbles[0].find_children("BarkLabel", "Label", true, false)[0] as Label).text, "3D!")
	var bubble: Control = bubbles[0]
	await wait_frame()
	var position_before: Vector2 = bubble.position
	npc3d.global_position = Vector3(3, 0, 0)
	await wait_frame()
	await wait_frame()
	assert_ne(bubble.position, position_before, "bubble follows the projected actor position")

	await wait_seconds(0.45)
	assert_eq(bark_ui.find_children("*", "PanelContainer", true, false).size(), 0, "3D bubble expires")
	bark_ui.queue_free()
	camera.queue_free()
	npc3d.queue_free()
	await wait_frame()

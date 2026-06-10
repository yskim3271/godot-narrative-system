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

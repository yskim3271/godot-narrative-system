extends "res://addons/narrative_system/tests/harness/test_case.gd"
## DialogueRunner: flow, signal order, choices, error paths, re-entrancy.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const SignalRecorder := preload("res://addons/narrative_system/tests/harness/signal_recorder.gd")

const RUNNER_SIGNALS := [
	"dialogue_started", "node_entered", "line_presented",
	"choices_presented", "choice_selected", "dialogue_ended",
]

var ctx: NarrativeContext
var rec: RefCounted


func before_each() -> void:
	ctx = NarrativeContext.create(DbFactory.standard())
	rec = SignalRecorder.new()
	rec.watch(ctx.runner, RUNNER_SIGNALS)


func after_each() -> void:
	# Break test-lambda capture cycles so contexts are freed (no exit leaks).
	disconnect_all_signals(ctx.runner)
	disconnect_all_signals(ctx.state)
	disconnect_all_signals(ctx.localization)
	disconnect_all_signals(ctx)
	ctx = null


func test_linear_dialogue_to_end() -> void:
	assert_true(ctx.runner.start_dialogue("linear"))
	assert_true(ctx.runner.is_dialogue_running())
	assert_eq(ctx.runner.get_current_node().id, "n1")
	assert_eq(ctx.runner.get_current_line_text(), "first")
	assert_true(ctx.runner.advance())
	assert_eq(ctx.runner.get_current_node().id, "n2")
	assert_true(ctx.runner.advance())
	assert_true(ctx.runner.advance())
	assert_false(ctx.runner.is_dialogue_running())
	assert_eq(rec.count("dialogue_ended"), 1)
	assert_eq(rec.args_of("dialogue_ended"), ["linear"])


func test_signal_order_on_start() -> void:
	ctx.runner.start_dialogue("linear")
	assert_eq(rec.names(), ["dialogue_started", "node_entered", "line_presented"] as Array[String])
	assert_eq(rec.args_of("line_presented"), ["guard", "first"])


func test_choice_branching_and_signal_order() -> void:
	ctx.runner.start_dialogue("branch")
	assert_true(ctx.runner.is_waiting_for_choice())
	rec.clear()
	assert_true(ctx.runner.select_choice("stay"))
	assert_eq(
		rec.names(),
		["choice_selected", "node_entered", "line_presented"] as Array[String]
	)
	assert_eq(ctx.runner.get_current_node().id, "good")
	assert_eq(ctx.state.get_value("met_guard"), true, "choice actions ran")


func test_hidden_vs_disabled_choices() -> void:
	ctx.runner.start_dialogue("branch")
	var choices := ctx.runner.get_available_choices()
	assert_eq(choices.size(), 2, "hidden 'secret' choice must not appear")
	assert_eq(choices[0].id, "stay")
	assert_eq(choices[0].enabled, true)
	assert_eq(choices[1].id, "bribe")
	assert_eq(choices[1].enabled, false, "bribe needs gold >= 100, we have 10")
	ctx.runner.end_dialogue()

	# with met_guard, the hidden choice appears; with gold, bribe enables
	ctx.state.set_value("met_guard", true)
	ctx.state.set_value("gold", 150)
	ctx.runner.start_dialogue("branch")
	var updated := ctx.runner.get_available_choices()
	assert_eq(updated.size(), 3)
	assert_eq(updated[1].enabled, true)


func test_select_disabled_or_unknown_choice_fails() -> void:
	ctx.runner.start_dialogue("branch")
	assert_false(ctx.runner.select_choice("bribe"), "disabled choice must be rejected")
	assert_false(ctx.runner.select_choice("nonexistent"))
	assert_true(ctx.runner.is_waiting_for_choice(), "runner stays at choices after rejects")
	assert_false(ctx.runner.advance(), "advance is illegal while enabled choices exist")


func test_unknown_dialogue_id_no_crash() -> void:
	assert_false(ctx.runner.start_dialogue("no_such_dialogue"))
	assert_false(ctx.runner.is_dialogue_running())
	assert_eq(rec.names().size(), 0, "no signals on failed start")
	assert_false(ctx.runner.start_dialogue("linear", "no_such_node"))
	assert_false(ctx.runner.is_dialogue_running())


func test_broken_next_node_ends_dialogue() -> void:
	ctx.runner.start_dialogue("broken")
	assert_true(ctx.runner.advance())
	assert_false(ctx.runner.is_dialogue_running(), "broken link ends the dialogue instead of crashing")
	assert_eq(rec.count("dialogue_ended"), 1)


func test_node_condition_skips_to_next() -> void:
	ctx.runner.start_dialogue("skipper")
	assert_eq(rec.count("node_entered"), 2, "skipped node still emits node_entered")
	assert_eq(rec.args_of("node_entered", 0), ["s1"])
	assert_eq(rec.args_of("node_entered", 1), ["s2"])
	assert_eq(ctx.runner.get_current_line_text(), "landed")
	assert_false(ctx.state.has_seen("skipper", "s1"), "condition-skipped nodes are not 'seen'")
	assert_true(ctx.state.has_seen("skipper", "s2"))


func test_hop_guard_breaks_condition_cycle() -> void:
	assert_true(ctx.runner.start_dialogue("cycle"))
	assert_false(ctx.runner.is_dialogue_running(), "hop guard must end the cyclic dialogue")
	assert_eq(rec.count("dialogue_ended"), 1)


func test_reentrant_advance_drains_iteratively() -> void:
	ctx.runner.line_presented.connect(func(_s: String, _t: String) -> void:
		ctx.runner.advance())
	assert_true(ctx.runner.start_dialogue("chain"))
	assert_false(ctx.runner.is_dialogue_running(), "auto-advance should run the whole chain")
	assert_eq(rec.count("node_entered"), 12)
	assert_eq(rec.count("dialogue_ended"), 1)


func test_pending_queue_is_single_slot() -> void:
	var second_results: Array = []
	ctx.runner.line_presented.connect(func(_s: String, _t: String) -> void:
		ctx.runner.advance()
		second_results.append(ctx.runner.advance()))
	ctx.runner.start_dialogue("linear")
	assert_false(ctx.runner.is_dialogue_running())
	for result in second_results:
		assert_false(result, "second queued advance in one transition must be dropped")


func test_start_during_processing_rejected() -> void:
	var attempted: Array = []
	ctx.runner.node_entered.connect(func(_id: String) -> void:
		if attempted.is_empty():
			attempted.append(ctx.runner.start_dialogue("branch")))
	ctx.runner.start_dialogue("linear")
	assert_eq(attempted, [false])
	assert_eq(ctx.runner.get_current_dialogue_id(), "linear")


func test_seen_nodes_and_first_time_variation() -> void:
	# first run: f1's condition (not has_seen) is true -> "nice to meet you"
	ctx.runner.start_dialogue("firsttime")
	assert_eq(ctx.runner.get_current_line_text(), "nice to meet you")
	ctx.runner.advance()  # to f2
	ctx.runner.advance()  # end
	# second run: f1 was seen -> skips to f2
	ctx.runner.start_dialogue("firsttime")
	assert_eq(ctx.runner.get_current_line_text(), "you again")
	ctx.runner.end_dialogue()


func test_all_choices_hidden_presents_plain_line() -> void:
	ctx.runner.start_dialogue("allhidden")
	assert_false(ctx.runner.is_waiting_for_choice())
	assert_eq(ctx.runner.get_available_choices().size(), 0)
	assert_true(ctx.runner.advance(), "advance acts as the escape for all-hidden choices")
	assert_false(ctx.runner.is_dialogue_running())


func test_node_actions_run_before_presentation() -> void:
	ctx.runner.start_dialogue("actions")
	assert_eq(ctx.state.get_value("gold"), 15)
	assert_eq(ctx.state.get_value("met_guard"), true)
	ctx.runner.end_dialogue()
	assert_eq(rec.count("dialogue_ended"), 1)


func test_state_current_dialogue_tracking() -> void:
	ctx.runner.start_dialogue("branch")
	assert_eq(ctx.state.current_dialogue.dialogue_id, "branch")
	assert_eq(ctx.state.current_dialogue.node_id, "q")
	assert_eq(ctx.state.current_dialogue.phase, "at_choices")
	ctx.runner.select_choice("stay")
	assert_eq(ctx.state.current_dialogue.phase, "at_line")
	ctx.runner.advance()
	assert_true(ctx.state.current_dialogue.is_empty(), "cleared after dialogue ends")

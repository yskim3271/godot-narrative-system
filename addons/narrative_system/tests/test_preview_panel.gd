extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Editor preview panel: sandboxed playback, transcript, choices, language
## switching, sequencer suppression and resource immutability.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const PreviewPanelScript := preload("res://addons/narrative_system/editor/preview_panel.gd")

var db: NarrativeDatabase
var panel: Control


func before_each() -> void:
	db = DbFactory.standard()
	panel = PreviewPanelScript.new()
	scene_tree.root.add_child(panel)
	panel.set_database(db)


func after_each() -> void:
	panel.queue_free()
	await wait_frame()


func _state_tree_texts() -> Array[String]:
	var texts: Array[String] = []
	var tree: Tree = panel._state_tree
	var root := tree.get_root()
	if root == null:
		return texts
	var stack: Array = [root]
	while not stack.is_empty():
		var item: TreeItem = stack.pop_back()
		texts.append("%s=%s" % [item.get_text(0), item.get_text(1)])
		var child := item.get_first_child()
		while child != null:
			stack.append(child)
			child = child.get_next()
	return texts


func test_start_presents_first_line() -> void:
	assert_true(panel.start_preview("linear"))
	assert_true(panel.is_running())
	assert_contains(panel.log_text(), "Guard: first")
	assert_false(panel._next_button.disabled, "plain line -> Next enabled")
	assert_eq(panel.choice_buttons().size(), 0)


func test_advance_to_the_end() -> void:
	panel.start_preview("linear")
	assert_true(panel.advance())
	assert_contains(panel.log_text(), "second")
	panel.advance()
	panel.advance()
	assert_false(panel.is_running())
	assert_contains(panel.log_text(), "— dialogue 'linear' ended —")
	assert_true(panel._next_button.disabled)


func test_choices_render_as_buttons() -> void:
	panel.start_preview("branch")
	var buttons: Array[Button] = panel.choice_buttons()
	assert_eq(buttons.size(), 2, "stay + disabled bribe; secret is hidden")
	assert_false(buttons[0].disabled)
	assert_eq(str(buttons[0].get_meta("choice_id")), "stay")
	assert_true(buttons[1].disabled, "bribe needs gold >= 100")
	assert_true(panel._next_button.disabled, "enabled choices block advance")


func test_select_choice_runs_actions_and_continues() -> void:
	panel.start_preview("branch")
	assert_true(panel.select_choice("stay"))
	assert_contains(panel.log_text(), "▷ stay")
	assert_contains(panel.log_text(), "good end")
	assert_eq(panel.context().state.get_value("met_guard"), true, "choice action ran in the sandbox")
	assert_eq(panel.choice_buttons().size(), 0, "choice buttons cleared after selection")


func test_language_switch_represents_line() -> void:
	panel.start_preview("loctest")
	assert_contains(panel.log_text(), "Hello")
	panel.set_preview_language("ko")
	assert_contains(panel.log_text(), "안녕하세요", "language change re-presents through the runtime path")


func test_sequencer_lines_logged_not_executed() -> void:
	panel.start_preview("seqtest")
	assert_contains(panel.log_text(), "wait(0.3)")
	assert_contains(panel.log_text(), "not executed")
	await wait_seconds(0.35)
	assert_eq(panel.context().state.get_value("gold"), 10, "sequence never ran (no set_variable)")


func test_quest_updates_logged_and_in_state_tree() -> void:
	panel.start_preview("questgiver")
	assert_contains(panel.log_text(), "quest 'rats'")
	assert_true(panel.context().quests.is_quest_active("rats"))
	var texts := _state_tree_texts()
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("rats=active")),
		"quest progress shown in the state tree: %s" % str(texts))
	assert_true(texts.has("gold=10"), "variables shown in the state tree")


func test_restart_gets_fresh_state_and_transcript() -> void:
	panel.start_preview("branch")
	panel.select_choice("stay")
	assert_eq(panel.context().state.get_value("met_guard"), true)
	assert_true(panel.start_preview("branch"))
	assert_eq(panel.context().state.get_value("met_guard"), false, "every run starts on a fresh context")
	assert_false(panel.log_text().contains("good end"), "transcript resets on restart")


func test_stop_preview_drops_context() -> void:
	panel.start_preview("linear")
	panel.stop_preview()
	assert_false(panel.is_running())
	assert_null(panel.context())
	assert_true(panel._next_button.disabled)
	assert_false(panel.advance())


func test_preview_never_mutates_resources() -> void:
	var node := db.get_dialogue("branch").get_node_by_id("q")
	var before := {"text": node.text, "speaker": node.speaker_id, "choices": node.choices.size()}
	panel.start_preview("branch")
	panel.select_choice("stay")
	panel.stop_preview()
	assert_eq(node.text, before.text)
	assert_eq(node.speaker_id, before.speaker)
	assert_eq(node.choices.size(), before.choices)
	assert_eq(db.get_dialogue("branch").get_node_by_id("q").choices[0].text, "choice stay")


func test_objective_completed_logged() -> void:
	panel.start_preview("questgiver")
	panel.context().quests.update_objective("rats", "kill_rats", 5)
	assert_contains(panel.log_text(), "objective 'rats / kill_rats' completed")
	assert_contains(panel.log_text(), "🎯")

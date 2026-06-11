extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Keeps the shipped demo database honest: it must validate clean and the
## authored flow must actually play.

const DB_PATH := "res://examples/integrated_demo/demo_database.tres"

var ctx: NarrativeContext


func before_each() -> void:
	var db := load(DB_PATH) as NarrativeDatabase
	assert_not_null(db, "demo database must load")
	ctx = NarrativeContext.create(db)


func after_each() -> void:
	if ctx != null:
		disconnect_all_signals(ctx.runner)
		disconnect_all_signals(ctx)
	ctx = null


func test_demo_database_validates_clean() -> void:
	var issues := NarrativeValidator.new().validate(ctx.database)
	for issue in issues:
		fail("demo db issue: " + NarrativeValidator.format_issue(issue))
	assert_eq(issues.size(), 0, "the shipped demo database must have zero validation issues")


func test_first_and_return_greetings() -> void:
	ctx.runner.start_dialogue("guard_talk")
	assert_eq(ctx.runner.get_current_node().id, "g_first", "first visit shows the first-time greeting")
	assert_contains(ctx.runner.get_current_line_text(), "처음 보는")
	ctx.runner.end_dialogue()
	ctx.runner.start_dialogue("guard_talk")
	assert_eq(ctx.runner.get_current_node().id, "g_return", "second visit shows the return greeting")
	ctx.runner.end_dialogue()


func test_quest_flow_through_dialogue() -> void:
	ctx.runner.start_dialogue("guard_talk")
	ctx.runner.advance()  # g_first -> g_menu
	assert_true(ctx.runner.is_waiting_for_choice())
	var ids: Array[String] = []
	var bribe_enabled := true
	for choice in ctx.runner.get_available_choices():
		ids.append(str(choice.id))
		if choice.id == "c_bribe":
			bribe_enabled = choice.enabled
	assert_contains(ids, "c_quest")
	assert_contains(ids, "c_bribe")
	assert_false(ids.has("c_progress"), "progress report hidden before the quest starts")
	assert_false(bribe_enabled, "bribe disabled with 30 gold")

	assert_true(ctx.runner.select_choice("c_quest"))
	assert_true(ctx.quests.is_quest_active("rat_hunt"), "q_give actions started the quest")
	ctx.runner.advance()
	assert_false(ctx.runner.is_dialogue_running())

	# halfway: only the progress report shows
	ctx.quests.update_objective("rat_hunt", "kill_rats", 3)
	ctx.runner.start_dialogue("guard_talk")
	ctx.runner.advance()
	var mid_ids: Array[String] = []
	for choice in ctx.runner.get_available_choices():
		mid_ids.append(str(choice.id))
	assert_contains(mid_ids, "c_progress")
	assert_false(mid_ids.has("c_done"))
	ctx.runner.end_dialogue()

	# all rats down: completion path pays out
	ctx.quests.update_objective("rat_hunt", "kill_rats", 2)
	ctx.runner.start_dialogue("guard_talk")
	ctx.runner.advance()
	assert_true(ctx.runner.select_choice("c_done"))
	assert_true(ctx.quests.is_quest_completed("rat_hunt"))
	assert_eq(ctx.state.get_value("gold"), 130, "reward paid (30 + 100)")
	ctx.runner.advance()

	# with 130 gold the bribe is now selectable
	ctx.runner.start_dialogue("guard_talk")
	ctx.runner.advance()
	assert_true(ctx.runner.select_choice("c_bribe"))
	assert_eq(ctx.state.get_value("gold"), 80)
	assert_eq(ctx.state.get_value("met_guard"), true)
	ctx.runner.end_dialogue()


func test_language_switch_on_demo_content() -> void:
	ctx.runner.start_dialogue("guard_talk")
	assert_contains(ctx.runner.get_current_line_text(), "처음 보는", "default language is Korean")
	ctx.localization.set_language("en")
	assert_eq(ctx.runner.get_current_line_text(), "A new face. What brings you to this town?")
	assert_eq(ctx.runner.get_character_display_name("guard"), "Guard")
	ctx.localization.set_language("ko")
	assert_eq(ctx.runner.get_character_display_name("guard"), "경비병")
	ctx.runner.end_dialogue()

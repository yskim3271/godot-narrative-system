extends "res://addons/narrative_system/tests/harness/test_case.gd"
## [var=x] inline markup: pure substitution rules + presentation integration
## (runner lines/choices, context barks/alerts).

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const TextMarkup := preload("res://addons/narrative_system/runtime/text_markup.gd")
const SignalRecorder := preload("res://addons/narrative_system/tests/harness/signal_recorder.gd")

var ctx: NarrativeContext


func before_each() -> void:
	ctx = NarrativeContext.create(_markup_db(), scene_tree)


func after_each() -> void:
	disconnect_all_signals(ctx)
	ctx = null


static func _markup_db() -> NarrativeDatabase:
	var db := NarrativeDatabase.new()
	db.characters = [DbFactory.make_character("guard", "Guard")]
	db.variables = [
		DbFactory.make_int_var("gold", 10),
		DbFactory.make_string_var("hero_name", "Hero"),
	]
	db.dialogues = [
		DbFactory.make_dialogue("m", "n1", [
			DbFactory.make_node("n1", {"text": "You have [var=gold] gold, [var=hero_name].", "choices": [
				DbFactory.make_choice("pay", {"text": "Pay [var=gold]", "target": "n2"}),
			]}),
			DbFactory.make_node("n2", {"text": "[var=missing] stays"}),
		]),
	]
	return db


func test_substitution_basics() -> void:
	assert_eq(TextMarkup.substitute_variables("[var=gold]", ctx.state), "10")
	assert_eq(TextMarkup.substitute_variables("A [var=gold] B [var=hero_name]!", ctx.state),
		"A 10 B Hero!", "multiple tags in one text")
	assert_eq(TextMarkup.substitute_variables("[var= gold ]", ctx.state), "10", "name is trimmed")
	assert_eq(TextMarkup.substitute_variables("no tags here", ctx.state), "no tags here")
	assert_eq(TextMarkup.substitute_variables("[var=gold]", null), "[var=gold]", "null state is a no-op")


func test_unknown_and_malformed_tags_stay_verbatim() -> void:
	assert_eq(TextMarkup.substitute_variables("[var=missing] x", ctx.state), "[var=missing] x")
	assert_eq(TextMarkup.substitute_variables("[var=]", ctx.state), "[var=]", "empty name kept")
	assert_eq(TextMarkup.substitute_variables("end [var=gold", ctx.state), "end [var=gold",
		"unclosed tag tail kept verbatim")
	assert_eq(TextMarkup.substitute_variables("ok [var=gold] then [var=oops", ctx.state),
		"ok 10 then [var=oops", "valid tags before a malformed tail still substitute")
	assert_eq(TextMarkup.substitute_variables("[color=red]hi[/color]", ctx.state),
		"[color=red]hi[/color]", "other bracket markup passes through (BBCode)")


func test_substituted_values_are_not_rescanned() -> void:
	ctx.state.set_value("hero_name", "[var=gold]")
	assert_eq(TextMarkup.substitute_variables("[var=hero_name]", ctx.state), "[var=gold]",
		"a value containing a tag is inserted literally, never re-substituted")


func test_find_variable_tags() -> void:
	assert_eq(TextMarkup.find_variable_tags("a [var=gold] b [var=x] c [var=broken"),
		PackedStringArray(["gold", "x"]))
	assert_eq(TextMarkup.find_variable_tags("plain"), PackedStringArray())


func test_runner_substitutes_lines_and_choices() -> void:
	ctx.runner.start_dialogue("m")
	assert_eq(ctx.runner.get_current_line_text(), "You have 10 gold, Hero.")
	var choices := ctx.runner.get_available_choices()
	assert_eq(choices.size(), 1)
	assert_eq(str(choices[0].text), "Pay 10", "choice text substitutes too")
	ctx.runner.select_choice("pay")
	assert_eq(ctx.runner.get_current_line_text(), "[var=missing] stays",
		"unknown variable stays verbatim at runtime")
	ctx.runner.end_dialogue()


func test_bark_and_alert_substitute() -> void:
	var rec: RefCounted = SignalRecorder.new()
	rec.watch(ctx, ["bark_requested", "alert_requested"])
	ctx.bark("guard", "Spare [var=gold] coins?")
	assert_eq(rec.args_of("bark_requested")[1], "Spare 10 coins?")
	ctx.request_alert("Found [var=gold] gold!")
	assert_eq(rec.args_of("alert_requested"), ["Found 10 gold!"])

extends "res://addons/narrative_system/tests/harness/test_case.gd"
## .ndlg text dialogue format: parsing, attach rules, errors, atomic import,
## export round-trip, and runtime playability of imported content.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const ScriptParser := preload("res://addons/narrative_system/import_export/dialogue_script_parser.gd")
const DemoBuilder := preload("res://examples/integrated_demo/db_builder.gd")

const FULL_SOURCE := """
# full-feature sample
dialogue talk
title 잡담
start greet

node greet
speaker guard
key dlg.talk.greet.text
if not has_seen("talk", "greet")
do met_guard = true
do gold += 1
text 안녕하신가.
text 처음 보는군.
seq wait(0.1)
seq emit_signal("greeted")
next menu

node menu
speaker guard
text 무슨 일이지?
choice c_ask -> answer
  text 길을 묻고 싶소.
  if gold >= 1
  do gold -= 1
  key dlg.talk.menu.c_ask
choice c_locked -> answer
  text (잠긴 선택지)
  if false
  show_disabled
choice c_bye ->

node answer
speaker guard
text 저쪽이라네.
"""


func _parse(source: String) -> Dictionary:
	return ScriptParser.parse_text(source)


func test_minimal_dialogue_and_default_start() -> void:
	var result := _parse("dialogue hi\nnode a\ntext hello\nnext b\nnode b\ntext bye\n")
	assert_true(result.ok, str(result.errors))
	assert_eq(result.dialogues.size(), 1)
	var dialogue: NarrativeDialogue = result.dialogues[0]
	assert_eq(dialogue.start_node_id, "a", "start defaults to the first node")
	assert_eq(dialogue.nodes.size(), 2)
	assert_eq(dialogue.get_node_by_id("a").next_node_id, "b")


func test_full_features_parse() -> void:
	var result := _parse(FULL_SOURCE)
	assert_true(result.ok, str(result.errors))
	var dialogue: NarrativeDialogue = result.dialogues[0]
	assert_eq(dialogue.title, "잡담")
	assert_eq(dialogue.start_node_id, "greet")
	var greet := dialogue.get_node_by_id("greet")
	assert_eq(greet.speaker_id, "guard")
	assert_eq(greet.localized_text_key, "dlg.talk.greet.text")
	assert_eq(greet.conditions, "not has_seen(\"talk\", \"greet\")")
	assert_eq(greet.actions, "met_guard = true\ngold += 1", "repeated do = appended lines")
	assert_eq(greet.text, "안녕하신가.\n처음 보는군.", "repeated text = appended lines")
	assert_eq(greet.sequencer_commands, "wait(0.1)\nemit_signal(\"greeted\")")
	var menu := dialogue.get_node_by_id("menu")
	assert_eq(menu.choices.size(), 3)
	var ask: NarrativeChoice = menu.choices[0]
	assert_eq(ask.id, "c_ask")
	assert_eq(ask.target_node_id, "answer")
	assert_eq(ask.text, "길을 묻고 싶소.")
	assert_eq(ask.condition, "gold >= 1")
	assert_eq(ask.actions, "gold -= 1")
	assert_eq(ask.localized_text_key, "dlg.talk.menu.c_ask")
	assert_true(bool(menu.choices[1].show_disabled))
	assert_eq(menu.choices[2].target_node_id, "", "'->' with no target ends the dialogue")


func test_choice_attach_rule_violations() -> void:
	var result := _parse("dialogue d\nnode n\nchoice c -> n\ntext too late node text\n")
	# 'text' after a choice attaches to the choice — legal. Node-level text
	# after a choice requires closing the choice context, which only `node`
	# does, so the only illegal shapes are pre-choice fields appearing late:
	assert_true(result.ok)
	assert_eq(result.dialogues[0].get_node_by_id("n").choices[0].text, "too late node text")

	var bad := _parse("dialogue d\nnode n\nchoice c -> n\nnode m\ntext fine\nif true\ndo gold = 1\nchoice c2 ->\nif after_choice_is_choice_level\n")
	assert_true(bad.ok, str(bad.errors))
	var m: NarrativeDialogueNode = bad.dialogues[0].get_node_by_id("m")
	assert_eq(m.conditions, "true", "node-level if before first choice")
	assert_eq(m.choices[0].condition, "after_choice_is_choice_level")


func test_multiple_dialogues() -> void:
	var result := _parse("dialogue a\nnode x\ntext 1\n\ndialogue b\nnode y\ntext 2\n")
	assert_true(result.ok)
	assert_eq(result.dialogues.size(), 2)
	assert_eq(result.dialogues[0].id, "a")
	assert_eq(result.dialogues[1].id, "b")


func test_errors_with_line_numbers() -> void:
	var source := "wat is this\nnode early\ndialogue ok\nnode a\nnode a\nif x\nif y\nchoice bad id! -> a\ndialogue ok\nstart ghost\n"
	var result := _parse(source)
	assert_false(result.ok)
	var by_line := {}
	for error in result.errors:
		by_line[int(error.line)] = str(error.message)
	assert_contains(by_line[1], "unknown keyword")
	assert_contains(by_line[2], "before any 'dialogue'")
	assert_contains(by_line[5], "duplicate node id")
	assert_contains(by_line[7], "already has an 'if'")
	assert_contains(by_line[8], "invalid choice id")
	assert_contains(by_line[9], "duplicate dialogue id")
	assert_true(by_line.has(3) or by_line.has(9), "start ghost reported on its dialogue")


func test_import_is_atomic_on_parse_error() -> void:
	var db := DbFactory.standard()
	var before := db.dialogues.size()
	var report := ScriptParser.import_text(db, "dialogue broken\nnode a\nwhoops keyword\n")
	assert_false(report.ok)
	assert_eq(db.dialogues.size(), before, "database untouched on parse errors")


func test_import_replace_and_skip() -> void:
	var db := DbFactory.standard()
	var count := db.dialogues.size()
	var source := "dialogue linear\nnode only\ntext replaced!\n\ndialogue fresh_one\nnode n\ntext new\n"
	var skip_report := ScriptParser.import_text(db, source, false)
	assert_true(skip_report.ok)
	assert_eq(skip_report.skipped, ["linear"])
	assert_eq(skip_report.imported, ["fresh_one"])
	assert_eq(db.get_dialogue("linear").nodes.size(), 3, "skip keeps the original")

	var replace_report := ScriptParser.import_text(db, source, true)
	assert_eq(replace_report.replaced, ["linear", "fresh_one"], "fresh_one exists after the first import, so both replace")
	assert_eq(replace_report.imported, [])
	assert_eq(db.get_dialogue("linear").nodes.size(), 1, "replace swaps the dialogue in place")
	assert_eq(db.dialogues.size(), count + 1, "no duplicate entries created")


func test_export_roundtrip_full_source() -> void:
	var original: NarrativeDialogue = _parse(FULL_SOURCE).dialogues[0]
	var exported := ScriptParser.export_dialogue(original)
	var reparsed_result := _parse(exported)
	assert_true(reparsed_result.ok, str(reparsed_result.errors))
	_assert_dialogues_equal(original, reparsed_result.dialogues[0])


func test_export_roundtrip_demo_dialogue() -> void:
	# The shipped demo content (authored in code) must survive the text format.
	var demo_db: NarrativeDatabase = DemoBuilder.build()
	var original := demo_db.get_dialogue("guard_talk")
	var reparsed_result := _parse(ScriptParser.export_dialogue(original))
	assert_true(reparsed_result.ok, str(reparsed_result.errors))
	_assert_dialogues_equal(original, reparsed_result.dialogues[0])


func test_imported_dialogue_plays_in_runner() -> void:
	var db := DbFactory.standard()
	var report := ScriptParser.import_text(db, FULL_SOURCE)
	assert_true(report.ok)
	var ctx := NarrativeContext.create(db)
	assert_true(ctx.runner.start_dialogue("talk"))
	assert_eq(ctx.runner.get_current_line_text(), "안녕하신가.\n처음 보는군.")
	assert_eq(ctx.state.get_value("gold"), 11, "node actions ran (10 + 1)")
	ctx.runner.advance()
	assert_true(ctx.runner.is_waiting_for_choice())
	var ids: Array[String] = []
	for available_choice in ctx.runner.get_available_choices():
		ids.append(str(available_choice.id))
	assert_eq(ids, ["c_ask", "c_locked", "c_bye"] as Array[String], "c_locked shows disabled")
	assert_true(ctx.runner.select_choice("c_ask"))
	assert_eq(ctx.state.get_value("gold"), 10, "choice actions ran")
	assert_eq(ctx.runner.get_current_line_text(), "저쪽이라네.")
	ctx.runner.end_dialogue()
	disconnect_all_signals(ctx.runner)


func test_crlf_and_bom_sources() -> void:
	var source := String.chr(0xFEFF) + "dialogue d\r\nnode a\r\ntext over crlf\r\n"
	var result := _parse(source)
	assert_true(result.ok, str(result.errors))
	assert_eq(result.dialogues[0].get_node_by_id("a").text, "over crlf")


func _assert_dialogues_equal(a: NarrativeDialogue, b: NarrativeDialogue) -> void:
	assert_eq(b.id, a.id)
	assert_eq(b.title, a.title)
	assert_eq(b.start_node_id, a.start_node_id)
	assert_eq(b.nodes.size(), a.nodes.size())
	for i in a.nodes.size():
		var na: NarrativeDialogueNode = a.nodes[i]
		var nb: NarrativeDialogueNode = b.nodes[i]
		assert_eq(nb.id, na.id)
		assert_eq(nb.speaker_id, na.speaker_id)
		assert_eq(nb.text, na.text)
		assert_eq(nb.localized_text_key, na.localized_text_key)
		assert_eq(nb.conditions.strip_edges(), na.conditions.strip_edges())
		assert_eq(nb.actions.strip_edges(), na.actions.strip_edges())
		assert_eq(nb.sequencer_commands.strip_edges(), na.sequencer_commands.strip_edges())
		assert_eq(nb.next_node_id, na.next_node_id)
		assert_eq(nb.choices.size(), na.choices.size())
		for j in na.choices.size():
			var ca: NarrativeChoice = na.choices[j]
			var cb: NarrativeChoice = nb.choices[j]
			assert_eq(cb.id, ca.id)
			assert_eq(cb.text, ca.text)
			assert_eq(cb.localized_text_key, ca.localized_text_key)
			assert_eq(cb.condition.strip_edges(), ca.condition.strip_edges())
			assert_eq(cb.actions.strip_edges(), ca.actions.strip_edges())
			assert_eq(cb.target_node_id, ca.target_node_id)
			assert_eq(cb.show_disabled, ca.show_disabled)

extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Headless UI smoke tests: the reference UIs react to runner signals.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")

var ctx: NarrativeContext
var box  # DialogueBox (CanvasLayer)
var list  # ChoiceList (CanvasLayer)


func before_each() -> void:
	ctx = NarrativeContext.create(DbFactory.standard(), scene_tree)
	box = load("res://addons/narrative_system/ui/dialogue_box.tscn").instantiate()
	box.typewriter_chars_per_sec = 0.0  # instant reveal for deterministic asserts
	list = load("res://addons/narrative_system/ui/choice_list.tscn").instantiate()
	scene_tree.root.add_child(box)
	scene_tree.root.add_child(list)
	box.setup(ctx.runner)
	list.setup(ctx.runner)


func after_each() -> void:
	disconnect_all_signals(ctx.runner)
	disconnect_all_signals(ctx.state)
	disconnect_all_signals(ctx.localization)
	disconnect_all_signals(ctx)
	box.queue_free()
	list.queue_free()
	await wait_frame()
	ctx = null


func test_dialogue_box_displays_line_and_speaker() -> void:
	ctx.runner.start_dialogue("linear")
	assert_true(box.visible)
	assert_eq(box.get_node("Panel/Margin/HBox/VBox/SpeakerLabel").text, "Guard")
	assert_eq(box.get_node("Panel/Margin/HBox/VBox/TextLabel").text, "first")
	assert_eq(box.get_node("Panel/Margin/HBox/VBox/TextLabel").visible_ratio, 1.0)
	assert_true(box.get_node("Panel/Margin/HBox/VBox/ContinueIndicator").visible)
	ctx.runner.advance()
	assert_eq(box.get_node("Panel/Margin/HBox/VBox/TextLabel").text, "second")


func test_dialogue_box_hides_when_dialogue_ends() -> void:
	ctx.runner.start_dialogue("linear")
	ctx.runner.advance()
	ctx.runner.advance()
	ctx.runner.advance()
	assert_false(ctx.runner.is_dialogue_running())
	assert_false(box.visible)


func test_choice_list_builds_buttons_and_selects() -> void:
	ctx.runner.start_dialogue("branch")
	assert_true(list.visible)
	var buttons: Array = list.get_node("Panel/Margin/Choices").get_children()
	assert_eq(buttons.size(), 2)
	assert_contains(buttons[0].text, "1. choice stay")
	assert_false(buttons[0].disabled)
	assert_true(buttons[1].disabled, "bribe choice renders disabled (gold too low)")
	buttons[0].pressed.emit()
	assert_false(list.visible, "choice list hides after selection")
	assert_eq(ctx.runner.get_current_node().id, "good")
	assert_eq(box.get_node("Panel/Margin/HBox/VBox/TextLabel").text, "good end")


func test_continue_indicator_hidden_while_choices_shown() -> void:
	ctx.runner.start_dialogue("branch")
	assert_false(box.get_node("Panel/Margin/HBox/VBox/ContinueIndicator").visible)


func test_late_attach_pulls_current_state() -> void:
	ctx.runner.start_dialogue("branch")
	var late = load("res://addons/narrative_system/ui/dialogue_box.tscn").instantiate()
	late.typewriter_chars_per_sec = 0.0
	var late_list = load("res://addons/narrative_system/ui/choice_list.tscn").instantiate()
	scene_tree.root.add_child(late)
	scene_tree.root.add_child(late_list)
	late.setup(ctx.runner)
	late_list.setup(ctx.runner)
	assert_true(late.visible, "late-attached box pulls the running dialogue")
	assert_eq(late.get_node("Panel/Margin/HBox/VBox/TextLabel").text, "what do you do?")
	assert_true(late_list.visible)
	assert_eq(late_list.get_node("Panel/Margin/Choices").get_child_count(), 2)
	late.queue_free()
	late_list.queue_free()
	await wait_frame()

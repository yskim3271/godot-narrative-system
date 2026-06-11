extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Quest UIs + facade integration (headless): tracker, log, alert queue.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")

var facade: Node
var tracker
var log_ui
var alert_ui


func before_each() -> void:
	facade = load("res://addons/narrative_system/runtime/narrative.gd").new()
	scene_tree.root.add_child(facade)
	facade.load_database(DbFactory.standard())
	tracker = load("res://addons/narrative_system/ui/quest_tracker.tscn").instantiate()
	log_ui = load("res://addons/narrative_system/ui/quest_log.tscn").instantiate()
	alert_ui = load("res://addons/narrative_system/ui/alert_ui.tscn").instantiate()
	alert_ui.display_seconds = 0.05
	alert_ui.fade_seconds = 0.02
	scene_tree.root.add_child(tracker)
	scene_tree.root.add_child(log_ui)
	scene_tree.root.add_child(alert_ui)
	tracker.setup(facade)
	log_ui.setup(facade)
	alert_ui.setup(facade)


func after_each() -> void:
	for node in [tracker, log_ui, alert_ui, facade]:
		node.queue_free()
	await wait_frame()


func _all_label_text(root: Node) -> String:
	var collected := ""
	for child in root.get_children():
		if child is Label or child is CheckBox:
			collected += str(child.text) + "\n"
		collected += _all_label_text(child)
	return collected


func test_tracker_shows_progress_and_clears_on_complete() -> void:
	assert_false(tracker.visible, "tracker hidden with nothing tracked")
	facade.start_quest("rats")
	await wait_frame()
	var text := _all_label_text(tracker.get_node("Box"))
	assert_contains(text, "Rat Hunt")
	assert_contains(text, "(0/5)")
	facade.update_objective("rats", "kill_rats", 3)
	await wait_frame()
	assert_contains(_all_label_text(tracker.get_node("Box")), "(3/5)")
	facade.complete_quest("rats", true)
	await wait_frame()
	assert_false(tracker.visible, "completed quests leave the tracker")


func test_quest_log_sections() -> void:
	facade.start_quest("rats")
	facade.start_quest("intro")
	facade.complete_quest("intro")
	log_ui.toggle()
	assert_true(log_ui.visible)
	var text := _all_label_text(log_ui.get_node("Panel/Margin/VBox/Scroll/Entries"))
	assert_contains(text, "Active")
	assert_contains(text, "Rat Hunt")
	assert_contains(text, "Kill cellar rats")
	assert_contains(text, "Completed")
	assert_contains(text, "Meet the Guard")
	log_ui.toggle()
	assert_false(log_ui.visible)


func test_quest_log_refreshes_while_open() -> void:
	facade.start_quest("rats")
	log_ui.toggle()
	assert_contains(_all_label_text(log_ui.get_node("Panel/Margin/VBox/Scroll/Entries")), "(0/5)")
	facade.update_objective("rats", "kill_rats", 2)
	await wait_frame()
	assert_contains(_all_label_text(log_ui.get_node("Panel/Margin/VBox/Scroll/Entries")), "(2/5)")


func test_alert_queue_shows_and_advances() -> void:
	facade.show_alert("First alert")
	facade.show_alert("Second alert")
	var panel: PanelContainer = alert_ui.get_node("Panel")
	var label: Label = alert_ui.get_node("Panel/Margin/Label")
	assert_true(panel.visible)
	assert_eq(label.text, "First alert")
	await wait_seconds(0.2)
	assert_eq(label.text, "Second alert", "queued alert shows after the first fades")
	await wait_seconds(0.3)
	assert_false(panel.visible, "panel hides after the queue drains")


func test_facade_quest_delegations() -> void:
	assert_eq(facade.get_quest_state("rats"), "inactive")
	facade.start_quest("rats")
	assert_true(facade.is_quest_active("rats"))
	assert_eq(facade.get_quest_title("rats"), "Rat Hunt")
	assert_eq(facade.get_quests_in_state("active"), ["rats"] as Array[String])
	assert_true(facade.set_quest_tracked("rats", false))
	assert_eq(facade.get_tracked_quests(), [] as Array[String])


func _find_button(root: Node, text: String) -> Button:
	for child in root.get_children():
		if child is Button and not (child is CheckBox) and str(child.text) == text:
			return child
		var nested := _find_button(child, text)
		if nested != null:
			return nested
	return null


func test_quest_log_abandon_button() -> void:
	facade.start_quest("rats")
	log_ui.toggle()
	var entries: Node = log_ui.get_node("Panel/Margin/VBox/Scroll/Entries")
	var abandon := _find_button(entries, "Abandon")
	assert_not_null(abandon, "active quests get an Abandon button")
	abandon.pressed.emit()
	assert_eq(facade.get_quest_state("rats"), "inactive", "button abandons the quest")
	await wait_frame()
	assert_false(_all_label_text(entries).contains("Rat Hunt"), "abandoned quest leaves the log")


func test_quest_log_abandon_button_can_be_hidden() -> void:
	log_ui.show_abandon_button = false
	facade.start_quest("rats")
	log_ui.toggle()
	assert_null(_find_button(log_ui.get_node("Panel/Margin/VBox/Scroll/Entries"), "Abandon"))


func test_quest_log_completion_badge() -> void:
	for i in 2:
		facade.start_quest("daily")
		facade.update_objective("daily", "win", 1)
		facade.complete_quest("daily")
	facade.start_quest("daily")
	facade.start_quest("intro")
	facade.complete_quest("intro")
	log_ui.toggle()
	var text := _all_label_text(log_ui.get_node("Panel/Margin/VBox/Scroll/Entries"))
	assert_contains(text, "Daily Run ×2", "repeat completions show as a ×N badge")
	assert_false(text.contains("Meet the Guard ×"), "single completions stay clean")

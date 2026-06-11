extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Bottom panel wiring: validation/localization double-click -> structured ref
## -> focus_reference -> graph editor jump. (Panels are built off-tree; the
## graph editor goes in-tree like the other UI tests. EditorInterface paths
## are guarded by is_editor_hint and never run here.)

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const ValidationPanelScript := preload("res://addons/narrative_system/editor/validation_panel.gd")
const LocalizationPanelScript := preload("res://addons/narrative_system/editor/localization_panel.gd")
const NarrativePanelScript := preload("res://addons/narrative_system/editor/narrative_panel.gd")
const GraphEditorScript := preload("res://addons/narrative_system/editor/dialogue_graph_editor.gd")

var db: NarrativeDatabase


func before_each() -> void:
	db = DbFactory.standard()


func test_validation_double_click_emits_parsed_ref() -> void:
	var panel: Control = ValidationPanelScript.new()
	var received: Array = []
	panel.set_focus_handler(func(ref: Dictionary) -> void: received.append(ref))
	var issues: Array[Dictionary] = [
		{"severity": "error", "code": "broken_link",
			"message": "next_node_id 'x' does not exist",
			"where": "dialogue 'branch' > node 'q'"},
		{"severity": "warning", "code": "missing_localization_key",
			"message": "key missing", "where": "quest 'rats' > objective 'kill_rats'"},
	]
	panel.show_issues(issues)
	panel._on_item_activated(0)
	panel._on_item_activated(1)
	assert_eq(received.size(), 2)
	assert_eq(str(received[0].category), "dialogue")
	assert_eq(str(received[0].node), "q")
	assert_eq(str(received[1].category), "quest")
	assert_eq(str(received[1].objective), "kill_rats")
	panel.free()


func test_localization_panel_rows_filter_and_activation() -> void:
	var panel: Control = LocalizationPanelScript.new()
	var received: Array = []
	panel.set_focus_handler(func(ref: Dictionary) -> void: received.append(ref))
	panel.show_database(db)
	var all_rows: Array[Dictionary] = panel.visible_rows()
	assert_true(all_rows.size() > 0, "standard fixture has ko gaps")

	# locale filter: "en" shows nothing (inline text covers the default language)
	for i in panel._filter.item_count:
		if panel._filter.get_item_text(i) == "en":
			panel._filter.select(i)
	panel._rebuild_list()
	assert_eq(panel.visible_rows().size(), 0, "no en gaps in the standard fixture")
	for i in panel._filter.item_count:
		if panel._filter.get_item_text(i) == "ko":
			panel._filter.select(i)
	panel._rebuild_list()
	assert_eq(panel.visible_rows().size(), all_rows.size())

	# double-click forwards the row's ref
	var first: TreeItem = panel._list.get_root().get_first_child()
	first.select(0)
	panel._on_item_activated()
	assert_eq(received.size(), 1)
	assert_true((received[0] as Dictionary).has("category"))
	panel.free()


func test_focus_reference_jumps_graph_editor() -> void:
	var graph: Control = GraphEditorScript.new()
	scene_tree.root.add_child(graph)
	graph.set_database(db)
	var panel: Control = NarrativePanelScript.new()
	panel._db = db
	panel.set_graph_editor(graph)

	panel.focus_reference({"category": "dialogue", "id": "linear", "node": "n2"})
	assert_eq(graph.current_dialogue().id, "linear")
	var gnode: GraphNode = graph.get_graph_edit().get_node(
		NodePath(String(graph.graph_name_for("n2"))))
	assert_true(gnode.selected)
	assert_contains(panel._status.text, "focused")

	# non-graph refs resolve without touching the graph view
	panel.focus_reference({"category": "quest", "id": "rats"})
	assert_eq(graph.current_dialogue().id, "linear", "quest focus leaves the graph alone")

	# unresolvable refs report an error status
	panel.focus_reference({"category": "dialogue", "id": "ghost"})
	assert_contains(panel._status.text, "cannot focus")

	panel.free()
	graph.queue_free()
	await wait_frame()

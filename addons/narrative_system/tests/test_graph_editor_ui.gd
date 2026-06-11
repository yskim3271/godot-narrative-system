extends "res://addons/narrative_system/tests/harness/test_case.gd"
## GraphEdit shell: node spawning, port wiring, gesture handlers.
## (Runs headless: the editor control guards all EditorInterface usage.)

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const GraphEditorScript := preload("res://addons/narrative_system/editor/dialogue_graph_editor.gd")
const GraphModel := preload("res://addons/narrative_system/editor/dialogue_graph_model.gd")

var db: NarrativeDatabase
var editor: Control


func before_each() -> void:
	db = DbFactory.standard()
	editor = GraphEditorScript.new()
	scene_tree.root.add_child(editor)
	editor.set_database(db)
	editor.open_dialogue("branch")


func after_each() -> void:
	editor.queue_free()
	await wait_frame()


func _graph_nodes() -> Array:
	var result: Array = []
	for child in editor.get_graph_edit().get_children():
		if child is GraphNode:
			result.append(child)
	return result


func _gnode(node_id: String) -> GraphNode:
	return editor.get_graph_edit().get_node(NodePath(String(editor.graph_name_for(node_id))))


func test_open_builds_nodes_ports_and_connections() -> void:
	assert_eq(_graph_nodes().size(), 4, "branch has 4 nodes")
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 3, "3 choice links")
	var q := _gnode("q")
	assert_not_null(q)
	assert_true(q.is_slot_enabled_left(0), "header row takes incoming links")
	assert_true(q.is_slot_enabled_right(0), "header row exposes the next port")
	assert_false(q.is_slot_enabled_right(1), "text preview row has no port")
	for slot in [2, 3, 4]:
		assert_true(q.is_slot_enabled_right(slot), "one output port per choice")
	assert_true(q.title.begins_with("▶"), "start node is marked")
	assert_false(_gnode("good").title.begins_with("▶"))


func test_connection_request_updates_next_and_choice() -> void:
	editor._on_connection_request(editor.graph_name_for("good"), 0, editor.graph_name_for("rich"), 0)
	assert_eq(db.get_dialogue("branch").get_node_by_id("good").next_node_id, "rich")
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 4)
	# rewire choice 'stay' (port 1) from good to rich
	editor._on_connection_request(editor.graph_name_for("q"), 1, editor.graph_name_for("rich"), 0)
	assert_eq(db.get_dialogue("branch").get_node_by_id("q").choices[0].target_node_id, "rich")
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 4, "rewiring replaces, not adds")


func test_disconnection_request_clears_data() -> void:
	editor._on_disconnection_request(editor.graph_name_for("q"), 1, editor.graph_name_for("good"), 0)
	assert_eq(db.get_dialogue("branch").get_node_by_id("q").choices[0].target_node_id, "")
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 2)


func test_add_node_via_editor() -> void:
	var node = editor.add_node_at(Vector2(500, 300))
	assert_not_null(node)
	assert_eq(_graph_nodes().size(), 5)
	assert_eq(db.get_dialogue("branch").nodes.size(), 5)
	assert_not_null(_gnode(node.id))
	assert_eq(_gnode(node.id).position_offset, Vector2(500, 300))


func test_delete_request_removes_and_cleans() -> void:
	editor._on_delete_nodes_request([editor.graph_name_for("good")])
	assert_eq(db.get_dialogue("branch").nodes.size(), 3)
	assert_eq(db.get_dialogue("branch").get_node_by_id("q").choices[0].target_node_id, "", "stay's dangling target cleared")
	assert_eq(_graph_nodes().size(), 3)
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 2)


func test_set_selection_as_start() -> void:
	_gnode("good").selected = true
	editor.set_selection_as_start()
	assert_eq(db.get_dialogue("branch").start_node_id, "good")
	assert_true(_gnode("good").title.begins_with("▶"))
	assert_false(_gnode("q").title.begins_with("▶"))


func test_end_node_move_persists_positions() -> void:
	# GraphEdit emits begin_node_move, the user drags, then end_node_move.
	editor._on_begin_node_move()
	var gnode := _gnode("rich")
	gnode.position_offset = Vector2(777, 333)
	editor._on_end_node_move()
	assert_eq(GraphModel.get_position(db.get_dialogue("branch").get_node_by_id("rich")), Vector2(777, 333))


func test_inline_controls_present_and_direct_rename() -> void:
	# No undo manager is injected here, so edits apply directly — the standalone
	# path must still mutate the model (and retarget links on rename).
	var gnode := _gnode("good")
	assert_true(gnode.has_meta("speaker_edit"), "speaker is inline-editable")
	assert_true(gnode.has_meta("text_edit"), "text is inline-editable")
	assert_true(gnode.has_meta("id_edit"), "id is inline-editable (rename)")
	var id_ctrl: LineEdit = gnode.get_meta("id_edit")
	id_ctrl.set_meta("edit_before", "good")
	id_ctrl.text = "ending"
	editor._commit_rename(id_ctrl, "good")
	assert_true(db.get_dialogue("branch").has_node_id("ending"))
	assert_eq(db.get_dialogue("branch").get_node_by_id("q").choices[0].target_node_id, "ending",
		"link retargeted even without an undo manager")


func test_fills_container_parent_so_graph_gets_height() -> void:
	# The editor main screen is a Container that ignores anchors and sizes
	# children by size flags. A fresh editor must EXPAND_FILL, otherwise it
	# collapses to its minimum height inside the container and the GraphEdit
	# gets ZERO height — every node is then spawned into an invisible canvas.
	# Regression: shipped 1.0.0 relied on FULL_RECT anchors alone, so the
	# graph editor showed an empty canvas in the actual editor main screen.
	var fresh: Control = GraphEditorScript.new()
	assert_eq(fresh.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "must fill container width")
	assert_eq(fresh.size_flags_vertical, Control.SIZE_EXPAND_FILL, "must fill container height")
	var box := VBoxContainer.new()
	box.size = Vector2(800, 600)
	scene_tree.root.add_child(box)
	box.add_child(fresh)
	fresh.set_database(db)
	fresh.open_dialogue("branch")
	await wait_frame()
	await wait_frame()
	assert_true(fresh.get_graph_edit().size.y > 100.0,
		"GraphEdit must receive real height inside a Container (got %s)" % fresh.get_graph_edit().size)
	box.queue_free()
	await wait_frame()


func test_choice_inline_fields_and_target_sync_on_drag() -> void:
	var q := _gnode("q")
	assert_true(q.has_meta("choice_text_0"), "choice text is inline-editable")
	assert_true(q.has_meta("choice_target_0"), "choice target is inline-editable")
	assert_eq((q.get_meta("choice_text_0") as LineEdit).text, "choice stay", "raw authoring text shown")
	assert_eq((q.get_meta("choice_target_0") as LineEdit).text, "good")
	# rewiring by port drag pushes the new target into the inline field
	editor._on_connection_request(editor.graph_name_for("q"), 1, editor.graph_name_for("rich"), 0)
	assert_eq((q.get_meta("choice_target_0") as LineEdit).text, "rich")
	# standalone (no undo manager) inline commit still mutates the model
	var ctext: LineEdit = q.get_meta("choice_text_0")
	ctext.set_meta("edit_before", "choice stay")
	ctext.text = "renamed inline"
	editor._commit_choice_text(ctext, "q", 0)
	assert_eq(db.get_dialogue("branch").get_node_by_id("q").choices[0].text, "renamed inline")


func test_markup_insert_helpers() -> void:
	# TextEdit: a selection becomes the variable name
	var text_edit: TextEdit = _gnode("good").get_meta("text_edit")
	text_edit.text = "good end"
	text_edit.select(0, 0, 0, 4)
	editor.insert_var_markup(text_edit)
	assert_eq(text_edit.text, "[var=good] end")
	# TextEdit: no selection parks the caret before the closing bracket
	text_edit.text = ""
	text_edit.set_caret_line(0)
	text_edit.set_caret_column(0)
	editor.insert_var_markup(text_edit)
	assert_eq(text_edit.text, "[var=]")
	assert_eq(text_edit.get_caret_column(), 5, "caret sits before ']' ready for the name")
	# LineEdit: color wrap without selection lands the caret between the tags
	var ctext: LineEdit = _gnode("q").get_meta("choice_text_0")
	ctext.text = ""
	ctext.caret_column = 0
	editor.wrap_color_markup(ctext)
	assert_eq(ctext.text, "[color=yellow][/color]")
	assert_eq(ctext.caret_column, "[color=yellow]".length())
	# LineEdit: wrapping a selection keeps it as the tag body
	ctext.text = "pay"
	ctext.select(0, 3)
	editor.wrap_color_markup(ctext)
	assert_eq(ctext.text, "[color=yellow]pay[/color]")


func test_switching_dialogues_rebuilds() -> void:
	assert_true(editor.open_dialogue("linear"))
	assert_eq(_graph_nodes().size(), 3)
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 2, "n1->n2->n3 next links")
	assert_false(editor.open_dialogue("ghost_dialogue"))
	assert_eq(editor.current_dialogue().id, "linear", "failed open keeps the current dialogue")


func test_focus_node_switches_dialogue_and_selects() -> void:
	assert_true(editor.focus_node("linear", "n2"), "focus from another dialogue")
	assert_eq(editor.current_dialogue().id, "linear")
	assert_true(_gnode("n2").selected)
	assert_false(_gnode("n1").selected, "focus selects exactly one node")
	assert_true(editor.focus_node("linear", "n3"))
	assert_false(_gnode("n2").selected, "previous focus target deselected")
	assert_true(_gnode("n3").selected)


func test_focus_node_dialogue_only_and_unknown_targets() -> void:
	assert_true(editor.focus_node("linear"), "empty node id just opens the dialogue")
	assert_eq(editor.current_dialogue().id, "linear")
	assert_false(editor.focus_node("ghost_dialogue"))
	assert_eq(editor.current_dialogue().id, "linear", "failed focus keeps the current dialogue")
	assert_false(editor.focus_node("branch", "ghost_node"), "unknown node reports failure")
	assert_eq(editor.current_dialogue().id, "branch", "the dialogue itself still opened")

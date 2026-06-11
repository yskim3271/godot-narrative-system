extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Graph editor undo/redo: every structural op must round-trip through
## its registered undo (and redo) methods. Uses a stub with the same
## create_action/add_do_method/add_undo_method/commit_action surface as
## EditorUndoRedoManager (which only exists inside the editor).

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const GraphEditorScript := preload("res://addons/narrative_system/editor/dialogue_graph_editor.gd")
const GraphModel := preload("res://addons/narrative_system/editor/dialogue_graph_model.gd")

var db: NarrativeDatabase
var branch: NarrativeDialogue
var editor: Control
var undo: RefCounted


class UndoStub:
	extends RefCounted
	var actions: Array = []  # {name, do: [[obj, method, payload]], undo: [...]}
	var _building: Dictionary = {}

	func create_action(action_name: String, _merge_mode := 0, _context: Object = null, _backward := false) -> void:
		_building = {"name": action_name, "do": [], "undo": []}

	func add_do_method(object: Object, method: StringName, payload: Dictionary) -> void:
		_building.do.append([object, method, payload])

	func add_undo_method(object: Object, method: StringName, payload: Dictionary) -> void:
		_building.undo.append([object, method, payload])

	func commit_action(execute := true) -> void:
		actions.append(_building)
		if execute:
			for op in _building.do:
				op[0].call(op[1], op[2])
		_building = {}

	func undo_last() -> void:
		var action: Dictionary = actions[-1]
		for i in range(action.undo.size() - 1, -1, -1):
			var op: Array = action.undo[i]
			op[0].call(op[1], op[2])

	func redo_last() -> void:
		var action: Dictionary = actions[-1]
		for op in action.do:
			op[0].call(op[1], op[2])


func before_each() -> void:
	db = DbFactory.standard()
	branch = db.get_dialogue("branch")
	editor = GraphEditorScript.new()
	scene_tree.root.add_child(editor)
	undo = UndoStub.new()
	editor.set_undo_redo(undo)
	editor.set_database(db)
	editor.open_dialogue("branch")


func after_each() -> void:
	editor.queue_free()
	await wait_frame()


func _graph_count() -> int:
	var count := 0
	for child in editor.get_graph_edit().get_children():
		if child is GraphNode:
			count += 1
	return count


func test_add_node_undo_redo() -> void:
	var node = editor.add_node_at(Vector2(400, 400))
	assert_eq(undo.actions.size(), 1)
	assert_eq(branch.nodes.size(), 5)
	assert_eq(_graph_count(), 5)
	undo.undo_last()
	assert_eq(branch.nodes.size(), 4, "undo removes the added node")
	assert_false(branch.has_node_id(node.id))
	assert_eq(_graph_count(), 4)
	undo.redo_last()
	assert_eq(branch.nodes.size(), 5, "redo restores it")
	assert_true(branch.has_node_id(node.id))


func test_delete_undo_restores_links_and_start() -> void:
	# delete the start node 'q' (3 outgoing choice links live on it; incoming none)
	# and 'good' (incoming choice link from q) in one gesture
	editor._on_delete_nodes_request([
		editor.graph_name_for("q"), editor.graph_name_for("good"),
	])
	assert_eq(branch.nodes.size(), 2)
	assert_eq(branch.start_node_id, "")
	undo.undo_last()
	assert_eq(branch.nodes.size(), 4, "both nodes restored")
	assert_eq(branch.start_node_id, "q", "start restored")
	var q := branch.get_node_by_id("q")
	assert_eq(q.choices[0].target_node_id, "good", "choice link into restored node re-established")
	assert_eq(q.choices[1].target_node_id, "rich", "untouched links survive")
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 3, "canvas matches data again")


func test_connect_disconnect_undo() -> void:
	editor._on_connection_request(editor.graph_name_for("good"), 0, editor.graph_name_for("rich"), 0)
	assert_eq(branch.get_node_by_id("good").next_node_id, "rich")
	undo.undo_last()
	assert_eq(branch.get_node_by_id("good").next_node_id, "", "connect undone")
	# rewire a choice, then undo back to the original target
	editor._on_connection_request(editor.graph_name_for("q"), 1, editor.graph_name_for("rich"), 0)
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "rich")
	undo.undo_last()
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "good", "rewire undo restores previous target")
	# disconnect, then undo
	editor._on_disconnection_request(editor.graph_name_for("q"), 2, editor.graph_name_for("rich"), 0)
	assert_eq(branch.get_node_by_id("q").choices[1].target_node_id, "")
	undo.undo_last()
	assert_eq(branch.get_node_by_id("q").choices[1].target_node_id, "rich")


func test_set_start_undo() -> void:
	editor.get_graph_edit().get_node(NodePath(String(editor.graph_name_for("good")))).selected = true
	editor.set_selection_as_start()
	assert_eq(branch.start_node_id, "good")
	undo.undo_last()
	assert_eq(branch.start_node_id, "q")


func test_move_undo_restores_positions() -> void:
	var original: Vector2 = GraphModel.get_position(branch.get_node_by_id("rich"))
	editor._on_begin_node_move()
	var gnode: GraphNode = editor.get_graph_edit().get_node(NodePath(String(editor.graph_name_for("rich"))))
	gnode.position_offset = original + Vector2(100, 100)
	editor._on_end_node_move()
	assert_eq(GraphModel.get_position(branch.get_node_by_id("rich")), original + Vector2(100, 100))
	undo.undo_last()
	assert_eq(GraphModel.get_position(branch.get_node_by_id("rich")), original, "metadata position restored")
	assert_eq(gnode.position_offset, original, "canvas position restored")


func _control(node_id: String, key: String) -> Control:
	var gname := String(editor.graph_name_for(node_id))
	var gnode := editor.get_graph_edit().get_node(NodePath(gname)) as GraphNode
	return gnode.get_meta(key) if gnode != null and gnode.has_meta(key) else null


func test_inline_text_and_speaker_edit_undo_redo() -> void:
	var text_ctrl := _control("good", "text_edit")
	text_ctrl.set_meta("edit_before", "good end")
	text_ctrl.text = "a better ending"
	editor._commit_field(text_ctrl, "good", "text")
	assert_eq(branch.get_node_by_id("good").text, "a better ending")
	undo.undo_last()
	assert_eq(branch.get_node_by_id("good").text, "good end", "text edit undone")
	assert_eq(text_ctrl.text, "good end", "on-screen field synced to the undone value")
	undo.redo_last()
	assert_eq(branch.get_node_by_id("good").text, "a better ending", "redo reapplies")
	# speaker edit, separate action
	var sp_ctrl := _control("good", "speaker_edit")
	sp_ctrl.set_meta("edit_before", sp_ctrl.text)
	sp_ctrl.text = "narrator"
	editor._commit_field(sp_ctrl, "good", "speaker")
	assert_eq(branch.get_node_by_id("good").speaker_id, "narrator")
	undo.undo_last()
	assert_eq(branch.get_node_by_id("good").speaker_id, "guard", "speaker edit undone")


func test_inline_edit_to_same_value_creates_no_action() -> void:
	var text_ctrl := _control("good", "text_edit")
	text_ctrl.set_meta("edit_before", "good end")
	text_ctrl.text = "good end"  # unchanged
	editor._commit_field(text_ctrl, "good", "text")
	assert_eq(undo.actions.size(), 0, "no-op edit pollutes no history")


func test_rename_node_undo_redo_retargets_links() -> void:
	var id_ctrl := _control("good", "id_edit")
	id_ctrl.set_meta("edit_before", "good")
	id_ctrl.text = "good_end"
	editor._commit_rename(id_ctrl, "good")
	assert_true(branch.has_node_id("good_end"))
	assert_false(branch.has_node_id("good"))
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "good_end", "link retargeted")
	assert_not_null(editor.get_graph_edit().get_node(NodePath(String(editor.graph_name_for("good_end")))), "canvas node remapped to new id")
	undo.undo_last()
	assert_true(branch.has_node_id("good"), "rename undone")
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "good", "link restored")
	undo.redo_last()
	assert_true(branch.has_node_id("good_end"), "redo renames again")


func test_rename_to_duplicate_is_rejected() -> void:
	var id_ctrl := _control("good", "id_edit")
	id_ctrl.set_meta("edit_before", "good")
	id_ctrl.text = "rich"  # already a node id
	editor._commit_rename(id_ctrl, "good")
	assert_eq(undo.actions.size(), 0, "rejected rename creates no action")
	assert_eq(id_ctrl.text, "good", "field reverts to the original id")
	assert_true(branch.has_node_id("good"), "node keeps its id")


func test_choice_text_inline_edit_undo_redo() -> void:
	var ctrl := _control("q", "choice_text_0")
	ctrl.set_meta("edit_before", "choice stay")
	ctrl.text = "Stay calm"
	editor._commit_choice_text(ctrl, "q", 0)
	assert_eq(branch.get_node_by_id("q").choices[0].text, "Stay calm")
	undo.undo_last()
	assert_eq(branch.get_node_by_id("q").choices[0].text, "choice stay", "choice text undone")
	assert_eq(ctrl.text, "choice stay", "on-screen field synced to the undone value")
	undo.redo_last()
	assert_eq(branch.get_node_by_id("q").choices[0].text, "Stay calm", "redo reapplies")


func test_choice_target_inline_edit_undo() -> void:
	var ctrl := _control("q", "choice_target_0") as LineEdit
	assert_eq(ctrl.text, "good")
	ctrl.set_meta("edit_before", "good")
	ctrl.text = "rich"
	editor._commit_choice_target(ctrl, "q", 0)
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "rich")
	undo.undo_last()
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "good")
	assert_eq(ctrl.text, "good", "undo restores the inline field too")
	# empty target = "end the dialogue": connection disappears from the canvas
	ctrl.set_meta("edit_before", "good")
	ctrl.text = ""
	editor._commit_choice_target(ctrl, "q", 0)
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "")
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 2)
	undo.undo_last()
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 3, "undo restores the connection")


func test_choice_target_unknown_rejected() -> void:
	var ctrl := _control("q", "choice_target_1") as LineEdit
	ctrl.set_meta("edit_before", "rich")
	ctrl.text = "nowhere"
	editor._commit_choice_target(ctrl, "q", 1)
	assert_eq(undo.actions.size(), 0, "rejected target creates no action")
	assert_eq(ctrl.text, "rich", "field reverts to the previous target")
	assert_eq(branch.get_node_by_id("q").choices[1].target_node_id, "rich")


func test_auto_number_choices_undo_and_toggle() -> void:
	editor.get_graph_edit().get_node(NodePath(String(editor.graph_name_for("q")))).selected = true
	editor.auto_number_selected_choices()
	var q := branch.get_node_by_id("q")
	assert_eq(q.choices[0].text, "1. choice stay")
	assert_eq(q.choices[2].text, "3. choice secret")
	assert_eq(_control("q", "choice_text_1").text, "2. choice bribe", "fields synced")
	undo.undo_last()
	assert_eq(q.choices[0].text, "choice stay", "numbering undone")
	assert_eq(_control("q", "choice_text_0").text, "choice stay")
	undo.redo_last()
	assert_eq(q.choices[0].text, "1. choice stay")
	# a second application toggles the numbering off (its own undo step)
	editor.auto_number_selected_choices()
	assert_eq(q.choices[0].text, "choice stay")
	assert_eq(q.choices[1].text, "choice bribe")
	assert_eq(undo.actions.size(), 2)


func test_noop_gestures_create_no_actions() -> void:
	# connecting to the same target, disconnecting an empty port, re-setting
	# the same start node: no history pollution
	editor._on_connection_request(editor.graph_name_for("q"), 1, editor.graph_name_for("good"), 0)
	editor._on_disconnection_request(editor.graph_name_for("good"), 0, editor.graph_name_for("rich"), 0)
	editor.get_graph_edit().get_node(NodePath(String(editor.graph_name_for("q")))).selected = true
	editor.set_selection_as_start()
	assert_eq(undo.actions.size(), 0)

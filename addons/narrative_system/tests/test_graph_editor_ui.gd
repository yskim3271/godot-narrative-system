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


func test_switching_dialogues_rebuilds() -> void:
	assert_true(editor.open_dialogue("linear"))
	assert_eq(_graph_nodes().size(), 3)
	assert_eq(editor.get_graph_edit().get_connection_list().size(), 2, "n1->n2->n3 next links")
	assert_false(editor.open_dialogue("ghost_dialogue"))
	assert_eq(editor.current_dialogue().id, "linear", "failed open keeps the current dialogue")

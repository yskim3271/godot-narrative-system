extends "res://addons/narrative_system/tests/harness/test_case.gd"
## Graph-editing model: structure ops, link ops, layout, id generation.

const DbFactory := preload("res://addons/narrative_system/tests/fixtures/db_factory.gd")
const GraphModel := preload("res://addons/narrative_system/editor/dialogue_graph_model.gd")

var db: NarrativeDatabase
var branch: NarrativeDialogue


func before_each() -> void:
	db = DbFactory.standard()
	branch = db.get_dialogue("branch")


func test_generate_node_id_skips_existing() -> void:
	var dialogue := DbFactory.make_dialogue("g", "n1", [
		DbFactory.make_node("n1", {}), DbFactory.make_node("n5", {}),
	])
	assert_eq(GraphModel.generate_node_id(dialogue), "n3", "size+1 = 3, free")
	GraphModel.add_node(dialogue, "n3")
	assert_eq(GraphModel.generate_node_id(dialogue), "n4")
	GraphModel.add_node(dialogue, "n4")
	assert_eq(GraphModel.generate_node_id(dialogue), "n6", "n5 exists, skip to n6")


func test_add_node_appends_with_position() -> void:
	var before := branch.nodes.size()
	var node := GraphModel.add_node(branch, "", Vector2(100, 50))
	assert_not_null(node)
	assert_eq(branch.nodes.size(), before + 1)
	assert_true(branch.has_node_id(node.id))
	assert_eq(GraphModel.get_position(node), Vector2(100, 50))
	assert_null(GraphModel.add_node(branch, node.id), "duplicate id rejected")
	assert_null(GraphModel.add_node(branch, "bad id!"), "invalid charset rejected")


func test_add_first_node_becomes_start() -> void:
	var dialogue := NarrativeDialogue.new()
	dialogue.id = "fresh"
	var node := GraphModel.add_node(dialogue)
	assert_eq(dialogue.start_node_id, node.id, "first node of an empty dialogue becomes the start")


func test_delete_node_cleans_references() -> void:
	# branch: q has choices stay->good, bribe->rich, secret->hidden_path
	var report := GraphModel.delete_node(branch, "good")
	assert_true(bool(report.removed))
	assert_eq(int(report.cleaned_links), 1, "stay's target cleared")
	assert_false(bool(report.was_start))
	assert_eq(branch.nodes.size(), 3)
	var stay: NarrativeChoice = branch.get_node_by_id("q").choices[0]
	assert_eq(stay.target_node_id, "")
	# deleting the start node clears start_node_id
	var report2 := GraphModel.delete_node(branch, "q")
	assert_true(bool(report2.was_start))
	assert_eq(branch.start_node_id, "")
	# unknown id is a no-op
	assert_false(bool(GraphModel.delete_node(branch, "ghost").removed))


func test_delete_cleans_next_references() -> void:
	var linear := db.get_dialogue("linear")  # n1 -> n2 -> n3
	var report := GraphModel.delete_node(linear, "n2")
	assert_eq(int(report.cleaned_links), 1, "n1.next cleared")
	assert_eq(linear.get_node_by_id("n1").next_node_id, "")


func test_set_next_and_disconnect() -> void:
	assert_true(GraphModel.set_next(branch, "good", "rich"))
	assert_eq(branch.get_node_by_id("good").next_node_id, "rich")
	assert_true(GraphModel.set_next(branch, "good", ""), "empty target disconnects")
	assert_eq(branch.get_node_by_id("good").next_node_id, "")
	assert_false(GraphModel.set_next(branch, "ghost", "rich"))
	assert_false(GraphModel.set_next(branch, "good", "ghost"))


func test_set_choice_target_and_bounds() -> void:
	assert_true(GraphModel.set_choice_target(branch, "q", 0, "rich"))
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "rich")
	assert_true(GraphModel.set_choice_target(branch, "q", 0, ""))
	assert_eq(branch.get_node_by_id("q").choices[0].target_node_id, "")
	assert_false(GraphModel.set_choice_target(branch, "q", 99, "rich"))
	assert_false(GraphModel.set_choice_target(branch, "q", -1, "rich"))
	assert_false(GraphModel.set_choice_target(branch, "q", 1, "ghost"))


func test_connections_ports_and_broken_links_omitted() -> void:
	var connections := GraphModel.connections(branch)
	assert_eq(connections.size(), 3, "three choice links, no next links")
	assert_eq(connections[0], {"from_id": "q", "port": 1, "to_id": "good"})
	assert_eq(connections[1], {"from_id": "q", "port": 2, "to_id": "rich"})
	assert_eq(connections[2], {"from_id": "q", "port": 3, "to_id": "hidden_path"})
	# next links use port 0; broken targets are omitted
	GraphModel.set_next(branch, "good", "rich")
	branch.get_node_by_id("q").choices[0].target_node_id = "ghost"
	var updated := GraphModel.connections(branch)
	assert_contains(updated, {"from_id": "good", "port": 0, "to_id": "rich"})
	assert_eq(updated.size(), 3, "broken choice link omitted, next link added")


func test_set_start() -> void:
	assert_true(GraphModel.set_start(branch, "good"))
	assert_eq(branch.start_node_id, "good")
	assert_false(GraphModel.set_start(branch, "ghost"))
	assert_eq(branch.start_node_id, "good")


func test_auto_layout_layers_and_unreachable() -> void:
	var positioned := GraphModel.auto_layout(branch)
	assert_eq(positioned, 4, "all four nodes had no position")
	var origin := GraphModel.LAYOUT_ORIGIN
	assert_eq(GraphModel.get_position(branch.get_node_by_id("q")), origin, "start at depth 0")
	# depth-1 nodes occupy distinct rows in column 1
	var seen_positions := {}
	for node_id in ["good", "rich", "hidden_path"]:
		var pos := GraphModel.get_position(branch.get_node_by_id(node_id))
		assert_almost_eq(pos.x, origin.x + GraphModel.LAYOUT_COLUMN_WIDTH)
		assert_false(seen_positions.has(pos), "no overlapping positions")
		seen_positions[pos] = true
	# already-positioned nodes are untouched; new unreachable node parks in the next column
	var island := GraphModel.add_node(branch, "island")
	island.metadata.erase(GraphModel.POSITION_KEY)
	assert_eq(GraphModel.auto_layout(branch), 1)
	assert_almost_eq(GraphModel.get_position(island).x, origin.x + 2 * GraphModel.LAYOUT_COLUMN_WIDTH)
	assert_eq(GraphModel.auto_layout(branch), 0, "second pass positions nothing")


func test_create_dialogue_with_start_node() -> void:
	var created := GraphModel.create_dialogue(db, "brand_new")
	assert_not_null(created)
	assert_not_null(db.get_dialogue("brand_new"))
	assert_eq(created.start_node_id, "start")
	assert_eq(created.nodes.size(), 1)
	assert_null(GraphModel.create_dialogue(db, "brand_new"), "duplicate dialogue id rejected")
	assert_null(GraphModel.create_dialogue(db, "bad id!"))
	var auto_named := GraphModel.create_dialogue(db)
	assert_true(auto_named.id.begins_with("dialogue_"))


func test_position_metadata_survives_tres_roundtrip() -> void:
	var node := branch.get_node_by_id("q")
	GraphModel.set_position(node, Vector2(123, 456))
	var err := ResourceSaver.save(branch, "user://t_graph_roundtrip.tres")
	assert_eq(err, OK)
	var loaded := ResourceLoader.load("user://t_graph_roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as NarrativeDialogue
	assert_not_null(loaded)
	assert_eq(GraphModel.get_position(loaded.get_node_by_id("q")), Vector2(123, 456))
	DirAccess.remove_absolute("user://t_graph_roundtrip.tres")
